## ---------------------------------------------------------------
## plausibility_checks.R -- country-agnostic sanity checks for every
## resolved concept, independent of any ground-truth comparison file
##
## MOTIVATION: `R/fred_qd_validation.R`'s `--validate` flag is the only
## verification this project runs automatically, and it ONLY works for
## the United States, because FRED-QD itself is the only real published
## ground truth available (see that file's header). A researcher adding
## a NEW country (say, FRA or POL) has no analogous ground truth to
## compare against -- until now, their only recourse was to eyeball
## <country>_nipa.csv and docs/data_sources.csv by hand, concept by
## concept, with no automated signal pointing at which of the 38 columns
## might actually be wrong (a wrong SDMX dimension picking the wrong
## sector, a units mismatch, a sign error, ...).
##
## This module closes that gap with three generic checks that need no
## ground truth at all, just the panel itself and each concept's known
## MEASUREMENT TYPE (percent/ratio, survey balance or sentiment index,
## quarterly growth rate, or level/index):
##   1. Sign/range plausibility -- a rate, ratio or index has a broad
##      but real-world-informed range (e.g. an unemployment rate of -40
##      or 900 is never right, regardless of country); a level/index
##      concept must simply be positive.
##   2. Extreme quarter-over-quarter jumps (levels/indices only) -- a
##      >|JUMP_THRESHOLD| swing between adjacent quarters is far more
##      often a units or decimal error (millions vs billions, a wrong
##      OBS_VALUE column, a mis-set UNIT_MULT) than a real economic
##      event; genuine shocks (COVID-19) are large but rarely THIS large
##      quarter-on-quarter for whole-economy aggregates.
##   3. Coverage sparsity -- a resolved concept with fewer than
##      MIN_OBS_FOR_TREND observations can't usefully support either
##      check above, so it is reported as "TOO_SHORT" rather than
##      silently skipped or falsely passed.
##
## These are DELIBERATELY loose, heuristic bounds, not authoritative
## thresholds -- the goal is to flag the small number of concepts most
## likely to reward a researcher's limited manual-verification time
## (Sections below in CONTRIBUTING.md), not to certify correctness. A
## PASS here is not proof a series is right; a FLAG is not proof it is
## wrong -- it is a prioritized to-do list.
## ---------------------------------------------------------------

## Category assignment for all 38 concepts in
## scripts/build_country_panel.R's `concept_group_map`. A concept added
## in the future and left OUT of this table falls through to "level" by
## default (see `plausibility_category()`) -- the strictest category
## (values must be positive) -- rather than silently skipping checks for
## it; update this table when adding a new concept whose natural range
## is a percentage, balance, or growth rate instead.
plausibility_categories <- tibble::tribble(
  ~label,                                  ~category,
  "unemployment_rate",                     "percent",
  "employment_rate",                       "percent",
  "short_term_rate",                       "percent",
  "long_term_rate",                        "percent",
  "mortgage_rate",                         "percent",
  "credit_to_private_nonfin_sector",       "percent",
  "household_credit_to_gdp",               "percent",
  "corporate_credit_to_gdp",               "percent",
  "government_debt_to_gdp",                "percent",
  "industrial_confidence",                 "balance",
  "employment_expectations",               "balance",
  "construction_confidence",               "balance",
  "retail_confidence",                     "balance",
  "consumer_confidence",                   "balance",
  "economic_sentiment_indicator",          "balance",
  "services_confidence",                   "balance",
  "euro_area_household_net_worth_growth",  "growth"
)

## Bounds per category: c(low, high). "percent" allows negative policy
## rates and >100% debt-to-GDP ratios (both real and observed); "balance"
## covers both EC survey balances (roughly -100..100) and the ESI's
## 0..~150 scale in one relaxed band; "growth" is a quarterly growth
## rate, generous enough for crisis-period swings.
plausibility_bounds <- list(
  percent = c(-10, 400),
  balance = c(-150, 250),
  growth  = c(-50, 50)
)

jump_threshold <- 0.90     # flag |quarter-over-quarter % change| above this, "level" category only
min_obs_for_trend <- 4     # need at least this many observations to run the jump check at all

#' Look up a concept's measurement category, defaulting to "level" (the
#' strictest: values must be positive) for anything not explicitly listed
plausibility_category <- function(label) {
  row <- plausibility_categories[plausibility_categories$label == label, ]
  if (nrow(row) == 1) row$category[1] else "level"
}

#' Run all three plausibility checks for one resolved concept's values
#'
#' `values` should already have NAs dropped and be in chronological
#' order (as `panel[[label]]` is, since `panel` is always
#' `dplyr::arrange(panel, date)`d before this runs).
check_one_concept <- function(label, values) {
  category <- plausibility_category(label)
  n_obs <- length(values)

  if (n_obs == 0) {
    return(list(label = label, category = category, status = "NO_DATA", detail = "No non-NA observations."))
  }
  if (n_obs < min_obs_for_trend) {
    return(list(label = label, category = category, status = "TOO_SHORT",
                detail = sprintf("Only %d observation(s) -- too few to check a trend.", n_obs)))
  }

  if (category %in% names(plausibility_bounds)) {
    bounds <- plausibility_bounds[[category]]
    out_of_range <- values < bounds[1] | values > bounds[2]
    if (any(out_of_range)) {
      bad <- values[out_of_range][1]
      return(list(label = label, category = category, status = "FLAG",
                  detail = sprintf("Value %.3g outside the expected %s range [%g, %g].", bad, category, bounds[1], bounds[2])))
    }
    return(list(label = label, category = category, status = "PASS",
                detail = sprintf("All %d values within [%g, %g].", n_obs, bounds[1], bounds[2])))
  }

  ## category == "level": must be positive, and no implausible qoq jump
  if (any(values <= 0)) {
    bad <- values[values <= 0][1]
    return(list(label = label, category = category, status = "FLAG",
                detail = sprintf("Non-positive value %.3g found in a level/index concept.", bad)))
  }
  qoq <- diff(values) / values[-length(values)]
  worst <- qoq[which.max(abs(qoq))]
  if (abs(worst) > jump_threshold) {
    return(list(label = label, category = category, status = "FLAG",
                detail = sprintf("Largest quarter-over-quarter change is %.0f%%, above the %.0f%% heuristic threshold -- check for a units/decimal/sector mismatch.", worst * 100, jump_threshold * 100)))
  }
  list(label = label, category = category, status = "PASS",
       detail = sprintf("Positive throughout; largest quarter-over-quarter change %.0f%%.", worst * 100))
}

#' Run plausibility checks for every canonical column of a finished panel
#'
#' `panel` is the same wide, date-sorted, canonical-schema tibble
#' `scripts/build_country_panel.R` writes to `<country>_nipa.csv`;
#' `canonical_cols` is `concept_group_map$label`. Returns a list of
#' per-concept result lists (label/category/status/detail), in
#' `canonical_cols` order, suitable for `jsonlite::write_json()`.
run_plausibility_checks <- function(panel, canonical_cols) {
  purrr::map(canonical_cols, function(label) {
    values <- panel[[label]]
    values <- values[!is.na(values)]
    check_one_concept(label, values)
  })
}
