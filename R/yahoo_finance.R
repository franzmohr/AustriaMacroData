## ---------------------------------------------------------------
## yahoo_finance.R -- ATX (Austrian Traded Index) via Yahoo Finance's
## public chart API, for Austria's `share_price_index` specifically
##
## STATUS: VERIFIED 2026-08-30.
##
## First attempt was the Vienna Stock Exchange's own historical-data CSV
## export (found by driving the real page in a browser and reading the
## "Download (csv-file)" link's actual href -- a real, working,
## unauthenticated endpoint, confirmed live with a plain curl GET
## returning 7,918 rows of real daily OHLC data for 1995-2026). That
## approach was dropped mid-implementation in favor of Yahoo Finance at
## the user's explicit direction, not because the exchange's own export
## didn't work -- httr/libcurl in the R environment used for this project
## rejected its response's Content-Encoding ("Unrecognized or bad HTTP
## Content or Transfer-Encoding" -- libcurl on this machine lacks
## brotli support), a local environment limitation rather than a problem
## with the source itself. Documented here in case wienerborse.at is
## revisited later with a libcurl build that supports brotli.
##
## Yahoo's `/v8/finance/chart/` endpoint requires a browser-like
## User-Agent (confirmed live: default httr/curl UA -> HTTP 429; a
## Chrome UA string -> HTTP 200) -- some combination of IP + UA
## filtering, not a real rate limit tied to request volume (immediate
## retries with the browser UA succeed repeatedly). `range=max&interval=1mo`
## returns the full history in one request (406 monthly points,
## 1992-11 through the present, ~43KB) -- confirmed the returned
## `regularMarketPrice` matches the live value shown on
## wienerborse.at's own ATX page at the same moment (6786.58).
##
## Ticker "^ATX" (Yahoo's own symbol for the plain ATX price index,
## exchange "VIE" / "Vienna" per the response's own `meta` block, not a
## guess). Averaged from monthly to quarterly using the same convention
## R/fred_mirror.R uses for OECD-MEI monthly series (reuses that file's
## `monthly_to_quarterly()` -- it only depends on there being a `date`
## column, so it works unchanged here).
## ---------------------------------------------------------------

yahoo_finance_chart_url <- "https://query2.finance.yahoo.com/v8/finance/chart/"
yahoo_finance_user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

#' Fetch monthly close prices for a Yahoo Finance ticker
#'
#' Returns a `date` + `label` tibble (month-start dates), or NULL (with a
#' warning) on any failure. `range` follows Yahoo's own vocabulary
#' ("max", "10y", "5y", ...); "max" is used by `fetch_atx_quarterly()`
#' below to get the full history in one request.
fetch_yahoo_finance_monthly <- function(ticker, label, range = "max") {
  tryCatch(
    fetch_yahoo_finance_monthly_impl(ticker, label, range),
    error = function(e) {
      warning(sprintf("[%s] Yahoo Finance fetch errored unexpectedly: %s", label, conditionMessage(e)))
      NULL
    }
  )
}

fetch_yahoo_finance_monthly_impl <- function(ticker, label, range) {
  url <- sprintf("%s%s?range=%s&interval=1mo", yahoo_finance_chart_url, utils::URLencode(ticker, reserved = TRUE), range)

  txt <- fetch_text(url, httr::add_headers(`User-Agent` = yahoo_finance_user_agent))
  if (is.null(txt)) {
    warning(sprintf("[%s] Yahoo Finance fetch failed for ticker '%s' -- URL: %s", label, ticker, url))
    return(NULL)
  }

  parsed <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  result <- parsed$chart$result[[1]]
  if (is.null(result)) {
    err <- parsed$chart$error$description %||% "unknown error"
    warning(sprintf("[%s] Yahoo Finance returned no result for ticker '%s': %s", label, ticker, err))
    return(NULL)
  }

  timestamps <- unlist(result$timestamp)
  closes <- unlist(lapply(result$indicators$quote[[1]]$close, function(x) if (is.null(x)) NA_real_ else x))
  if (length(timestamps) == 0 || length(timestamps) != length(closes)) {
    warning(sprintf("[%s] Yahoo Finance response for ticker '%s' had no usable timestamp/close data", label, ticker))
    return(NULL)
  }

  out <- tibble::tibble(
    date = as.Date(as.POSIXct(timestamps, origin = "1970-01-01", tz = "UTC")),
    value = as.numeric(closes)
  ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value)) %>%
    dplyr::mutate(date = as.Date(sprintf("%s-01", format(.data$date, "%Y-%m"))))
  names(out)[2] <- label
  out
}

#' Fetch quarterly ATX levels (average of monthly closes within the
#' quarter) for use as Austria's `share_price_index`
fetch_atx_quarterly <- function(label = "share_price_index", start_period = "1995-Q1") {
  monthly <- fetch_yahoo_finance_monthly("^ATX", label, range = "max")
  if (is.null(monthly)) return(NULL)
  monthly_to_quarterly(monthly, label) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}
