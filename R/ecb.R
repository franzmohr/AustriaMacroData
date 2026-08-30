## ---------------------------------------------------------------
## ecb.R -- Household net worth (Quarterly Sector Accounts) and mortgage
## interest rates (MFI Interest Rate Statistics), both from the ECB
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

## ---------------------------------------------------------------
## mortgage_rate -- ECB MFI Interest Rate Statistics (MIR), the natural
## analog to FRED-QD's MORTGAGE30US (Interest Rates group)
##
## STATUS: VERIFIED 2026-08-30. Dataflow MIR, key dimension order (10
## segments, confirmed straight from the API's own CSV header row, not
## guessed): FREQ.REF_AREA.BS_REP_SECTOR.BS_ITEM.MATURITY_NOT_IRATE.
## DATA_TYPE_MIR.AMOUNT_CAT.BS_COUNT_SECTOR.CURRENCY_TRANS.IR_BUS_COV.
## Series "Bank interest rates - loans to households for house purchase
## (new business)": M.<cc2>.B.A2C.A.R.A.2250.EUR.N -- confirmed with
## real, CURRENT (through 2026-06) monthly data for BOTH AT (3.54%) and
## DE (3.95%), and a clean 404 (not a hang or garbage) for a non-euro-
## area country (US). UNLIKE `fetch_ecb_household_networth()` above,
## this genuinely IS country-specific -- every euro-area member has its
## own series, not a shared aggregate.
## ---------------------------------------------------------------

ecb_mir_dims <- c("FREQ", "REF_AREA", "BS_REP_SECTOR", "BS_ITEM", "MATURITY_NOT_IRATE",
                   "DATA_TYPE_MIR", "AMOUNT_CAT", "BS_COUNT_SECTOR", "CURRENCY_TRANS", "IR_BUS_COV")

#' Fetch the mortgage interest rate (new business, loans to households
#' for house purchase) for one euro-area country
#'
#' Returns NULL (with a warning) if `country3` is not a euro-area member
#' or has no FRED 2-letter code known (reused as the ECB REF_AREA code,
#' confirmed identical for AT/DE).
fetch_ecb_mortgage_rate <- function(country3, label = "mortgage_rate", start_period = "1995-Q1") {
  if (!(country3 %in% euro_area_countries)) {
    warning(sprintf("[%s] ECB mortgage rate: %s is not a euro-area country -- skipping", label, country3))
    return(NULL)
  }
  country2 <- lookup_country2(country3)
  if (is.na(country2)) return(NULL)

  dims <- c(FREQ = "M", REF_AREA = country2, BS_REP_SECTOR = "B", BS_ITEM = "A2C",
            MATURITY_NOT_IRATE = "A", DATA_TYPE_MIR = "R", AMOUNT_CAT = "A",
            BS_COUNT_SECTOR = "2250", CURRENCY_TRANS = "EUR", IR_BUS_COV = "N")
  key <- build_sdmx_key(dims[ecb_mir_dims])

  ## MIR is monthly (FREQ=M); start_period here is a "YYYY-Qn" string like
  ## everywhere else in this project, so it's converted to the "YYYY-MM"
  ## the API expects for a monthly startPeriod.
  start_month <- format(period_to_date(start_period), "%Y-%m")
  url <- paste0(
    "https://data-api.ecb.europa.eu/service/data/MIR/", key,
    "?format=csvdata&startPeriod=", start_month
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] ECB mortgage rate fetch failed for %s -- verify manually at https://data.ecb.europa.eu", label, country3))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex('"status":\\s*404|No Series was returned', ignore_case = TRUE))) {
    warning(sprintf("[%s] ECB has no mortgage-rate observations for %s", label, country3))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] ECB mortgage rate: unexpected response shape, inspect manually", label))
    return(NULL)
  }

  monthly <- df %>%
    dplyr::transmute(
      date = as.Date(paste0(.data$TIME_PERIOD, "-01")),
      value = as.numeric(.data$OBS_VALUE)
    ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value)) %>%
    dplyr::distinct(date, .keep_all = TRUE)
  names(monthly)[2] <- label

  monthly_to_quarterly(monthly, label) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}
