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
## ---------------------------------------------------------------

bis_wstc_dims <- c("FREQ", "BORROWERS_CTY", "TC_BORROWERS", "TC_LENDERS",
                    "VALUATION", "UNIT_TYPE", "TC_ADJUST")

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

#' Fetch BIS credit to a given borrower sector, as % of GDP
#'
#' `country2` is a 2-letter BIS/FRED-style country code (e.g. "DE", "US").
#' `tc_borrowers` selects the borrower sector (see CL_TC_BORROWERS above);
#' defaults to "P" (private non-financial sector), the series verified in
#' the original pass. Credit from all lenders (TC_LENDERS = "A"), market
#' value (VALUATION = "M"), percentage of GDP (UNIT_TYPE = "770"), adjusted
#' for breaks (TC_ADJUST = "A") -- this exact combination returned real
#' quarterly observations for both DE and US on verification.
fetch_bis_credit <- function(country2, tc_borrowers = "P",
                              label = "credit_to_private_nonfin_sector",
                              start_period = "1995-Q1") {
  dims <- c(FREQ = "Q", BORROWERS_CTY = country2, TC_BORROWERS = tc_borrowers,
            TC_LENDERS = "A", VALUATION = "M", UNIT_TYPE = "770", TC_ADJUST = "A")
  key <- build_sdmx_key(dims[bis_wstc_dims])

  url <- paste0(
    "https://stats.bis.org/api/v2/data/dataflow/BIS/WS_TC/2.0/", key,
    "?format=csv&startPeriod=", start_period
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] BIS credit fetch failed for %s -- verify manually at https://data.bis.org/topics/CRE",
                     label, country2))
    return(NULL)
  }

  if (stringr::str_detect(txt, stringr::regex("<message:Error|No structures match", ignore_case = TRUE))) {
    warning(sprintf("[%s] BIS returned no observations for key '%s'", label, key))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) return(NULL)

  df %>%
    dplyr::transmute(period = .data$TIME_PERIOD, !!label := as.numeric(.data$OBS_VALUE)) %>%
    dplyr::distinct(period, .keep_all = TRUE)
}
