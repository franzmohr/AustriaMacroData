## ---------------------------------------------------------------
## imf.R -- IMF National Economic Accounts, Quarterly (fallback for
## OECD anchor concepts, mainly useful for non-OECD countries)
##
## STATUS: VERIFIED 2026-08-30, with one confirmed upstream bug.
##
## The original script used the CRAN `imfapi` package (imf_get()).
## That package is broken as of v0.1.2: imf_get_dataflows() (called
## internally by imf_get() to resolve a dataflow_id) throws
## "Indexing out of bounds" on `dataflow$description[[1]]` while
## parsing IMF's full ~220-dataflow catalog, because at least one
## dataflow entry has no description field. This crashes EVERY call
## to imf_get(), regardless of dataflow_id or indicator -- reproduced
## live via imf_get(dataflow_id = "NEA", ...) and via
## imfapi:::get_dataflows_components() directly. Filed upstream at
## https://github.com/Teal-Insights/r-imfapi/issues.
##
## Because of that, this module calls IMF's SDMX 3.0 API directly via
## httr instead of depending on imfapi. It reuses imfapi's own base
## URL (https://api.imf.org/external/sdmx/3.0/, found by reading the
## installed package's source) but skips the buggy dataflow-listing
## step entirely.
##
## Also corrected: the original script's dataflow_id "NEA" no longer
## exists (IMF's March 2025 data-platform restructuring renamed it).
## The current dataflow is IMF.STA:QNEA v7.0.0 ("National Economic
## Accounts (NEA), Quarterly Data"), confirmed via IMF's own
## structure/dataflow/all/*/+ catalog. Its indicator codes are
## standard SNA transaction codes (B1GQ, P3_S1M, ...), NOT the
## legacy IFS-style mnemonics (NGDP_R, NCP_R, ...) the original
## script guessed -- confirmed via the CL_NEA_INDICATOR codelist (78
## codes, none of which are IFS-style).
## ---------------------------------------------------------------

imf_base_url <- "https://api.imf.org/external/sdmx/3.0/"

## Confirmed dimension order for IMF.STA:QNEA (7.0.0):
##   COUNTRY.INDICATOR.PRICE_TYPE.S_ADJUSTMENT.TYPE_OF_TRANSFORMATION.FREQUENCY
## PRICE_TYPE "Q" = constant prices (real); TYPE_OF_TRANSFORMATION "XDC" =
## domestic currency; verified live with a real 200 response for
## USA.B1GQ.Q.SA.XDC.Q (GDP, 1950-Q1 onward).
imf_qnea_dataflow <- "IMF.STA/QNEA/7.0.0"

#' IMF QNEA indicator codes for the anchor concepts
#'
#' Corrected from the original NGDP_R/NCP_R/... IFS mnemonics to the SNA
#' codes actually used by QNEA. No household disposable income row: QNEA has
#' no household-specific disposable income indicator (only whole-economy
#' B6G/B6N), and even that has zero USA observations -- verified live, see
#' README.
imf_indicator_map <- tibble::tribble(
  ~label,                              ~imf_indicator,
  "real_gdp",                          "B1GQ",
  "real_household_consumption",        "P3_S1M",
  "real_govt_consumption",             "P3_S13",
  "real_gfcf_total",                   "P51G",
  "real_exports",                      "P6",
  "real_imports",                      "P7"
)

#' Fetch one QNEA series directly via httr (bypasses the buggy imfapi wrapper)
fetch_imf_qnea <- function(country3, indicator, label,
                            s_adjustment = "SA", start_period = "1995-Q1") {
  tryCatch(
    fetch_imf_qnea_impl(country3, indicator, label, s_adjustment, start_period),
    error = function(e) {
      warning(sprintf("[%s] IMF QNEA fetch errored unexpectedly for %s/%s: %s", label, country3, indicator, conditionMessage(e)))
      NULL
    }
  )
}

fetch_imf_qnea_impl <- function(country3, indicator, label, s_adjustment, start_period) {
  key <- paste(country3, indicator, "Q", s_adjustment, "XDC", "Q", sep = ".")
  url <- paste0(
    "https://api.imf.org/external/sdmx/3.0/data/dataflow/", imf_qnea_dataflow, "/",
    key, "?format=csv&startPeriod=", start_period
  )

  ## IMF's API honors `format=csv` in the query string only loosely --
  ## without an explicit Accept header it can still return SDMX-JSON.
  ## Confirmed live: same URL, no header -> JSON; with this header -> CSV.
  txt <- fetch_text(url, httr::add_headers(Accept = "text/csv"))
  if (is.null(txt)) {
    warning(sprintf("[%s] IMF QNEA fetch failed for indicator '%s' -- URL: %s", label, indicator, url))
    return(NULL)
  }

  if (stringr::str_detect(txt, stringr::fixed('"dataSets"'))) {
    warning(sprintf("[%s] IMF QNEA returned JSON instead of CSV for %s/%s -- unexpected, inspect manually", label, country3, indicator))
    return(NULL)
  }
  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (nrow(df) == 0 || !("OBS_VALUE" %in% names(df)) || all(is.na(df$OBS_VALUE))) {
    warning(sprintf("[%s] IMF QNEA has no observations for %s/%s", label, country3, indicator))
    return(NULL)
  }

  out <- df %>%
    dplyr::filter(!is.na(.data$OBS_VALUE)) %>%
    dplyr::transmute(period = .data$TIME_PERIOD, value = as.numeric(.data$OBS_VALUE)) %>%
    dplyr::distinct(period, .keep_all = TRUE)
  names(out)[2] <- label
  out
}

#' Fill in anchor concepts missing from `anchor_merged` using IMF QNEA
#'
#' `missing_labels` should be setdiff(oecd_anchor_concepts$label, names(anchor_merged))
#' from the caller. Returns a named list of period/value tibbles (possibly
#' empty), one per label IMF was able to fill.
fetch_imf_fallbacks <- function(country3, missing_labels, start_period = "1995-Q1") {
  candidates <- imf_indicator_map %>% dplyr::filter(.data$label %in% missing_labels)
  results <- purrr::pmap(
    list(candidates$label, candidates$imf_indicator),
    function(label, imf_indicator) fetch_imf_qnea(country3, imf_indicator, label, start_period = start_period)
  )
  names(results) <- candidates$label
  purrr::compact(results)
}
