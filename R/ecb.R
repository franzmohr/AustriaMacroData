## ---------------------------------------------------------------
## ecb.R -- Household net worth via ECB's Quarterly Sector Accounts
##
## STATUS: VERIFIED 2026-08-30, with an important correction to the
## original script's premise.
##
## The original script assumed household net worth would be available
## PER COUNTRY for euro-area members (e.g. separate DEU, AUT, FRA
## series) and only needed its SDMX key guessed correctly. That premise
## is wrong: confirmed live against data-api.ecb.europa.eu that the
## dataflow is ECB.DISS:QSA_PUB ("Quarterly Sector Accounts ... table
## 801 -- Published series", agency ECB.DISS, not plain "ECB" as
## guessed), and that for STO = B90 (net worth), REF_SECTOR = S1M
## (households + NPISH), the ONLY REF_AREA with actual observations is
## "I8" (the fixed-composition euro area aggregate) -- individual member
## countries (DE, AT, FR, ...) return zero observations. This was
## confirmed by listing the dataflow's real series keys, not by
## exhausting guesses.
##
## Consequently this module does NOT return a country-specific series.
## It returns the euro-area aggregate, clearly labeled as such, for any
## euro-area country -- useful as a common regional control variable,
## but it must not be presented as e.g. "Germany's household net
## worth". Also note the only available TRANSFORMATION found (G4) is a
## growth rate, not a level (title: "Net worth of households (growth
## rate)"); no verified level series was found in the time available.
##
## Dimension order (18 dims, confirmed via the DSD, dataflow
## ECB.DISS:QSA_PUB v1.0): FREQ.ADJUSTMENT.REF_AREA.COUNTERPART_AREA.
## REF_SECTOR.COUNTERPART_SECTOR.CONSOLIDATION.ACCOUNTING_ENTRY.STO.
## INSTR_ASSET.MATURITY.EXPENDITURE.UNIT_MEASURE.CURRENCY_DENOM.
## VALUATION.PRICES.TRANSFORMATION.CUST_BREAKDOWN -- completely
## different in both names and count from the original script's
## 18-segment guess (which happened to match the segment count by
## coincidence but not a single dimension name past REF_AREA).
## ---------------------------------------------------------------

ecb_qsa_dims <- c("FREQ", "ADJUSTMENT", "REF_AREA", "COUNTERPART_AREA", "REF_SECTOR",
                   "COUNTERPART_SECTOR", "CONSOLIDATION", "ACCOUNTING_ENTRY", "STO",
                   "INSTR_ASSET", "MATURITY", "EXPENDITURE", "UNIT_MEASURE",
                   "CURRENCY_DENOM", "VALUATION", "PRICES", "TRANSFORMATION", "CUST_BREAKDOWN")

euro_area_countries <- c("AUT", "BEL", "CYP", "EST", "FIN", "FRA", "DEU", "GRC", "IRL",
                          "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "PRT", "SVK", "SVN", "ESP")

#' Fetch the euro-area aggregate household net-worth growth rate
#'
#' Returns NULL (with a warning) if `country3` is not a euro-area member,
#' since the series is not meaningful for non-euro-area countries. Always
#' returns the SAME series regardless of which euro-area country was
#' requested -- see module header. Column is named
#' "euro_area_household_net_worth_growth", not e.g. "{country}_..." on
#' purpose, so callers can't mistake it for a country-specific figure.
fetch_ecb_household_networth <- function(country3, start_period = "1995-Q1") {
  if (!(country3 %in% euro_area_countries)) {
    warning(sprintf("ECB household net worth: %s is not a euro-area country -- skipping (no euro-area-independent source exists)", country3))
    return(NULL)
  }

  label <- "euro_area_household_net_worth_growth"
  dims <- c(FREQ = "Q", ADJUSTMENT = "N", REF_AREA = "I8", COUNTERPART_AREA = "W0",
            REF_SECTOR = "S1M", COUNTERPART_SECTOR = "S1", CONSOLIDATION = "_Z",
            ACCOUNTING_ENTRY = "B", STO = "B90", INSTR_ASSET = "_Z", MATURITY = "_Z",
            EXPENDITURE = "_Z", UNIT_MEASURE = "XDC", CURRENCY_DENOM = "_T",
            VALUATION = "S", PRICES = "V", TRANSFORMATION = "G4", CUST_BREAKDOWN = "_T")
  key <- build_sdmx_key(dims[ecb_qsa_dims])

  url <- paste0(
    "https://data-api.ecb.europa.eu/service/data/ECB.DISS,QSA_PUB,1.0/", key,
    "?format=csvdata&startPeriod=", start_period
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning("ECB household net worth fetch failed -- this is the euro-area aggregate (REF_AREA=I8); verify manually at https://data.ecb.europa.eu")
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning("ECB household net worth: unexpected response shape, inspect manually")
    return(NULL)
  }

  df %>%
    dplyr::transmute(period = .data$TIME_PERIOD, !!label := as.numeric(.data$OBS_VALUE)) %>%
    dplyr::distinct(period, .keep_all = TRUE)
}
