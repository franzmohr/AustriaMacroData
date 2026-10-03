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

## ---------------------------------------------------------------
## Pure new loans for house purchase -- the same MIR dataflow and the
## same loan category as `mortgage_rate`, at IR_BUS_COV=P ("pure new
## loans") instead of N ("new business").
##
## STATUS: VERIFIED 2026-10-03. Both keys were confirmed live against
## data-api.ecb.europa.eu with real, current monthly observations for AT
## (2017-08 to 2026-08), the series titles reading "Bank business volumes
## - loans to households for house purchase (pure new loans)" and "Bank
## interest rates - loans to households for house purchase (pure new
## loans)" -- and for DE with only REF_AREA changed (2026-08: EUR
## 15,113 million at 4.02%, against AT's EUR 1,284 million at 3.64%):
##   MIR.M.AT.B.A2C.A.B.A.2250.EUR.P  volume, DATA_TYPE_MIR=B, EUR millions
##                                    (UNIT=EUR, UNIT_MULT=6), COLLECTION=S
##   MIR.M.AT.B.A2C.A.R.A.2250.EUR.P  rate, DATA_TYPE_MIR=R, percent p.a.,
##                                    COLLECTION=A
##
## WHY "PURE". New business (N) counts every contract whose terms were
## agreed in the month, including renegotiations of loans already on the
## books, and refinancing waves move those independently of house
## purchases. Pure new loans (P) leave
## renegotiations out, so the volume is the closest monthly measure of
## new mortgage lending there is for a euro-area country. The history is
## short: the P series start in 2017-08 for Austria, against 2003 for N.
##
## THE VOLUME IS A FLOW. COLLECTION=S says it: each month's figure is the
## sum of the contracts agreed in that month. A quarter's figure is
## therefore the SUM of its three months, not their average, and a
## quarter that is not yet complete is left out rather than summed over
## the months it has -- a two-month sum would show up as a one-third
## collapse in lending that never happened. The rate is a period average
## (COLLECTION=A) and is averaged like `mortgage_rate`.
## ---------------------------------------------------------------

#' Fetch one monthly MIR series for house-purchase loans to households
#'
#' Shared by `fetch_ecb_mortgage_rate()`, `fetch_ecb_mortgage_rate_pure_new()`
#' and `fetch_ecb_mortgage_new_lending()`, which differ only in two key
#' segments, in how a quarter is formed, and in what their warnings call
#' the series. `aggregate = "sum"` sums complete quarters (for a flow);
#' "mean" averages, as every other monthly source in this project does.
fetch_ecb_mir_house_purchase <- function(country3, label, data_type, bus_cov, what,
                                         start_period = "1995-Q1", frequency = "Q",
                                         aggregate = c("mean", "sum")) {
  aggregate <- match.arg(aggregate)
  if (!(country3 %in% euro_area_countries)) {
    warning(sprintf("[%s] ECB %s: %s is not a euro-area country -- skipping", label, what, country3))
    return(NULL)
  }
  country2 <- lookup_country2(country3)
  if (is.na(country2)) return(NULL)

  dims <- c(FREQ = "M", REF_AREA = country2, BS_REP_SECTOR = "B", BS_ITEM = "A2C",
            MATURITY_NOT_IRATE = "A", DATA_TYPE_MIR = data_type, AMOUNT_CAT = "A",
            BS_COUNT_SECTOR = "2250", CURRENCY_TRANS = "EUR", IR_BUS_COV = bus_cov)
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
    warning(sprintf("[%s] ECB %s fetch failed for %s -- verify manually at https://data.ecb.europa.eu", label, what, country3))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex('"status":\\s*404|No Series was returned', ignore_case = TRUE))) {
    warning(sprintf("[%s] ECB has no %s observations for %s", label, gsub(" ", "-", what), country3))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] ECB %s: unexpected response shape, inspect manually", label, what))
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

  out <- if (identical(aggregate, "sum") && identical(check_frequency(frequency), "Q")) {
    monthly_to_quarterly_sum(monthly, label)
  } else {
    aggregate_to(monthly, label, frequency)
  }
  out %>% dplyr::filter(.data$date >= period_to_date(start_period))
}

#' Fetch the mortgage interest rate (new business, loans to households
#' for house purchase) for one euro-area country
#'
#' Returns NULL (with a warning) if `country3` is not a euro-area member
#' or has no FRED 2-letter code known (reused as the ECB REF_AREA code,
#' confirmed identical for AT/DE).
fetch_ecb_mortgage_rate <- function(country3, label = "mortgage_rate", start_period = "1995-Q1",
                                    frequency = "Q") {
  fetch_ecb_mir_house_purchase(country3, label, data_type = "R", bus_cov = "N",
                               what = "mortgage rate", start_period = start_period,
                               frequency = frequency)
}

