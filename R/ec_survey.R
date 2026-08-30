## ---------------------------------------------------------------
## ec_survey.R -- European Commission Business and Consumer Survey (BCS),
## consumer confidence indicator, for EU member states
##
## STATUS: VERIFIED 2026-08-30 against ec.europa.eu's own monthly archive:
##   https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_<YYMM>/main_indicators_sa_nace2.zip
## <YYMM> is a 2-digit year + 2-digit month (e.g. "2608" = August 2026).
## An unpublished month 301-redirects to a generic landing page (still
## HTTP 200 after the redirect, Content-Type text/html) rather than
## returning a clean 404 -- confirmed live, handled by `fetch_binary()`
## (R/utils.R) checking both Content-Type and the raw ZIP magic number.
##
## The archive is a single .xlsx (main_indicators_nace2.xlsx) with a
## "MONTHLY" sheet: column 1 = month-end date, and one column per
## "<EC 2-letter code>.<INDICATOR>" (e.g. "AT.CONS", "DE.CONS" for
## consumer confidence; also .INDU/.SERV/.RETA/.BUIL/.ESI/.EEI for other
## sectors, not used here). Confirmed live with real, CURRENT data
## through 2026-08 for AT and DE (values around -18 to -20, a plausible
## consumer-confidence balance) -- unlike the OECD-MEI-via-FRED
## `consumer_confidence` source in R/fred_mirror.R, whose data is frozen
## around 2024 (see that file's header comment).
##
## Motivation: for EU countries, this is a fresher, primary-source
## alternative to the frozen `CSCICP03{cc2}M665S` FRED mirror --
## scripts/build_country_panel.R tries this FIRST for EU member states
## (see R/country_codes.R's `eu_member_countries`) and overrides the
## FRED-mirror value with it on success, falling back to the FRED mirror
## otherwise (e.g. a transient failure, or a future EU member not yet in
## the archive).
##
## CACHING: the archive covers every EU country in one file and only
## changes once a month, so it is cached in `data/landing/` (gitignored,
## like the rest of that directory) rather than re-downloaded for every
## country. `get_ec_survey_xlsx()` checks the local cache for each
## candidate month BEFORE ever hitting the network; building the panel
## for e.g. AUT then DEU in the same month downloads the archive once.
## ---------------------------------------------------------------

ec_survey_base_url <- "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series"
ec_survey_landing_dir <- "data/landing"

#' Build the archive URL for a given calendar year/month
ec_survey_zip_url <- function(year, month) {
  yymm <- sprintf("%02d%02d", year %% 100, month)
  sprintf("%s/nace2_ecfin_%s/main_indicators_sa_nace2.zip", ec_survey_base_url, yymm)
}

#' Local cache path for a given calendar year/month's workbook
ec_survey_landing_path <- function(year, month, landing_dir = ec_survey_landing_dir) {
  file.path(landing_dir, sprintf("ec_bcs_main_indicators_%02d%02d.xlsx", year %% 100, month))
}

#' Unzip archive bytes and return the path to the .xlsx inside, or NULL
extract_ec_survey_xlsx <- function(zip_bytes) {
  tmp_zip <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp_zip), add = TRUE)
  writeBin(zip_bytes, tmp_zip)

  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  extracted <- tryCatch(utils::unzip(tmp_zip, exdir = tmp_dir), error = function(e) character(0))
  xlsx_path <- extracted[stringr::str_detect(extracted, stringr::regex("\\.xlsx$", ignore_case = TRUE))]
  if (length(xlsx_path) == 0) {
    unlink(tmp_dir, recursive = TRUE)
    return(NULL)
  }
  xlsx_path[1]
}

