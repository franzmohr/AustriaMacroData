## ---------------------------------------------------------------
## fred_qd_validation.R -- cross-check against the actual published
## FRED-QD file, and reuse its transformation codes
##
## STATUS: VERIFIED 2026-08-30. The FRED-QD file structure (row 1 =
## mnemonics, row 2 = factor flags, row 3 = transform codes, then
## data with M/D/YYYY dates) was confirmed by downloading and parsing
## the real August 2026 vintage.
## ---------------------------------------------------------------

#' Download and parse the actual FRED-QD CSV for a given monthly vintage
##
## The URL embeds a dated vintage (e.g. "2026-07-qd.csv") and FRED-QD is
## updated monthly, so a hardcoded date WILL eventually 404. Callers should
## pass the current vintage or accept the NULL-plus-warning and try an
## earlier month.
fetch_actual_fred_qd <- function(vintage_url) {
  raw_lines <- fetch_text(vintage_url, timeout_seconds = 60)
  if (is.null(raw_lines)) {
    warning("Could not download the FRED-QD file -- it's updated monthly, so this vintage URL may have gone stale; try an earlier YYYY-MM.")
    return(NULL)
  }

  con <- textConnection(raw_lines)
  raw <- utils::read.csv(con, header = FALSE, stringsAsFactors = FALSE)
  close(con)

  mnemonics  <- as.character(raw[1, ])
  factors    <- as.numeric(raw[2, -1])
  transform  <- as.numeric(raw[3, -1])
  data_rows  <- raw[-(1:3), ]
  names(data_rows) <- mnemonics

  data_rows$sasdate <- as.Date(data_rows$sasdate, format = "%m/%d/%Y")
  data_rows[, -1] <- lapply(data_rows[, -1], as.numeric)

  list(
    data = data_rows,
    transform_codes = stats::setNames(transform, mnemonics[-1]),
    factor_flags    = stats::setNames(factors, mnemonics[-1])
  )
}

#' Map from this project's anchor labels to real FRED-QD mnemonics
##
## No household disposable income row on purpose: that concept has no
## reliable quarterly source for USA from either OECD or IMF (verified,
## see README/R/oecd.R), so there is nothing to validate it against.
fred_qd_validation_map <- tibble::tribble(
  ~our_label,                          ~fred_qd_mnemonic,
  "real_gdp",                          "GDPC1",
  "real_household_consumption",        "PCECC96",
  "real_govt_consumption",             "GCEC1",
  "real_gfcf_total",                   "GPDIC1",
  "real_exports",                      "EXPGSC1",
  "real_imports",                      "IMPGSC1"
)

#' Correlate our OECD-sourced growth rates against the real FRED-QD series
##
## Compares GROWTH RATES (log-differences), not levels: OECD reports
## national-currency levels while FRED-QD reports chained-2012-dollar
## levels, so only the growth rate is comparable. `anchor_merged$period`
## is assumed to be in OECD's "YYYY-Qn" format.
##
## Returns a tibble with one row per concept, a `correlation`, and a
## `status` of "PASS" (>= pass_threshold), "FAIL" (< pass_threshold but
## computable) or "NO_DATA" (couldn't compute -- concept missing from one
## side, or fewer than 8 overlapping quarters).
## NOTE: this deliberately uses base R indexing (`df[[x]]`, `merge()`)
## rather than dplyr verbs inside the per-row closure below. Nesting a
## dplyr verb using `.data[[var]]` inside a purrr::map*() callback that
## itself runs inside an outer dplyr::mutate() loses track of `var` as a
## local variable (reproduced live: "object 'theirs' not found") -- a
## tidy-eval data-mask interaction, not a typo. Base R subsetting has no
## such issue.
correlate_one_concept <- function(ours, theirs, anchor_merged, fred_qd_data) {
  if (!(theirs %in% names(fred_qd_data))) return(NA_real_)
  if (!(ours %in% names(anchor_merged))) return(NA_real_)

  ours_series <- data.frame(period = anchor_merged$period, value = anchor_merged[[ours]])
  theirs_series <- data.frame(period = date_to_period(fred_qd_data$sasdate), value = fred_qd_data[[theirs]])

  merged <- merge(ours_series, theirs_series, by = "period", suffixes = c("_oecd", "_fred"))
  if (nrow(merged) < 8) return(NA_real_)

  g_oecd <- diff(log(merged$value_oecd))
  g_fred <- diff(log(merged$value_fred))
  suppressWarnings(stats::cor(g_oecd, g_fred, use = "complete.obs"))
}

validate_against_fred_qd <- function(anchor_merged, fred_qd_actual, pass_threshold = 0.9) {
  candidates <- fred_qd_validation_map %>%
    dplyr::filter(.data$our_label %in% names(anchor_merged))

  candidates$correlation <- vapply(
    seq_len(nrow(candidates)),
    function(i) correlate_one_concept(candidates$our_label[i], candidates$fred_qd_mnemonic[i],
                                       anchor_merged, fred_qd_actual$data),
    numeric(1)
  )
  candidates$status <- dplyr::case_when(
    is.na(candidates$correlation) ~ "NO_DATA",
    candidates$correlation >= pass_threshold ~ "PASS",
    TRUE ~ "FAIL"
  )
  candidates
}
