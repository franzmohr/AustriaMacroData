## ---------------------------------------------------------------
## gov_yields.R -- 2-year and 5-year government bond yields
##
## Two concepts beside long_term_rate (10 years) and short_term_rate
## (3 months), for the countries that publish a government yield curve
## at these maturities:
##
##   Germany  Deutsche Bundesbank, term structure of interest rates on
##            listed Federal securities (Svensson method), zero-coupon,
##            residual maturity 2.0 / 5.0 years, % p.a.:
##              BBSIS.D.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A
##              (daily; R05XX for 5 years)
##            The monthly series (BBSIS.M...) holds END-OF-MONTH values
##            -- checked 2026-10-04: its 2026-08 value is the last daily
##            observation of August, not the mean. long_term_rate and the
##            US series are monthly AVERAGES, so the daily series is
##            averaged within the month instead. The daily series starts
##            1997-08; the end-of-month values carry the history back to
##            1972-09 -- an end-of-month value is an unbiased stand-in for
##            the month's mean, if a noisier one: for the 10-year yield
##            built this way, monthly changes correlate with
##            long_term_rate's (OECD, a monthly average) at 0.991 from
##            1997-08 and at 0.665 before. The current month is the mean
##            of the days published so far, as for financial_stress.
##   USA      FRED's own Treasury constant-maturity yields, monthly
##            averages of daily values, % p.a.: GS2 (from 1976-06) and
##            GS5 (from 1953-04). GS5 is FRED-QD's own series.
##
## Austria and every other country resolve to NA. Checked 2026-10-04:
## the OeNB's "Austrian government bond yields" data set (24) carries
## issue yields and the average yield of all outstanding federal bonds
## (UDRB), no yield at a fixed maturity; the ECB's FM data set publishes
## 2- and 10-year benchmarks for the euro-area aggregate (U2) only; and
## Eurostat, OECD and IMF carry only the 10-year Maastricht yield.
## ---------------------------------------------------------------

gov_yield_concepts <- tibble::tribble(
  ~label,                      ~bbk_maturity, ~fred_id,
  "government_bond_yield_2y",  "R02XX",       "GS2",
  "government_bond_yield_5y",  "R05XX",       "GS5"
)

#' The Bundesbank series key of a yield, at daily ("D") or monthly ("M")
#' frequency
bundesbank_yield_key <- function(maturity, freq = "D") {
  sprintf("BBSIS.%s.I.ZST.ZI.EUR.S1311.B.A604.%s.R.A.A._Z._Z.A", freq, maturity)
}

#' Parse a Bundesbank time-series CSV (format=csv) into date + value
#'
#' The file opens with a block of metadata rows; the observations are
#' the rows whose first field is a period, "YYYY-MM" or "YYYY-MM-DD".
#' Days without a value are published as ".", which becomes NA and is
#' dropped.
parse_bundesbank_csv <- function(txt) {
  lines <- strsplit(txt, "\r?\n")[[1]]
  lines <- lines[stringr::str_detect(lines, "^\\d{4}-\\d{2}(-\\d{2})?,")]
  if (length(lines) == 0) return(NULL)
  fields <- stringr::str_split_fixed(lines, ",", 3)
  period <- fields[, 1]
  date <- as.Date(ifelse(nchar(period) == 7, paste0(period, "-01"), period))
  tibble::tibble(date = date, value = suppressWarnings(as.numeric(fields[, 2]))) %>%
    dplyr::filter(!is.na(.data$value)) %>%
    dplyr::arrange(.data$date)
}

#' Fetch one Bundesbank yield series, or NULL with a warning
fetch_bundesbank_series <- function(maturity, freq, label) {
  key <- bundesbank_yield_key(maturity, freq)
  url <- paste0("https://api.statistiken.bundesbank.de/rest/data/",
                sub("^BBSIS\\.", "BBSIS/", key), "?format=csv&lang=en")
  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Bundesbank fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  out <- parse_bundesbank_csv(txt)
  if (is.null(out) || nrow(out) == 0) {
    warning(sprintf("[%s] Bundesbank returned no observations for %s", label, key))
    return(NULL)
  }
  out
}

#' German government bond yield at one maturity, monthly
#'
#' The mean of the daily values where the daily series exists, the
#' end-of-month value before it (see the header).
fetch_bundesbank_yield <- function(maturity, label) {
  daily <- fetch_bundesbank_series(maturity, "D", label)
  month_end <- fetch_bundesbank_series(maturity, "M", label)
  if (is.null(daily) && is.null(month_end)) return(NULL)

  averaged <- if (is.null(daily)) NULL else daily %>%
    dplyr::mutate(date = as.Date(format(.data$date, "%Y-%m-01"))) %>%
    dplyr::group_by(.data$date) %>%
    dplyr::summarise(value = mean(.data$value), .groups = "drop")
  if (is.null(month_end)) return(averaged)
  if (is.null(averaged)) return(month_end)
  dplyr::bind_rows(averaged, dplyr::filter(month_end, .data$date < min(averaged$date))) %>%
    dplyr::arrange(.data$date)
}

#' Fetch a 2- or 5-year government bond yield for one country
#'
#' Germany from the Bundesbank, the USA from FRED, NULL (no request)
#' for every other country. The result carries the source key in
#' attr(, "source_col") and the provider in attr(, "provider").
fetch_gov_yield <- function(country3, label, start_period = "1960-Q1", frequency = "Q") {
  frequency <- check_frequency(frequency)
  row <- gov_yield_concepts[gov_yield_concepts$label == label, ]
  if (nrow(row) != 1) stop("Unknown government yield concept: ", label)

  if (identical(country3, "DEU")) {
    monthly <- fetch_bundesbank_yield(row$bbk_maturity, label)
    provider <- "BUNDESBANK"
    key <- paste0(bundesbank_yield_key(row$bbk_maturity, "D"),
                  " (daily, averaged within the month; end-of-month values from the monthly series before 1997-08)")
  } else if (identical(country3, "USA")) {
    monthly <- get_fred_series(row$fred_id)
    if (is.null(monthly)) warning(sprintf("[%s] FRED fetch failed for %s", label, row$fred_id))
    provider <- "FRED"
    key <- row$fred_id
  } else {
    return(NULL)
  }
  if (is.null(monthly)) return(NULL)

  names(monthly) <- c("date", label)
  out <- aggregate_to(monthly, label, frequency)
  out <- out[!is.na(out[[label]]) & out$date >= period_to_date(start_period), ]
  if (nrow(out) == 0) return(NULL)
  attr(out, "source_col") <- key
  attr(out, "provider") <- provider
  out
}
