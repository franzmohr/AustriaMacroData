test_that("concept_dictionary has exactly one row per concept, no duplicates", {
  expect_equal(nrow(concept_dictionary), length(unique(concept_dictionary$label)))
  expect_false(anyNA(concept_dictionary$label))
})

test_that("concept_dictionary has the expected columns", {
  expect_setequal(
    names(concept_dictionary),
    c("label", "fred_qd_group", "fred_qd_mnemonic", "us_note", "cross_country_note", "plausibility_category", "available_monthly",
      "aggregation", "unit", "sa", "tcode_fred", "class", "frequency", "tcode_lt", "tcode_ht")
  )
})

test_that("every concept has complete, valid series metadata", {
  expect_setequal(concept_metadata$label, concept_dictionary$label)
  expect_equal(anyDuplicated(concept_metadata$label), 0L)
  expect_true(all(concept_dictionary$aggregation %in% c("mean", "sum")))
  expect_true(all(concept_dictionary$sa %in% c("SA", "SCA", "NSA")))
  expect_true(all(concept_dictionary$class %in% c("R", "N", "F", "C")))
  expect_true(all(concept_dictionary$tcode_fred %in% 1:7))
  expect_true(all(concept_dictionary$tcode_lt %in% 0:5))
  expect_true(all(concept_dictionary$tcode_ht %in% 0:5))
  expect_true(all(concept_dictionary$frequency %in% c("M", "Q")))
  expect_false(anyNA(concept_dictionary$unit))
})

test_that("the flows are summed and nothing else is", {
  # A summed concept that is a stock would triple every quarter; an
  # averaged flow would show a third of it. Both look like plausible data.
  expect_setequal(concept_dictionary$label[concept_dictionary$aggregation == "sum"],
                  c("mortgage_new_lending", "mortgage_new_lending_oenb", "heating_degree_days", "cooling_degree_days"))
})

test_that("FRED-QD's own transformation codes are kept for the concepts that map to it", {
  code <- function(lbl) concept_dictionary$tcode_fred[concept_dictionary$label == lbl]
  expect_equal(code("real_gdp"), 5L)
  expect_equal(code("cpi_index"), 6L)
  expect_equal(code("unemployment_rate"), 2L)
  expect_equal(code("consumer_confidence"), 1L)
})

test_that("ea_md_qd_codes differences prices and nominal stocks twice only in the heavy set", {
  codes <- ea_md_qd_codes(c(6L, 5L, 5L, 5L, 2L, 1L), c("N", "N", "N", "R", "F", "C"),
                          c("mean", "mean", "sum", "mean", "mean", "mean"))
  expect_equal(codes$light, c(2L, 2L, 2L, 2L, 4L, 0L))
  expect_equal(codes$heavy, c(3L, 3L, 2L, 2L, 4L, 0L))
})

test_that("every row has a non-NA, valid plausibility_category", {
  valid_categories <- c("percent", "balance", "growth", "deviation", "level", "level_event_driven", "nonneg_seasonal", "nonneg_event_driven")
  expect_false(anyNA(concept_dictionary$plausibility_category))
  expect_true(all(concept_dictionary$plausibility_category %in% valid_categories))
})

test_that("every row has a non-NA fred_qd_group", {
  expect_false(anyNA(concept_dictionary$fred_qd_group))
})

test_that("a concept with no fred_qd_mnemonic has a us_note explaining why", {
  no_mnemonic <- concept_dictionary[is.na(concept_dictionary$fred_qd_mnemonic), ]
  expect_true(all(!is.na(no_mnemonic$us_note)))
})

test_that("downstream tables derived from concept_dictionary agree on real_gfcf_total's mnemonic", {
  ## Regression test for the bug this file was created to prevent:
  ## concept_group_map (via scripts/build_country_panel.R) and
  ## fred_qd_validation_map (R/fred_qd_validation.R) independently
  ## disagreed about this concept's FRED-QD reference (FPIx vs GPDIC1)
  ## until both started deriving from this one table.
  expect_equal(
    concept_dictionary$fred_qd_mnemonic[concept_dictionary$label == "real_gfcf_total"],
    "FPIx"
  )
  expect_true("real_gfcf_total" %in% fred_qd_validation_map$our_label)
  expect_equal(
    fred_qd_validation_map$fred_qd_mnemonic[fred_qd_validation_map$our_label == "real_gfcf_total"],
    "FPIx"
  )
})

## Note: `concept_group_map` and `concept_notes` are derived views defined
## in scripts/build_country_panel.R (a CLI entrypoint, not an R/ module),
## so they aren't in scope here -- tests/testthat/setup.R only sources
## R/*.R. They're exercised live every time the CLI runs; see this
## project's Verification section in README.md.

test_that("every non-'level' plausibility category has bounds defined for it", {
  ## A category named in concept_dictionary but absent from
  ## plausibility_bounds falls through `check_one_concept()` to the
  ## "level" branch, silently applying a positivity and jump check the
  ## category was invented to avoid -- the exact trap "nonneg_seasonal"
  ## (the degree-day concepts) was added to escape.
  expect_true(all(unique(plausibility_categories$category) %in% names(plausibility_bounds) |
                    unique(plausibility_categories$category) == "level_event_driven"))
})

test_that("plausibility_categories (derived view) omits the default 'level' category", {
  expect_false("level" %in% plausibility_categories$category)
  expect_true(all(plausibility_categories$label %in% concept_dictionary$label))
})

test_that("available_monthly is a flag on every row and marks nothing quarterly-only", {
  expect_type(concept_dictionary$available_monthly, "logical")
  expect_false(anyNA(concept_dictionary$available_monthly))

  monthly <- concept_dictionary$label[concept_dictionary$available_monthly]
  expect_gt(length(monthly), 20)
  expect_lt(length(monthly), nrow(concept_dictionary))

  # scripts/build_monthly_panel.R takes its whole concept list from this
  # column, so a concept that is quarterly at source and marked TRUE here
  # would come back either empty or interpolated, and neither is visible in
  # the output CSV. The national accounts are the clearest case: Eurostat
  # and the OECD publish them quarterly and nobody publishes them monthly.
  quarterly_at_source <- c("real_gdp", "real_household_consumption",
                           "real_govt_consumption", "real_gfcf_total",
                           "real_exports", "real_imports",
                           "real_household_disposable_income", "hours_worked",
                           "unit_labor_cost", "employment_rate",
                           "house_price_real", "credit_to_private_nonfin_sector",
                           "household_credit_to_gdp", "corporate_credit_to_gdp",
                           "government_debt_to_gdp",
                           "government_primary_balance_to_gdp",
                           "euro_area_household_net_worth_growth",
                           "world_uncertainty_index")
  expect_false(any(quarterly_at_source %in% monthly))
})