#' Fetch the interest rate on PURE new loans to households for house
#' purchase (renegotiations excluded) for one euro-area country
fetch_ecb_mortgage_rate_pure_new <- function(country3, label = "mortgage_rate_pure_new_loans",
                                             start_period = "1995-Q1", frequency = "Q") {
  fetch_ecb_mir_house_purchase(country3, label, data_type = "R", bus_cov = "P",
                               what = "pure-new-loan mortgage rate", start_period = start_period,
                               frequency = frequency)
}

#' Fetch the volume of PURE new loans to households for house purchase
#' (millions of EUR per period, renegotiations excluded) for one
#' euro-area country -- summed, not averaged, into quarters
fetch_ecb_mortgage_new_lending <- function(country3, label = "mortgage_new_lending",
                                           start_period = "1995-Q1", frequency = "Q") {
  fetch_ecb_mir_house_purchase(country3, label, data_type = "B", bus_cov = "P",
                               what = "new mortgage lending", start_period = start_period,
                               frequency = frequency, aggregate = "sum")
}

## ---------------------------------------------------------------
## household_mortgage_loans -- ECB MFI Balance Sheet Items (BSI),
## outstanding amounts of loans to households for house purchase. Pairs
## with `mortgage_rate` above (same purpose category, same "loans to
## households for house purchase" concept, but a STOCK instead of a
## RATE) -- the natural analog to FRED-QD's REALLNx (Money and Credit).
##
## STATUS: VERIFIED 2026-08-30. This dataflow (BSI) has a DIFFERENT
## dimension order and DIFFERENT codes from MIR above, despite both
## being ECB MFI statistics about the same underlying loan category --
## confirmed via a live structure query (dataflow/ECB/BSI, 11 key
## segments): FREQ.REF_AREA.ADJUSTMENT.BS_REP_SECTOR.BS_ITEM.
## MATURITY_ORIG.DATA_TYPE.COUNT_AREA.BS_COUNT_SECTOR.CURRENCY_TRANS.
## BS_SUFFIX. Blind key construction from first principles (by analogy
## with MIR's codes) repeatedly returned a structurally valid "zero
## observations" 404, even for the simplest total-loans case -- the
## working key was instead found by searching the ECB Data Portal's own
## published series list (data.ecb.europa.eu) for "loans households
## house purchase Austria", which surfaces real, human-readable series
## titles alongside their exact SDMX keys.
##
## The confirmed key for Austria -- "Adjusted loans, lending for house
## purchase to DOMESTIC households granted by MFIs excluding NCB,
## Stocks": BSI.M.AT.N.A.A22T.A.1.U6.2250.Z01.E. Segment-by-segment:
## ADJUSTMENT=N (not seasonally adjusted), BS_REP_SECTOR=A (MFIs
## excluding ESCB), BS_ITEM=A22T ("T" = the adjusted/total loans
## variant of A22 "Lending for house purchase" -- plain "A22" alone
## returns zero observations here, unlike in MIR's BS_ITEM dimension),
## MATURITY_ORIG=A (total), DATA_TYPE=1 (outstanding amounts/stocks),
## COUNT_AREA=U6 (domestic/home area -- NOT "U2" euro area, which is a
## real but DIFFERENT published series: loans to households anywhere in
## the euro area, not just this country's own residents),
## BS_COUNT_SECTOR=2250 (households and NPISH, same code as MIR),
## CURRENCY_TRANS=Z01 (all currencies combined), BS_SUFFIX=E (Euro,
## i.e. the amount is denominated in EUR, not a growth rate or index).
## Confirmed live and CURRENT (through 2026-07) for both AT (EUR 133.0
## billion) and DE (EUR 1,658.4 billion) with only REF_AREA changed.
##
## Data starts 2014-12 for Austria (shorter history than MIR's rate
## series, which goes back to 2003) -- a genuine coverage limit of this
## dataflow, not a code error.
##
## Unit: millions of EUR (confirmed via the response's own UNIT/
## UNIT_MULT metadata columns, not assumed) -- reported as-is, NOT
## deflated to real terms the way FRED-QD's REALLNx is (see
## concept_group_map's us_note in scripts/build_country_panel.R).
## ---------------------------------------------------------------

ecb_bsi_dims <- c("FREQ", "REF_AREA", "ADJUSTMENT", "BS_REP_SECTOR", "BS_ITEM",
                   "MATURITY_ORIG", "DATA_TYPE", "COUNT_AREA", "BS_COUNT_SECTOR",
                   "CURRENCY_TRANS", "BS_SUFFIX")

