## ---------------------------------------------------------------
## bis.R -- BIS Credit to the Non-Financial Sector, BIS's own SDMX API
##
## STATUS: VERIFIED 2026-08-30. Dataflow, version, dimension order and
## every code below were confirmed live against stats.bis.org (structure
## query + real 200 responses with data for DE and US), not guessed.
##
## Corrections vs. the original script's guess:
##   - Dataflow is BIS:WS_TC version 2.0, not 1.0 (a hardcoded "1.0" in
##     the URL path returns a generic "No structures match query
##     parameters" error even though WS_TC itself exists).
##   - Real dimension order (7 dims, confirmed via the DSD): FREQ.
##     BORROWERS_CTY.TC_BORROWERS.TC_LENDERS.VALUATION.UNIT_TYPE.
##     TC_ADJUST -- the original script guessed 8 dimensions with
##     different names/order (FREQ.BORROWERS_CTY.LENDING_SECTOR.
##     BORROWING_SECTOR.UNIT_TYPE.VALUATION.TC_ADJUST.TC_SUFFIX).
##   - BORROWERS_CTY takes FRED-style 2-letter codes (e.g. "DE", "US"),
##     not ISO-3166 alpha-3.
##
## EXTENDED 2026-08-30: `fetch_bis_credit()` gained a `tc_borrowers`
## parameter so the same verified dataflow/key can also pull
## household-only and nonfinancial-corporation-only credit-to-GDP (codes
## "H" and "N" in CL_TC_BORROWERS, confirmed live for AT/DE/US), rather
## than only the combined "private non-financial sector" aggregate ("P").
## This fills two gaps: it gives Household Balance Sheets a genuinely
## country-specific series (unlike ecb.R's euro-area-only net worth), and
## it gives Non-Household Balance Sheets a first real concept where
## previously nothing was attempted.
##
## EXTENDED AGAIN 2026-08-30: leaving BORROWERS_CTY blank (a wildcard in
## SDMX REST key syntax) was confirmed live to return EVERY country BIS
## has for a given TC_BORROWERS sector in one request (48 countries, one
## call, ~200KB from 2020-Q1) rather than erroring -- so `fetch_bis_credit()`
## now routes through `fetch_bis_credit_bulk()`, which fetches all
## countries at once per sector and caches the result in `data/landing/`
## (gitignored, refreshed only when the cache file is absent -- same
## manual-refresh convention as `data/bronze/`'s OECD pulls). Building
## panels for AUT, then DEU, then USA in one sitting now downloads each
## of the 3 sectors (P/H/N) ONCE total, not once per country.
## ---------------------------------------------------------------

bis_wstc_dims <- c("FREQ", "BORROWERS_CTY", "TC_BORROWERS", "TC_LENDERS",
                    "VALUATION", "UNIT_TYPE", "TC_ADJUST")
bis_landing_dir <- "data/landing"

## TC_BORROWERS codelist (CL_TC_BORROWERS), confirmed live 2026-08-30 via
## the WS_TC dataflow structure query -- used to extend credit-to-GDP
## beyond the single "private non-financial sector" aggregate to the two
## sector breakdowns FRED-QD keeps separate (households vs. nonfinancial
## corporations):
##   C - Non financial sector (economy-wide, incl. general government)
##   G - General government
##   H - Households & NPISHs           <- household_credit_to_gdp
##   N - Non-financial corporations    <- corporate_credit_to_gdp
##   P - Private non-financial sector  <- credit_to_private_nonfin_sector (default, unchanged)
## All three (P, H, N) confirmed to return real quarterly observations for
## AT, DE and US (e.g. AT/H = 49.6% of GDP, AT/N = 94.6% of GDP in 2020-Q1).

#' Local cache path for one sector's all-countries bulk pull
bis_landing_path <- function(tc_borrowers, landing_dir = bis_landing_dir) {
  file.path(landing_dir, sprintf("bis_credit_%s.csv", tc_borrowers))
}

#' Fetch BIS credit-to-GDP for ALL countries at once, for one borrower
#' sector, caching the result locally
#'
#' Returns a `country2, period, value` tibble (BIS's own 2-letter codes,
#' e.g. "DE", "US", not ISO-3166 alpha-3). NOTE: the cache is keyed only
#' by `tc_borrowers`, not `start_period` -- since every caller in this
#' project uses the same "1995-Q1" default, this doesn't matter in
#' practice, but a cached pull from a later `start_period` would silently
#' lack earlier data for a caller requesting more history. Delete the
#' cache file to force a refresh (same manual-refresh convention as
#' `data/bronze/`'s OECD pulls).
fetch_bis_credit_bulk <- function(tc_borrowers, start_period = "1995-Q1",
                                   landing_dir = bis_landing_dir) {
  cache_path <- bis_landing_path(tc_borrowers, landing_dir)
  if (file.exists(cache_path)) {
    return(suppressMessages(readr::read_csv(cache_path, show_col_types = FALSE)))
  }

  dims <- c(FREQ = "Q", BORROWERS_CTY = "", TC_BORROWERS = tc_borrowers,
            TC_LENDERS = "A", VALUATION = "M", UNIT_TYPE = "770", TC_ADJUST = "A")
  key <- build_sdmx_key(dims[bis_wstc_dims])
  url <- paste0(
    "https://stats.bis.org/api/v2/data/dataflow/BIS/WS_TC/2.0/", key,
    "?format=csv&startPeriod=", start_period
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("BIS bulk credit fetch failed for TC_BORROWERS=%s -- verify manually at https://data.bis.org/topics/CRE", tc_borrowers))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("<message:Error|No structures match", ignore_case = TRUE))) {
    warning(sprintf("BIS returned no observations for bulk key TC_BORROWERS=%s", tc_borrowers))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("BORROWERS_CTY", "TIME_PERIOD", "OBS_VALUE") %in% names(df))) return(NULL)

  out <- df %>%
    dplyr::transmute(country2 = .data$BORROWERS_CTY, period = .data$TIME_PERIOD,
                      value = as.numeric(.data$OBS_VALUE)) %>%
    dplyr::distinct(country2, period, .keep_all = TRUE)

  dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(out, cache_path)
  out
}

#' Fetch BIS credit to a given borrower sector, as % of GDP, for ONE
#' country -- from the cached (or freshly-fetched) all-countries pull
#'
#' `country2` is a 2-letter BIS/FRED-style country code (e.g. "DE", "US").
#' `tc_borrowers` selects the borrower sector (see CL_TC_BORROWERS above);
#' defaults to "P" (private non-financial sector), the series verified in
#' the original pass.
fetch_bis_credit <- function(country2, tc_borrowers = "P",
                              label = "credit_to_private_nonfin_sector",
                              start_period = "1995-Q1",
                              landing_dir = bis_landing_dir) {
  bulk <- fetch_bis_credit_bulk(tc_borrowers, start_period = start_period, landing_dir = landing_dir)
  if (is.null(bulk)) return(NULL)

  out <- bulk %>%
    dplyr::filter(.data$country2 == .env$country2) %>%
    dplyr::distinct(period, .keep_all = TRUE) %>%
    dplyr::select(period, value)
  if (nrow(out) == 0) {
    warning(sprintf("[%s] BIS bulk data has no observations for country '%s' (TC_BORROWERS=%s)", label, country2, tc_borrowers))
    return(NULL)
  }
  names(out)[2] <- label
  out
}
