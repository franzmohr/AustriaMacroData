test_that("concept_dictionary has exactly one row per concept, no duplicates", {
  expect_equal(nrow(concept_dictionary), length(unique(concept_dictionary$label)))
  expect_false(anyNA(concept_dictionary$label))
})

test_that("concept_dictionary has the expected columns", {
  expect_setequal(
    names(concept_dictionary),
    c("label", "fred_qd_group", "fred_qd_mnemonic", "us_note", "cross_country_note", "plausibility_category")
  )
})

test_that("every row has a non-NA, valid plausibility_category", {
  valid_categories <- c("percent", "balance", "growth", "level", "level_event_driven")
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

test_that("plausibility_categories (derived view) omits the default 'level' category", {
  expect_false("level" %in% plausibility_categories$category)
  expect_true(all(plausibility_categories$label %in% concept_dictionary$label))
})