#' Get a local path to the EC survey workbook for the most recent
#' available month, downloading and caching it if not already there
#'
#' For each candidate month, current first then walking back up to
#' `max_lookback` months: a local cache hit returns immediately (no
#' network call at all); otherwise this tries the network and, on
#' success, saves the workbook into `landing_dir` before returning it, so
#' every later call (any country, same month) hits the cache. Returns
#' NULL if no candidate month is either cached or fetchable.
get_ec_survey_xlsx <- function(reference_date = Sys.Date(), max_lookback = 3,
                                landing_dir = ec_survey_landing_dir) {
  ym0 <- as.integer(format(reference_date, "%Y")) * 12 + (as.integer(format(reference_date, "%m")) - 1)
  for (back in 0:max_lookback) {
    ym <- ym0 - back
    year <- ym %/% 12
    month <- ym %% 12 + 1
    cached_path <- ec_survey_landing_path(year, month, landing_dir)
    if (file.exists(cached_path)) {
      return(list(path = cached_path, year = year, month = month, cached = TRUE))
    }

    bytes <- fetch_binary(ec_survey_zip_url(year, month))
    if (!is.null(bytes)) {
      extracted_path <- extract_ec_survey_xlsx(bytes)
      if (!is.null(extracted_path)) {
        dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
        file.copy(extracted_path, cached_path, overwrite = TRUE)
        unlink(dirname(extracted_path), recursive = TRUE)
        return(list(path = cached_path, year = year, month = month, cached = FALSE))
      }
    }
  }
  NULL
}

#' Extract one country's consumer-confidence column from a workbook path
#'
#' `ec_country2` is the Commission's own 2-letter code (see
#' R/country_codes.R's `lookup_ec_country2()` -- identical to the usual
#' FRED 2-letter code except Greece, "EL" not "GR"). Returns a `date` +
#' `label` monthly tibble, or NULL (with a warning) if the workbook can't
#' be read or the country's column isn't in it.
parse_ec_consumer_confidence <- function(xlsx_path, ec_country2, label) {
  monthly <- tryCatch(
    suppressMessages(readxl::read_excel(xlsx_path, sheet = "MONTHLY", col_names = FALSE)),
    error = function(e) NULL
  )
  if (is.null(monthly)) {
    warning(sprintf("[%s] Could not read the 'MONTHLY' sheet from the EC survey archive", label))
    return(NULL)
  }

  header <- as.character(monthly[1, ])
  col_name <- paste0(ec_country2, ".CONS")
  col_idx <- which(header == col_name)
  if (length(col_idx) == 0) {
    warning(sprintf("[%s] Column '%s' not found in the EC survey archive", label, col_name))
    return(NULL)
  }

  out <- tibble::tibble(
    date = suppressWarnings(as.Date(monthly[[1]][-1])),
    value = suppressWarnings(as.numeric(monthly[[col_idx[1]]][-1]))
  ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value))
  names(out)[2] <- label
  out
}

#' Fetch quarterly consumer confidence for an EU country from the EC's own
#' Business and Consumer Survey, averaging the underlying monthly series
#'
#' Returns NULL (with a warning) if the country isn't an EU member, the
#' archive can't be found (cached or fetched) within the lookback window,
#' or the country's column isn't in it.
fetch_ec_consumer_confidence <- function(country3, label = "consumer_confidence",
                                          start_period = "1995-Q1",
                                          reference_date = Sys.Date()) {
  if (!country3 %in% eu_member_countries) {
    warning(sprintf("[%s] EC Business and Consumer Survey only covers EU member states -- '%s' is not one", label, country3))
    return(NULL)
  }
  ec_country2 <- lookup_ec_country2(country3)
  if (is.na(ec_country2)) return(NULL)

  found <- get_ec_survey_xlsx(reference_date)
  if (is.null(found)) {
    warning(sprintf("[%s] Could not find a published EC survey archive (cached or live) within the lookback window", label))
    return(NULL)
  }

  monthly_df <- parse_ec_consumer_confidence(found$path, ec_country2, label)
  if (is.null(monthly_df)) return(NULL)

  monthly_to_quarterly(monthly_df, label) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}
