## ---------------------------------------------------------------
## ecb_market_rates.R -- short- and long-term market interest rates for
## euro-area members from the ECB, current within days of a month's end
##
## The OECD MEI mirror on FRED that every country's short_term_rate and
## long_term_rate come from runs about a month behind: on 2026-10-04 it
## ended in 2026-08, while the ECB already had September's Euribor. A
## nowcast of the month just ended is built on exactly that month, so the
## euro-area members now take both rates from the ECB, and the mirror
## only fills the months before the ECB's series start, unchanged.
##
##   short_term_rate  3-month Euribor, monthly average, ECB Financial
##                    market data (FM), M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA.
##                    Over 1999-01 to 2026-08 it equals the mirror for
##                    Austria and Germany in every month (checked
##                    2026-10-04). Before 1999 the ECB series is a
##                    synthetic euro rate where the mirror holds each
##                    country's own interbank rate, so Euribor is used only
##                    from a country's euro adoption on (`euro_adoption`).
##   long_term_rate   10-year government bond yield used for the
##                    convergence criterion, ECB Long-term interest rate
##                    statistics (IRS), M.<cc>.L.L40.CI.0000.EUR.N.Z,
##                    country-specific. Equal to the mirror for Austria in
##                    every month since 1993; for Germany it differs by at
##                    most 0.15 pp in 61 months up to 2019-06, where the
##                    ECB's series is the official one. Published around
##                    the tenth of the following month.
##
## Countries outside the euro area keep the mirror: the functions below
## return NULL for them without a request.
## ---------------------------------------------------------------

#' First month in which each euro-area member's money-market rate is Euribor
euro_adoption <- c(
  AUT = "1999-01", BEL = "1999-01", DEU = "1999-01", ESP = "1999-01", FIN = "1999-01",
  FRA = "1999-01", IRL = "1999-01", ITA = "1999-01", LUX = "1999-01", NLD = "1999-01",
  PRT = "1999-01", GRC = "2001-01", SVN = "2007-01", CYP = "2008-01", MLT = "2008-01",
  SVK = "2009-01", EST = "2011-01", LVA = "2014-01", LTU = "2015-01"
)

#' Fetch one monthly ECB rate series as date + value, or NULL with a warning
fetch_ecb_rate_series <- function(flow_key, label, what, start_month) {
  url <- paste0("https://data-api.ecb.europa.eu/service/data/", flow_key,
                "?format=csvdata&startPeriod=", start_month)
  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] ECB %s fetch failed -- the OECD MEI mirror stays in place", label, what))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex('"status":\\s*404|No Series was returned', ignore_case = TRUE))) {
    warning(sprintf("[%s] ECB has no %s observations -- the OECD MEI mirror stays in place", label, what))
    return(NULL)
  }
  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] ECB %s: unexpected response shape, inspect manually", label, what))
    return(NULL)
  }
  out <- df %>%
    dplyr::transmute(date = as.Date(paste0(.data$TIME_PERIOD, "-01")), value = as.numeric(.data$OBS_VALUE)) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value)) %>%
    dplyr::distinct(.data$date, .keep_all = TRUE) %>%
    dplyr::arrange(.data$date)
  names(out)[2] <- label
  out
}

#' 3-month Euribor for a euro-area member, from its euro adoption on
fetch_ecb_short_term_rate <- function(country3, label = "short_term_rate", start_period = "1995-Q1",
                                      frequency = "Q") {
  frequency <- check_frequency(frequency)
  if (!country3 %in% names(euro_adoption)) return(NULL)
  from <- max(as.Date(paste0(euro_adoption[[country3]], "-01")), period_to_date(start_period))
  monthly <- fetch_ecb_rate_series("FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA", label, "3-month Euribor",
                                   format(from, "%Y-%m"))
  if (is.null(monthly)) return(NULL)
  monthly <- monthly[monthly$date >= from, ]
  attr_key <- "FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA (3-month Euribor, from euro adoption)"
  out <- aggregate_to(monthly, label, frequency)
  attr(out, "key") <- attr_key
  out
}

#' 10-year government bond yield (convergence criterion) for a euro-area member
fetch_ecb_long_term_rate <- function(country3, label = "long_term_rate", start_period = "1995-Q1",
                                     frequency = "Q") {
  frequency <- check_frequency(frequency)
  if (!country3 %in% names(euro_adoption)) return(NULL)
  country2 <- lookup_country2(country3)
  if (is.na(country2)) return(NULL)
  key <- sprintf("IRS/M.%s.L.L40.CI.0000.EUR.N.Z", country2)
  monthly <- fetch_ecb_rate_series(key, label, "10-year government bond yield",
                                   format(period_to_date(start_period), "%Y-%m"))
  if (is.null(monthly)) return(NULL)
  out <- aggregate_to(monthly, label, frequency)
  attr(out, "key") <- paste0(key, " (10-year government bond yield, convergence criterion)")
  out
}
