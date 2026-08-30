## ---------------------------------------------------------------
## utils.R -- shared helpers used across all source-specific fetchers
## ---------------------------------------------------------------

#' GET a URL and return the response, or NULL on any failure
#'
#' Never throws: network errors, timeouts and non-2xx statuses all
#' result in NULL plus a warning naming the URL, so callers can log
#' and move on to the next series instead of aborting a whole run.
safe_get <- function(url, ..., timeout_seconds = 30) {
  resp <- tryCatch(
    httr::GET(url, httr::timeout(timeout_seconds), ...),
    error = function(e) {
      warning(sprintf("Request failed for %s: %s", url, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(resp)) return(NULL)
  if (httr::status_code(resp) >= 300) {
    warning(sprintf("HTTP %s for %s", httr::status_code(resp), url))
    return(NULL)
  }
  resp
}

#' Read an httr response body as UTF-8 text
response_text <- function(resp) {
  httr::content(resp, as = "text", encoding = "UTF-8")
}

#' GET a URL and return its body as text, or NULL on any failure
#'
#' This is the single point every source-specific fetcher (R/oecd.R,
#' R/imf.R, R/bis.R, R/ecb.R, R/fred_mirror.R) goes through to reach the
#' network. Tests mock this one function (reassigning it in the global
#' environment, since this is a script-sourced project rather than a
#' package) to return canned text instead of hitting a live API --
#' see tests/testthat/helper-mocks.R.
fetch_text <- function(url, ..., timeout_seconds = 30) {
  resp <- safe_get(url, ..., timeout_seconds = timeout_seconds)
  if (is.null(resp)) return(NULL)
  response_text(resp)
}

#' GET a URL and return its body as raw bytes, or NULL on any failure
#'
#' Analogous to `fetch_text()` but for binary downloads (R/ec_survey.R's
#' .xlsx-in-a-.zip archive). A request that resolves via redirect to an
#' HTML page instead of the expected binary (confirmed live: an
#' unpublished monthly archive 301-redirects to a generic landing page,
#' still HTTP 200 after the redirect) is treated as a failure -- checked
#' via both the Content-Type header and the raw bytes not starting with
#' the ZIP magic number "PK", since relying on either alone is fragile
#' (a server could omit/mislabel Content-Type).
fetch_binary <- function(url, ..., timeout_seconds = 30) {
  resp <- safe_get(url, ..., timeout_seconds = timeout_seconds)
  if (is.null(resp)) return(NULL)
  ctype <- httr::headers(resp)[["content-type"]] %||% ""
  bytes <- httr::content(resp, as = "raw")
  looks_like_zip <- length(bytes) >= 2 && bytes[1] == as.raw(0x50) && bytes[2] == as.raw(0x4B)
  if (stringr::str_detect(ctype, stringr::regex("html", ignore_case = TRUE)) || !looks_like_zip) {
    return(NULL)
  }
  bytes
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Build a dot-separated SDMX key from a named list of dimension values
#'
#' `dims` must be a named character vector giving a value for every key
#' dimension in the dataflow's declared order (position 1..n). Missing/NA
#' entries become wildcard segments (empty string between dots), matching
#' SDMX REST key syntax. Getting the dimension order wrong is the single
#' most common cause of a "structurally valid but empty" SDMX response --
#' see R/oecd.R, R/bis.R and R/ecb.R for the verified orders used here.
build_sdmx_key <- function(dims) {
  vals <- ifelse(is.na(dims) | dims == "_ALL_", "", dims)
  paste(vals, collapse = ".")
}

#' Convert an SDMX "YYYY-Qn" period string to a Date (first day of quarter)
#'
#' Used as the common join key between OECD/IMF/BIS/ECB series (which use
#' "YYYY-Qn" period strings) and FRED series (which use Date columns).
period_to_date <- function(period) {
  m <- stringr::str_match(period, "^(\\d{4})-Q([1-4])$")
  year <- as.integer(m[, 2])
  quarter <- as.integer(m[, 3])
  as.Date(sprintf("%d-%02d-01", year, (quarter - 1) * 3 + 1))
}

#' Convert a Date to an SDMX "YYYY-Qn" period string
#'
#' R's `format.Date()` has no "%q" (quarter) specifier -- `format(d,
#' "%Y-Q%q")`, which the original prototype script used for exactly this
#' conversion, silently emits the literal string "Qq" instead of e.g.
#' "Q1" (verified: format(as.Date("2020-01-01"), "%Y-Q%q") returns
#' "2020-Qq"). That single bug broke every period join in the FRED-QD
#' validation logic while still "running without erroring" -- the kind
#' of silent failure this project is meant to catch, not reproduce.
date_to_period <- function(date) {
  year <- as.integer(format(date, "%Y"))
  quarter <- (as.integer(format(date, "%m")) - 1) %/% 3 + 1
  sprintf("%d-Q%d", year, quarter)
}

#' Parse an OECD/BIS/ECB "csvfilewithlabels"-style response into period/value
#'
#' Column names vary by dataflow vintage, so this locates TIME_PERIOD and
#' OBS_VALUE (or their SDMX-JSON camelCase equivalents) by regex rather than
#' assuming a fixed position.
parse_time_value_csv <- function(txt, label) {
  if (nchar(trimws(txt)) == 0) {
    warning(sprintf("[%s] Empty response body", label))
    return(NULL)
  }
  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  time_col  <- names(df)[stringr::str_detect(names(df), stringr::regex("^TIME_PERIOD$|^obsTime$", ignore_case = TRUE))][1]
  value_col <- names(df)[stringr::str_detect(names(df), stringr::regex("^OBS_VALUE$|^obsValue$", ignore_case = TRUE))][1]

  if (is.na(time_col) || is.na(value_col)) {
    warning(sprintf("[%s] Could not identify TIME_PERIOD/OBS_VALUE columns in response", label))
    return(NULL)
  }

  out <- df %>%
    dplyr::transmute(period = .data[[time_col]], value = as.numeric(.data[[value_col]])) %>%
    dplyr::distinct(period, .keep_all = TRUE)
  names(out)[2] <- label
  out
}
