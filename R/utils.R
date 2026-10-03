## ---------------------------------------------------------------
## utils.R -- shared helpers used across all source-specific fetchers
## ---------------------------------------------------------------

#' GET a URL and return the response, or NULL on any failure
#'
#' Never throws: network errors, timeouts and non-2xx statuses all
#' result in NULL plus a warning naming the URL, so callers can log
#' and move on to the next series instead of aborting a whole run.
#'
#' A transient failure -- a timeout, a dropped connection, HTTP 429 or
#' any 5xx -- is retried up to `attempts` times, waiting
#' `retry_pause_seconds` times the attempt number in between. Added
#' 2026-10-03, when the ECB's data API answered HTTP 504 or timed out for
#' a different series on each of three AUT/DEU rebuilds in one afternoon
#' (CISS, then new mortgage lending, then the mortgage rate and household
#' net worth), each time while the same request succeeded seconds later:
#' without a retry every such blip published that month's panel with one
#' column empty. A 4xx other than 429 is not retried, since the SDMX
#' sources answer "no such series" that way and asking again cannot help.
safe_get <- function(url, ..., timeout_seconds = 30, attempts = 3,
                     retry_pause_seconds = getOption("austriamacrodata.retry_pause", 5)) {
  for (attempt in seq_len(attempts)) {
    failure <- NULL
    resp <- tryCatch(
      httr::GET(url, httr::timeout(timeout_seconds), ...),
      error = function(e) {
        failure <<- conditionMessage(e)
        NULL
      }
    )
    status <- if (is.null(resp)) NA_integer_ else httr::status_code(resp)
    transient <- is.null(resp) || status == 429 || status >= 500
    if (!transient || attempt == attempts) break
    Sys.sleep(retry_pause_seconds * attempt)
  }
  if (is.null(resp)) {
    warning(sprintf("Request failed for %s: %s", url, failure))
    return(NULL)
  }
  if (status >= 300) {
    warning(sprintf("HTTP %s for %s", status, url))
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
#' .xlsx-in-a-.zip archive, R/gpr.R's .xls workbook). A request that
#' resolves via redirect to an HTML page instead of the expected binary
#' (confirmed live: an unpublished monthly EC survey archive 301-redirects
#' to a generic landing page, still HTTP 200 after the redirect) is
#' treated as a failure via the Content-Type header -- this alone is
#' fragile (a server could omit/mislabel it), so callers that know their
#' expected binary format's magic number should check the returned bytes
#' themselves (see R/ec_survey.R's ZIP check) rather than relying only on
#' this generic guard.
fetch_binary <- function(url, ..., timeout_seconds = 30) {
  resp <- safe_get(url, ..., timeout_seconds = timeout_seconds)
  if (is.null(resp)) return(NULL)
  ctype <- httr::headers(resp)[["content-type"]] %||% ""
  if (stringr::str_detect(ctype, stringr::regex("html", ignore_case = TRUE))) {
    return(NULL)
  }
  httr::content(resp, as = "raw")
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

#' Convert an SDMX period string to a Date (first day of the period)
#'
#' Used as the common join key between OECD/IMF/BIS/ECB series (which use
#' period strings) and FRED series (which use Date columns).
#'
#' Quarterly "YYYY-Qn" and monthly "YYYY-Mnn" are both understood, so that
#' the same `start_period` argument can be handed to a fetcher whatever
#' frequency it is being asked for. Anything in neither form comes back as
#' NA rather than as a plausible-looking wrong date: a start that silently
#' became the wrong month would be far harder to notice than one that
#' filtered the series away.
period_to_date <- function(period) {
  quarterly <- stringr::str_match(period, "^(\\d{4})-Q([1-4])$")
  monthly <- stringr::str_match(period, "^(\\d{4})-M(0[1-9]|1[0-2])$")

  year <- ifelse(is.na(quarterly[, 2]), monthly[, 2], quarterly[, 2])
  month <- ifelse(is.na(quarterly[, 3]),
                  as.integer(monthly[, 3]),
                  (as.integer(quarterly[, 3]) - 1) * 3 + 1)

  out <- rep(as.Date(NA), length(period))
  ok <- !is.na(year) & !is.na(month)
  out[ok] <- as.Date(sprintf("%s-%02d-01", year[ok], month[ok]))
  out
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
date_to_period <- function(date, frequency = "Q") {
  year <- as.integer(format(date, "%Y"))
  if (identical(frequency, "M")) {
    return(sprintf("%d-M%02d", year, as.integer(format(date, "%m"))))
  }
  quarter <- (as.integer(format(date, "%m")) - 1) %/% 3 + 1
  sprintf("%d-Q%d", year, quarter)
}

#' Parse an OECD/BIS/ECB "csvfilewithlabels"-style response into period/value
#'
#' Column names vary by dataflow vintage, so this locates TIME_PERIOD and
#' OBS_VALUE (or their SDMX-JSON camelCase equivalents) by regex rather than
#' assuming a fixed position.
#'
#' A key that is STRUCTURALLY valid but has no observations for it (e.g. a
#' UNIT/NA_ITEM combination that validates against the dataflow's DSD but
#' simply isn't published for a given country -- confirmed live 2026-08-30
#' for Eurostat's namq_10_lp_ulc, whose index-level unit "I10" exists for
#' Austria but returns a real HTTP 200 with a header row and zero
#' observations for Germany) comes back as an otherwise well-formed CSV
#' with a header but no data rows -- NOT a SOAP Fault, and NOT
#' distinguishable from a real result without checking `nrow()`. Treating
#' that as NULL (like the SOAP-Fault and empty-body cases above) rather
#' than an empty-but-truthy tibble matters for every EU/euro-area-specific
#' OVERRIDE in scripts/build_country_panel.R (e.g. `if (!is.null(hicp))`):
#' without this check, a full_join against a 0-row "success" would silently
#' replace an already-resolved FRED-mirror value with NA instead of falling
#' back to it.
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

  if (nrow(out) == 0) {
    warning(sprintf("[%s] Structurally valid key returned zero observations", label))
    return(NULL)
  }

  names(out)[2] <- label
  out
}

#' Merge two wide period-indexed tibbles, preferring `primary`'s value at
#' each period and column, falling back to `secondary`'s value wherever
#' `primary` has none (including periods or columns `primary` doesn't
#' cover at all)
#'
#' Used to extend a shorter but conceptually preferred series (e.g.
#' Eurostat, preferred for EU countries' anchor NIPA concepts -- see
#' scripts/build_country_panel.R) with an available but non-preferred
#' source's longer history (e.g. OECD QNA), rather than treating the
#' non-preferred source as a pure "primary returned nothing at all"
#' fallback and silently forfeiting decades of history for any concept
#' the preferred source covers even partially. Confirmed live 2026-08-30:
#' OECD QNA has Austrian real GDP back to 1960-Q1, 35 years before
#' Eurostat's 1995-Q1 floor for the same concept.
#'
#' Both inputs (or either, but not both, being NULL) are expected to have
#' a `period` column plus one column per concept label; column names that
#' exist in only one input are carried through unchanged.
merge_prefer <- function(primary, secondary) {
  if (is.null(primary)) return(secondary)
  if (is.null(secondary)) return(primary)

  shared_labels <- intersect(setdiff(names(primary), "period"), setdiff(names(secondary), "period"))
  merged <- dplyr::full_join(primary, secondary, by = "period", suffix = c("", ".secondary"))
  for (lbl in shared_labels) {
    sec_col <- paste0(lbl, ".secondary")
    merged[[lbl]] <- dplyr::coalesce(merged[[lbl]], merged[[sec_col]])
    merged[[sec_col]] <- NULL
  }
  dplyr::arrange(merged, period)
}

#' Does `df[[label]]` have at least one non-NA value? (FALSE if the column
#' or the whole tibble is absent) -- used to decide, per concept, whether
#' a given source actually contributed anything to a merged result.
has_data <- function(df, label) {
  !is.null(df) && label %in% names(df) && any(!is.na(df[[label]]))
}

#' Like `merge_prefer()`, but first RESCALES each of `secondary`'s
#' columns to match `primary`'s level at the first period where BOTH
#' have real data for that column (a genuine overlap point), before
#' coalescing -- for combining two sources known to have a systematic
#' SCALE mismatch, not just a coverage gap `merge_prefer()` alone is fine
#' for.
#'
#' BUG FOUND AND FIXED 2026-08-30, by this project's own plausibility
#' checks (`R/plausibility_checks.R`), not by the pre-existing
#' `--validate` flag: `merge_prefer(eurostat_result, oecd_result)` in
#' `scripts/build_country_panel.R`'s anchor-concept step introduced a
#' ~4x level DISCONTINUITY at the exact quarter Austria's merge switches
#' from OECD to Eurostat (1994-Q4 to 1995-Q1), across all six anchor
#' concepts identically. Root cause, confirmed live: OECD QNA's table
#' T0102 (used for every anchor concept) only offers
#' `TRANSFORMATION="LA"` ("Annual levels", i.e. the quarterly series
#' expressed at an annualized rate) -- there is no non-annualized
#' quarterly variant of this table at all, confirmed by querying
#' `TRANSFORMATION="N"` ("Non transformed data") for both a 1990s and a
#' 2020s period and getting a clean `NoRecordsFound` both times, not a
#' guess. Eurostat's `namq_10_gdp`, by contrast, reports actual
#' (non-annualized) quarterly levels, so simply coalescing the two (as
#' `merge_prefer()` does) mixes annualized-rate values with true
#' quarterly values in one column.
#'
#' This was invisible to the `--validate` flag because that flag only
#' ever compares GROWTH RATES: annualizing a series multiplies every
#' period by a near-constant factor, so its period-over-period % growth
#' rate is virtually identical to the true series' -- the correlation
#' check that gave `real_gdp` a perfect 1.000 for the United States
#' would have looked exactly as good even with this exact bug present,
#' because it never inspects LEVELS at all. The plausibility checks do,
#' which is how a >300% quarter-over-quarter jump surfaced it.
#'
#' The join key is a parameter because the monthly panel keys on `date`
#' rather than on a `period` string, and a level splice is exactly as
#' necessary there: the monthly panel's Eurostat sources are indices on
#' 2021 = 100 while the FRED mirrors whose history they extend are on
#' other bases.
#'
#' Rescaling (rather than discarding OECD's pre-Eurostat history
#' entirely, which would forfeit the whole point of `merge_prefer()`)
#' preserves OECD's own internally-consistent quarter-to-quarter
#' DYNAMICS for the period Eurostat doesn't cover, while correcting its
#' ABSOLUTE LEVEL to match Eurostat's at the point the two meet -- the
#' standard "level-splice" technique for joining two differently-based
#' series into one comparable one. The scale factor is computed
#' EMPIRICALLY per concept (not assumed to be a fixed ~4), since OECD's
#' own annualization convention need not be exactly 4x every quarter's
#' true value; `secondary` (OECD) is already fetched for the FULL
#' requested range in `scripts/build_country_panel.R`, so the overlap
#' point this needs already exists in the data being merged -- no extra
#' API call required.
splice_prefer <- function(primary, secondary, by = "period") {
  if (is.null(primary)) return(secondary)
  if (is.null(secondary)) return(primary)

  shared_labels <- intersect(setdiff(names(primary), by), setdiff(names(secondary), by))
  merged <- dplyr::full_join(primary, secondary, by = by, suffix = c("", ".secondary"))
  for (lbl in shared_labels) {
    sec_col <- paste0(lbl, ".secondary")
    both <- !is.na(merged[[lbl]]) & !is.na(merged[[sec_col]])
    if (any(both)) {
      first_overlap <- which(both)[1]
      scale <- merged[[lbl]][first_overlap] / merged[[sec_col]][first_overlap]
      if (is.finite(scale) && scale > 0) {
        merged[[sec_col]] <- merged[[sec_col]] * scale
      }
      ## else: no usable overlap ratio (e.g. secondary's value at the
      ## overlap point is exactly 0) -- fall through unscaled rather
      ## than corrupt the column with an Inf/NaN/negative multiplier.
    }
    merged[[lbl]] <- dplyr::coalesce(merged[[lbl]], merged[[sec_col]])
    merged[[sec_col]] <- NULL
  }
  dplyr::arrange(merged, .data[[by]])
}