#' Fetch outstanding household house-purchase loans (millions of EUR) for
#' one euro-area country
#'
#' Returns NULL (with a warning) if `country3` is not a euro-area member.
fetch_ecb_household_mortgage_loans <- function(country3, label = "household_mortgage_loans",
                                                start_period = "1995-Q1",
                                                frequency = "Q") {
  if (!(country3 %in% euro_area_countries)) {
    warning(sprintf("[%s] ECB household mortgage loans: %s is not a euro-area country -- skipping", label, country3))
    return(NULL)
  }
  country2 <- lookup_country2(country3)
  if (is.na(country2)) return(NULL)

  dims <- c(FREQ = "M", REF_AREA = country2, ADJUSTMENT = "N", BS_REP_SECTOR = "A",
            BS_ITEM = "A22T", MATURITY_ORIG = "A", DATA_TYPE = "1", COUNT_AREA = "U6",
            BS_COUNT_SECTOR = "2250", CURRENCY_TRANS = "Z01", BS_SUFFIX = "E")
  key <- build_sdmx_key(dims[ecb_bsi_dims])

  start_month <- format(period_to_date(start_period), "%Y-%m")
  url <- paste0(
    "https://data-api.ecb.europa.eu/service/data/BSI/", key,
    "?format=csvdata&startPeriod=", start_month
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] ECB household mortgage loans fetch failed for %s -- verify manually at https://data.ecb.europa.eu", label, country3))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex('"status":\\s*404|No Series was returned', ignore_case = TRUE))) {
    warning(sprintf("[%s] ECB has no household-mortgage-loan observations for %s", label, country3))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] ECB household mortgage loans: unexpected response shape, inspect manually", label))
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

  aggregate_to(monthly, label, frequency) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}

## ---------------------------------------------------------------
## financial_stress -- the ECB's country-level Composite Indicator of
## Systemic Stress (CISS)
##
## STATUS: VERIFIED 2026-09-14. Dataflow CISS, key dimension order (7
## segments, confirmed from the API's own CSV header row, not guessed):
## FREQ.REF_AREA.CURRENCY.PROVIDER_FM.INSTRUMENT_FM.PROVIDER_FM_ID.
## DATA_TYPE_FM. Series "Austria, New Composite Indicator of Systemic
## Stress (CISS), Index": D.AT.Z0Z.4F.EC.SS_CIN.IDX -- confirmed with
## real, CURRENT (through 2026-09-11) daily data for AT, DE, US and GB.
##
## Only a DAILY series exists: the same key with FREQ=M is a clean 404,
## so the daily values are averaged to calendar quarters here (the
## current quarter is the mean of the days published so far). Unlike the
## MIR and BSI series above the index is not restricted to the euro area,
## so it is attempted for every country and resolves to NA only where the
## ECB publishes nothing. The FRED 2-letter code doubles as REF_AREA, as
## for MIR (confirmed identical for AT, DE and US).
##
## Coverage differs by country, and the response does not show it at a
## glance: rows go back to 1980 for every country, but for Austria they
## carry an empty OBS_VALUE until 1999-01-05 (Germany starts 1980-01-04,
## the United States 1980-01-02). Empty rows are dropped before
## aggregating, so a quarter is never averaged over missing days.
## ---------------------------------------------------------------

ecb_ciss_dims <- c("FREQ", "REF_AREA", "CURRENCY", "PROVIDER_FM", "INSTRUMENT_FM",
                    "PROVIDER_FM_ID", "DATA_TYPE_FM")

#' Fetch the ECB's country-level CISS for one country, averaged to
#' quarters, or NULL if the ECB publishes none for it
#'
#' The SDMX key is attached as attribute "key", for the coverage report.
fetch_ecb_ciss <- function(country3, label = "financial_stress", start_period = "1995-Q1",
                           frequency = "Q") {
  country2 <- lookup_country2(country3)
  if (is.na(country2)) return(NULL)

  dims <- c(FREQ = "D", REF_AREA = country2, CURRENCY = "Z0Z", PROVIDER_FM = "4F",
            INSTRUMENT_FM = "EC", PROVIDER_FM_ID = "SS_CIN", DATA_TYPE_FM = "IDX")
  key <- build_sdmx_key(dims[ecb_ciss_dims])

  start_day <- format(period_to_date(start_period), "%Y-%m-%d")
  url <- paste0(
    "https://data-api.ecb.europa.eu/service/data/CISS/", key,
    "?format=csvdata&startPeriod=", start_day
  )

  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] ECB CISS fetch failed for %s -- verify manually at https://data.ecb.europa.eu", label, country3))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex('"status":\\s*404|No Series was returned', ignore_case = TRUE))) {
    warning(sprintf("[%s] ECB publishes no CISS for %s", label, country3))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE,
                                         col_types = readr::cols(TIME_PERIOD = "c", OBS_VALUE = "d", .default = "c")))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] ECB CISS: unexpected response shape, inspect manually", label))
    return(NULL)
  }

  daily <- df %>%
    dplyr::transmute(date = as.Date(.data$TIME_PERIOD), value = .data$OBS_VALUE) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value)) %>%
    dplyr::distinct(date, .keep_all = TRUE)
  if (nrow(daily) == 0) {
    warning(sprintf("[%s] ECB CISS for %s has no non-missing observations", label, country3))
    return(NULL)
  }
  names(daily)[2] <- label

  out <- aggregate_to(daily, label, frequency) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
  attr(out, "key") <- key
  out
}
