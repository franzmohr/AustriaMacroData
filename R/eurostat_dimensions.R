## ---------------------------------------------------------------
## eurostat_dimensions.R -- the guard that makes a Eurostat key fail
## loudly when it was written for the wrong dimension order
##
## WHY THIS EXISTS. Eurostat's SDMX 2.1 dissemination endpoint filters a
## dataset ONLY through the dot-separated key in the path, and that key
## is POSITIONAL: segment i is matched against dimension i of that
## dataset's own declared order. The same values passed as query
## parameters are IGNORED. So a key written for the wrong order does not
## come back as an error -- it filters on a different dimension and
## answers with plausible-looking rows. `parse_time_value_csv()` reads
## them happily and the panel gets a column of real numbers that measure
## something nobody asked for.
##
## The orders are NOT uniform, not even between siblings in one family.
## Confirmed live 2026-11-20 by reading each dataset's own SDMX-CSV
## header (every order in `eurostat_key_dimensions` below was checked
## that day against a real 200 response for AT):
##   namq_10_gdp     freq.unit.s_adj.na_item.geo
##   namq_10_a10_e   freq.unit.nace_r2.s_adj.na_item.geo   <- two middle
##   nasq_10_nf_tr   freq.unit.direct.sector.na_item.s_adj.geo
##   gov_10q_ggnfa   freq.unit.s_adj.sector.na_item.geo
## The same trap outside this project: gov_10dd_edpt1 declares
## freq.unit.sector.na_item.geo while gov_10q_ggdebt declares
## freq.na_item.sector.unit.geo.
##
## HOW IT IS CHECKED. An SDMX-CSV answer states its own dimension order
## in its header row:
##   DATAFLOW,LAST UPDATE,<dimensions...>,TIME_PERIOD,OBS_VALUE,...
## so the dimension names sit strictly between "LAST UPDATE" and
## "TIME_PERIOD" and can be compared against the order the key was
## written for. Every Eurostat fetcher in this project goes through
## `fetch_eurostat_text()` below, which does that comparison and
## `stop()`s on a mismatch.
##
## WHY stop() AND NOT warning(). A warning here publishes a panel of
## wrong numbers that looks right: the run finishes, the CSV commits,
## and nothing downstream can tell the column apart from a correct one.
## An aborted build is a visible, fixable failure; a silently wrong
## column is neither. The existing "S:Fault|faultstring" warnings are a
## different case and are left as they are -- a fault means Eurostat
## refused the key, so no numbers arrive at all.
##
## ALSO FAIL-CLOSED: an answer whose first line is not an SDMX-CSV
## header (no TIME_PERIOD column -- an HTML error page, a truncated
## body) stops too, because then there is no way to tell what the key
## filtered on. A blank body is left to the callers' existing
## "fetch failed"/"no observations" warnings, since nothing arrived to
## check. A dataflow with no declared order stops as well: adding a
## Eurostat request means declaring the order it assumes, which is the
## whole point of the table below.
##
## TO ADD A DATAFLOW. Read its order from its own answer rather than
## from a codelist or another dataflow in the same family:
##   curl -s "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/\
## data/<dataflow>/<key>?format=SDMX-CSV&startPeriod=2025-Q1" | head -1
## and take the column names between "LAST UPDATE" and "TIME_PERIOD".
## ---------------------------------------------------------------

#' The declared key dimension order of every Eurostat dataflow this
#' project requests, lower-case, in key-segment order
#'
#' Keys are dataflow ids as the fetchers spell them (see
#' `sts_dataflow()` in R/eurostat_sts.R for the _m/_q pairs).
eurostat_key_dimensions <- list(
  ## National accounts (R/eurostat.R, R/inventories.R, R/population.R,
  ## R/employment.R)
  namq_10_gdp    = c("freq", "unit", "s_adj", "na_item", "geo"),
  namq_10_pe     = c("freq", "unit", "s_adj", "na_item", "geo"),
  namq_10_lp_ulc = c("freq", "unit", "s_adj", "na_item", "geo"),
  namq_10_a10_e  = c("freq", "unit", "nace_r2", "s_adj", "na_item", "geo"),
  nasq_10_nf_tr  = c("freq", "unit", "direct", "sector", "na_item", "s_adj", "geo"),
  ## Government finance (R/eurostat.R)
  gov_10q_ggnfa  = c("freq", "unit", "s_adj", "sector", "na_item", "geo"),
  ## Prices (R/eurostat.R)
  prc_hicp_minr  = c("freq", "unit", "coicop18", "geo"),
  ## Short-term statistics (R/eurostat_sts.R, R/construction_costs.R)
  sts_inpr_m     = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
  sts_inpr_q     = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
  sts_trtu_m     = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
  sts_trtu_q     = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
  sts_copi_m     = c("freq", "indic_bt", "cpa2_1", "s_adj", "unit", "geo"),
  sts_copi_q     = c("freq", "indic_bt", "cpa2_1", "s_adj", "unit", "geo"),
  ## Labour force survey (R/eurostat_sts.R)
  une_rt_m       = c("freq", "s_adj", "age", "unit", "sex", "geo"),
  ## Energy (R/weather.R)
  nrg_chdd_m     = c("freq", "unit", "indic_nrg", "geo")
)

