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
## <country>_panel.csv and docs/data_sources.csv by hand, concept by
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
##   2. Extreme quarter-over-quarter jumps (levels/indices only, and NOT
##      "level_event_driven" concepts -- see below) -- a
##      >|JUMP_THRESHOLD| swing between adjacent quarters is far more
##      often a units or decimal error (millions vs billions, a wrong
##      OBS_VALUE column, a mis-set UNIT_MULT) than a real economic
##      event; genuine shocks (COVID-19) are large but rarely THIS large
##      quarter-on-quarter for whole-economy aggregates. PROOF THIS WORKS:
##      this exact check caught a real, previously-unknown bug the first
##      time it ran live (2026-08-30) -- `merge_prefer()`'s naive
##      Eurostat/OECD splice was combining OECD's annualized-rate levels
##      with Eurostat's true quarterly levels, producing a ~4x
##      discontinuity across all six anchor concepts at the exact
##      handoff quarter. The pre-existing `--validate` flag, which only
##      compares growth rates, never caught it (annualizing barely
##      changes a growth rate). Fixed by `splice_prefer()` in
##      `R/utils.R` -- see its header for the full account.
##   3. Coverage sparsity -- a resolved concept with fewer than
##      MIN_OBS_FOR_TREND observations can't usefully support either
##      check above, so it is reported as "TOO_SHORT" rather than
##      silently skipped or falsely passed.
##
## A fourth category, "level_event_driven" (currently just
## geopolitical_risk), is exempted from check 2 specifically: it is
## legitimately spiky by construction (confirmed live that Austria's
## largest GPR jumps land exactly on the Gulf War, 9/11, and Russia's
## invasion of Ukraine -- see `check_one_concept()`), so the jump check
## would flag it on every real crisis, forever, teaching researchers to
## ignore the tool rather than trust it.
##
## These are DELIBERATELY loose, heuristic bounds, not authoritative
## thresholds -- the goal is to flag the small number of concepts most
## likely to reward a researcher's limited manual-verification time
## (Sections below in CONTRIBUTING.md), not to certify correctness. A
## PASS here is not proof a series is right; a FLAG is not proof it is
## wrong -- it is a prioritized to-do list.
## ---------------------------------------------------------------

## Category assignment for all 38 concepts, derived from
## R/concept_dictionary.R's `plausibility_category` column -- the single
## authored source for this and every other piece of concept-level
## metadata (see that file's header for why this used to be its own
## hand-maintained table). A concept added to `concept_dictionary` in the
## future without an explicit category still defaults through to "level"
## (see `plausibility_category()` below) -- the strictest category
## (values must be positive) -- rather than silently skipping checks for
## it.
##
## Two categorization calls worth explaining, both preserved from
## `concept_dictionary`'s own rationale:
## - `unit_labor_cost`'s own CONSTRUCTION differs by country in this
##   project (see its `cross_country_note`): an INDEX LEVEL (~90-155) for
##   Austria via the Eurostat override, but an employment-based PERCENT
##   CHANGE (small numbers, can be negative) for every other country via
##   the OECD-mirror default -- confirmed live 2026-08-30 when Germany's
##   real -0.35 legitimately tripped the "level" category's positivity
##   check. "balance" is used here (not because this is a survey balance)
##   purely because its wide, sign-agnostic bounds happen to comfortably
##   fit BOTH constructions at once.
## - `cpi_index`'s FRED-mirror DEFAULT (CPALTT01{cc2}Q657N, used for every
##   non-EU country -- see R/fred_mirror.R) was discovered live
##   2026-08-30, BY THIS CHECK, to itself be a quarterly PERCENT CHANGE
##   series, not the index level its own name and its FRED-QD mnemonic
##   (CPIAUCSL, a genuine level index) both imply: confirmed directly
##   against the raw FRED series (values like 2.97, 1.31, 0.37 for
##   2022-2023, matching real US quarterly inflation rates almost
##   exactly, not a CPI level around 25-30 that a 1950s observation
##   should show). The EU-member override (Eurostat HICP) IS a genuine
##   level index. Categorized as "balance" for the same reason as
##   unit_labor_cost above -- this is a KNOWN, DOCUMENTED discovery this
##   project has not yet acted on (see README/paper Known Limitations),
##   not a miscategorization to quietly work around.
plausibility_categories <- concept_dictionary %>%
  dplyr::filter(.data$plausibility_category != "level") %>%
  dplyr::transmute(label, category = .data$plausibility_category)

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

  ## category == "level" or "level_event_driven": must be positive.
  if (any(values <= 0)) {
    bad <- values[values <= 0][1]
    return(list(label = label, category = category, status = "FLAG",
                detail = sprintf("Non-positive value %.3g found in a level/index concept.", bad)))
  }

  ## "level_event_driven" concepts (geopolitical_risk) are legitimately
  ## spiky by construction -- confirmed live 2026-08-30 that Austria's
  ## largest quarter-over-quarter GPR jumps land exactly on the Gulf War
  ## (1990-Q3, +112%), its escalation (1991-Q1, +90%), 9/11 (2001-Q3,
  ## +241%) and Russia's invasion of Ukraine (2022-Q1, +149%) -- real
  ## history, not a units/decimal error, so the jump check below does not
  ## apply to them (it would otherwise flag on every single one of those
  ## quarters, forever, for every country, which teaches researchers to
  ## ignore this tool rather than trust it).
  if (identical(category, "level_event_driven")) {
    return(list(label = label, category = category, status = "PASS",
                detail = sprintf("Positive throughout (%d observations); no jump check applied -- this concept is expected to spike sharply around real geopolitical events.", n_obs)))
  }

  ## category == "level": must ALSO show no implausible qoq jump
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
#' `scripts/build_country_panel.R` writes to `<country>_panel.csv`;
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
