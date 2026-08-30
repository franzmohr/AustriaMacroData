## ---------------------------------------------------------------
## gpr.R -- Geopolitical Risk (GPR) Index, Caldara and Iacoviello (2022,
## American Economic Review), the standard academic/policy measure of
## geopolitical uncertainty. New "Other" concept with no FRED-QD
## equivalent (FRED-QD does not track geopolitical risk at all).
##
## STATUS: VERIFIED 2026-08-30 against matteoiacoviello.com's own
## published monthly data file (a real, current .xls download, not a
## guess). Source: https://www.matteoiacoviello.com/gpr_files/data_gpr_export.xls
## -- a single stable (non-versioned) URL the authors overwrite every
## month "at the beginning of the month" (confirmed live: last update
## shown on the page was August 3, 2026, with data through 2026-07).
##
## COUNTRY COVERAGE: confirmed by enumerating the file's own column
## names, not assumed -- "Country-specific indexes are also constructed
## for 44 different countries" (the page's own description), using
## GPRC_<ISO3> column names that match this project's own `country3`
## codes directly (no FRED-2-letter-style translation needed, e.g.
## GPRC_DEU, GPRC_USA). Austria is confirmed ABSENT from this list
## (checked directly against the real column names, not inferred from
## the "44 countries" figure) -- note also the trap that "GPRC_AUS" in
## this file is Australia, not Austria, the same 2-vs-3-letter-code
## collision this project's own country_codes.R warns about for FRED.
## For any country without its own column (confirmed: Austria; likely
## true for many smaller economies), this module falls back to the
## global "GPR" index -- not country-specific, but still informative,
## since Caldara and Iacoviello's own findings document international
## spillovers of geopolitical risk shocks regardless of a country's own
## media coverage of them.
##
## CACHING: the file covers every country in one ~2.7MB download and is
## only updated monthly, so it is cached in `data/landing/` (gitignored,
## refreshed only when the cache file is absent -- same manual-refresh
## convention as this project's other bulk pulls: BIS credit, EC survey).
##
## FORMAT NOTE: `readxl::read_excel()` with its default `guess_max = 1000`
## mis-detects several GPRC_* columns as logical (TRUE/FALSE) rather than
## numeric, because the column is entirely NA for the first ~1000 rows
## (the historical index goes back to 1900, but most country-specific
## series only start in 1985) -- confirmed live: values that print
## correctly as numeric (e.g. GPRC_DEU = 0.49 for 2026-02) come back as
## literal `TRUE` with the default guess_max. Fixed here by passing a
## `guess_max` larger than the file's ~1519 rows.
##
## CACHE FILENAME: deliberately has NO `.xls`/`.xlsx` extension. The
## source publishes old-format binary `.xls` (confirmed via the file's
## own OLE2 magic bytes), but `readxl::read_excel()` picks its parsing
## backend from the file EXTENSION first and only falls back to peeking
## at the actual bytes when the extension is absent or unrecognized --
## confirmed live that saving real `.xlsx`-format bytes under a `.xls`
## name makes `read_excel()` pick the wrong (legacy) backend and fail
## outright. An extension-less cache filename makes this module robust
## to the source ever changing its own format, and is what makes the
## test fixture below (built with `writexl`, which only writes `.xlsx`)
## actually exercise the same code path real `.xls` bytes go through.
## ---------------------------------------------------------------

gpr_url <- "https://www.matteoiacoviello.com/gpr_files/data_gpr_export.xls"
gpr_landing_dir <- "data/landing"
gpr_landing_path <- function(landing_dir = gpr_landing_dir) file.path(landing_dir, "gpr_data")

#' Fetch (or read from cache) the full GPR data file as a wide tibble:
#' one `date` column plus the global `GPR` column and every `GPRC_*`
#' country-specific column, or NULL on failure
fetch_gpr_bulk <- function(landing_dir = gpr_landing_dir) {
  cache_path <- gpr_landing_path(landing_dir)
  if (!file.exists(cache_path)) {
    bytes <- fetch_binary(gpr_url)
    if (is.null(bytes)) {
      warning(sprintf("GPR data fetch failed -- verify manually at %s", gpr_url))
      return(NULL)
    }
    dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
    writeBin(bytes, cache_path)
  }

  df <- tryCatch(
    readxl::read_excel(cache_path, sheet = "Sheet1", guess_max = 5000),
    error = function(e) NULL
  )
  if (is.null(df) || !"month" %in% names(df)) {
    warning("GPR data: unexpected workbook shape, inspect manually")
    unlink(cache_path)
    return(NULL)
  }

  df %>% dplyr::mutate(date = as.Date(.data$month)) %>% dplyr::select(-month)
}

#' Fetch quarterly geopolitical risk for one country: the country-specific
#' GPRC_<country3> index where the source publishes one, otherwise the
#' global GPR index (see module header for which countries have their own)
fetch_geopolitical_risk <- function(country3, label = "geopolitical_risk",
                                     start_period = "1995-Q1",
                                     landing_dir = gpr_landing_dir) {
  bulk <- fetch_gpr_bulk(landing_dir)
  if (is.null(bulk)) return(NULL)

  country_col <- paste0("GPRC_", country3)
  source_col <- if (country_col %in% names(bulk)) country_col else "GPR"

  monthly <- bulk %>%
    dplyr::transmute(date = .data$date, value = .data[[source_col]]) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value))
  if (nrow(monthly) == 0) {
    warning(sprintf("[%s] GPR data has no observations in column '%s'", label, source_col))
    return(NULL)
  }
  names(monthly)[2] <- label

  out <- monthly_to_quarterly(monthly, label) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
  attr(out, "source_col") <- source_col
  out
}