#' Build the condition a dimension mismatch signals
#'
#' Classed so that the `tryCatch()`s which turn an unexpected fetch
#' error into a warning (R/eurostat.R's `fetch_eurostat_series()`,
#' `fetch_eurostat_hours()`, R/population.R's
#' `fetch_eurostat_namq_10_pe()`) can let this one through unchanged
#' instead of downgrading it to the warning this guard exists to avoid.
eurostat_dimension_error <- function(message) {
  structure(
    class = c("eurostat_dimension_mismatch", "error", "condition"),
    list(message = message, call = NULL)
  )
}

#' Let a dimension mismatch out of a broad `error =` handler
#'
#' Call this FIRST inside any `tryCatch(..., error = )` handler that
#' turns a failed Eurostat fetch into a warning: it re-signals a
#' dimension mismatch and returns invisibly for every other error, so
#' the handler's own warn-and-NULL path follows for those.
#'
#' Why it is done from inside the `error =` handler rather than by
#' listing an `eurostat_dimension_mismatch =` handler beside it:
#' `tryCatch()` leaves the handlers listed AFTER the one it invoked in
#' place while that handler runs, so a dedicated handler that re-signals
#' the condition has it caught by the `error =` handler next to it --
#' confirmed by trying exactly that. Re-signalling from inside the last
#' handler has nothing left to catch it, so the condition propagates.
stop_if_eurostat_dimension_mismatch <- function(e) {
  if (inherits(e, "eurostat_dimension_mismatch")) stop(e)
  invisible(NULL)
}

#' The dimension column names an SDMX-CSV answer declares
#'
#' Returns the column names strictly between "LAST UPDATE" and
#' "TIME_PERIOD" in the header row, lower-cased, or NULL if the first
#' line is not an SDMX-CSV header.
eurostat_response_dimensions <- function(txt) {
  header <- strsplit(txt, "\r?\n")[[1]][1]
  if (is.na(header) || !nzchar(trimws(header))) return(NULL)
  cols <- tolower(trimws(strsplit(header, ",", fixed = TRUE)[[1]]))
  time <- match("time_period", cols)
  if (is.na(time)) return(NULL)
  last_update <- match("last update", cols)
  if (is.na(last_update) || last_update >= time) return(NULL)
  cols[seq_len(time - last_update - 1) + last_update]
}

#' Stop unless a Eurostat answer's dimensions are the ones its key assumed
#'
#' `dataflow` and `key` are the request that produced `txt`; `label`, if
#' given, names the concept in the message, as the surrounding warnings
#' do. Returns the dimension names invisibly when they match.
check_eurostat_dimension_order <- function(txt, dataflow, key, label = NULL) {
  tag <- if (is.null(label)) "" else sprintf("[%s] ", label)
  expected <- eurostat_key_dimensions[[tolower(dataflow)]]
  if (is.null(expected)) {
    stop(eurostat_dimension_error(sprintf(
      paste0("%sEurostat dataflow '%s' has no declared key dimension order, so the key ",
             "'%s' cannot be verified. A Eurostat key is positional: declare this ",
             "dataflow's order in `eurostat_key_dimensions` (R/eurostat_dimensions.R), ",
             "read from its own SDMX-CSV header, before requesting it."),
      tag, dataflow, key)))
  }

  arrived <- eurostat_response_dimensions(txt)
  if (is.null(arrived)) {
    stop(eurostat_dimension_error(sprintf(
      paste0("%sEurostat dataflow '%s' answered key '%s' with something that is not an ",
             "SDMX-CSV header (no 'LAST UPDATE'/'TIME_PERIOD' columns in its first line), ",
             "so the dimensions the key filtered on cannot be verified. First line: %s"),
      tag, dataflow, key, substr(strsplit(txt, "\r?\n")[[1]][1], 1, 200))))
  }

  if (!identical(arrived, tolower(expected))) {
    stop(eurostat_dimension_error(sprintf(
      paste0("%sEurostat dataflow '%s' declares its key dimensions as %s, but the key ",
             "'%s' was written for %s. A Eurostat key is positional, so this request ",
             "filtered on something other than what was asked for and returned ",
             "plausible-looking rows for the wrong series. Fix the key, or the order in ",
             "`eurostat_key_dimensions` (R/eurostat_dimensions.R), before trusting any ",
             "of these numbers."),
      tag, dataflow, paste(arrived, collapse = "."), key,
      paste(tolower(expected), collapse = "."))))
  }

  invisible(arrived)
}

#' GET a Eurostat SDMX-CSV URL, verifying that the answer's dimensions
#' are the ones `key` assumed
#'
#' The single point every Eurostat fetcher in this project reaches the
#' network through: `fetch_text()` plus `check_eurostat_dimension_order()`.
#' Returns exactly what `fetch_text()` does -- NULL on a failed request,
#' and a SOAP fault body unchanged, so each caller's own "fetch failed"
#' and "no observations" warnings keep working untouched -- but never
#' returns rows whose dimensions contradict the key that asked for them.
fetch_eurostat_text <- function(url, dataflow, key, label = NULL, ...) {
  txt <- fetch_text(url, ...)
  if (is.null(txt) || !nzchar(trimws(txt))) return(txt)
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    return(txt)
  }
  check_eurostat_dimension_order(txt, dataflow, key, label)
  txt
}
