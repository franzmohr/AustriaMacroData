test_that("plausibility_category defaults to 'level' for an unlisted concept", {
  expect_equal(plausibility_category("real_gdp"), "level")
  expect_equal(plausibility_category("some_future_concept_not_yet_categorized"), "level")
})

test_that("plausibility_category looks up percent/balance/growth concepts correctly", {
  expect_equal(plausibility_category("unemployment_rate"), "percent")
  expect_equal(plausibility_category("consumer_confidence"), "balance")
  expect_equal(plausibility_category("euro_area_household_net_worth_growth"), "growth")
})

test_that("check_one_concept returns NO_DATA for an empty series", {
  out <- check_one_concept("real_gdp", numeric(0))
  expect_equal(out$status, "NO_DATA")
})

test_that("check_one_concept returns TOO_SHORT for a series shorter than min_obs_for_trend", {
  out <- check_one_concept("real_gdp", c(100, 101))
  expect_equal(out$status, "TOO_SHORT")
})

test_that("check_one_concept passes a plausible percent-category series", {
  out <- check_one_concept("unemployment_rate", c(4.1, 4.3, 4.0, 4.2, 4.5))
  expect_equal(out$status, "PASS")
  expect_equal(out$category, "percent")
})

test_that("check_one_concept flags a percent-category series with an impossible value", {
  ## A unit slip (e.g. a fraction 0.045 mixed with real percentages 4.5,
  ## or a wildly wrong sector code) should trip the bound.
  out <- check_one_concept("unemployment_rate", c(4.1, 4.3, 950, 4.2, 4.5))
  expect_equal(out$status, "FLAG")
  expect_match(out$detail, "outside the expected percent range")
})

test_that("check_one_concept flags a negative rate outside the percent bound but not a mildly negative one", {
  ## Negative policy rates are real (ECB, 2015-2022) -- must not flag -0.5.
  out_ok <- check_one_concept("short_term_rate", c(-0.5, -0.4, -0.3, -0.2, -0.1))
  expect_equal(out_ok$status, "PASS")
  ## But -40 is never a real short-term interest rate.
  out_bad <- check_one_concept("short_term_rate", c(-0.5, -40, -0.3, -0.2, -0.1))
  expect_equal(out_bad$status, "FLAG")
})

test_that("check_one_concept passes a plausible balance-category series (ESI-scale and balance-scale)", {
  expect_equal(check_one_concept("economic_sentiment_indicator", c(95, 98, 101, 97, 99))$status, "PASS")
  expect_equal(check_one_concept("consumer_confidence", c(-15, -12, -18, -10, -14))$status, "PASS")
})

test_that("check_one_concept flags a growth-category series with an implausible quarterly swing", {
  out <- check_one_concept("euro_area_household_net_worth_growth", c(2.1, 1.8, 2.4, 300, 1.9))
  expect_equal(out$status, "FLAG")
})

test_that("check_one_concept passes a level-category series with normal growth", {
  out <- check_one_concept("real_gdp", c(100, 101, 102.5, 103, 104.2))
  expect_equal(out$status, "PASS")
  expect_equal(out$category, "level")
})

test_that("check_one_concept flags a non-positive value in a level-category series", {
  out <- check_one_concept("real_gdp", c(100, 101, -5, 103, 104))
  expect_equal(out$status, "FLAG")
  expect_match(out$detail, "Non-positive value")
})

test_that("check_one_concept flags an extreme quarter-over-quarter jump in a level-category series", {
  ## A 1000x jump like this is the classic units-mismatch signature
  ## (e.g. thousands vs millions), not a real economic event.
  out <- check_one_concept("household_mortgage_loans", c(130000, 131000, 130500000, 132000, 133000))
  expect_equal(out$status, "FLAG")
  expect_match(out$detail, "quarter-over-quarter change")
})

test_that("check_one_concept exempts level_event_driven concepts from the jump check", {
  ## Real Austrian GPR-style spikes (Gulf War, 9/11, Ukraine invasion)
  ## routinely exceed the 90% jump threshold -- must still PASS.
  out <- check_one_concept("geopolitical_risk", c(61.0, 207.9, 90.3, 224.6, 100.0))
  expect_equal(out$status, "PASS")
  expect_equal(out$category, "level_event_driven")
})

test_that("check_one_concept still flags a non-positive value for a level_event_driven concept", {
  out <- check_one_concept("geopolitical_risk", c(100, -5, 90, 110, 95))
  expect_equal(out$status, "FLAG")
  expect_match(out$detail, "Non-positive value")
})

test_that("check_one_concept accepts both constructions of unit_labor_cost (index level or % change)", {
  ## Austria: an index level around 90-155 (Eurostat NULC_HW override)
  expect_equal(check_one_concept("unit_labor_cost", c(120, 122, 121, 123, 125))$status, "PASS")
  ## Germany/USA: a small, possibly-negative % change (OECD-mirror default)
  expect_equal(check_one_concept("unit_labor_cost", c(1.2, -0.35, 0.8, -0.1, 0.5))$status, "PASS")
})

test_that("check_one_concept accepts both constructions of cpi_index (index level or % change)", {
  ## EU members: a genuine index level (Eurostat HICP override)
  expect_equal(check_one_concept("cpi_index", c(150, 152, 151, 153, 155))$status, "PASS")
  ## Non-EU countries: a quarterly % change, including a real 0% quarter
  ## (confirmed live 2026-08-30 for the US FRED-mirror default) -- must
  ## NOT be flagged as a non-positive level/index value.
  expect_equal(check_one_concept("cpi_index", c(0.5, 0, 0.3, 1.1, 0.8))$status, "PASS")
})

test_that("check_one_concept does not flag a large but plausible level swing (e.g. COVID-era)", {
  ## A ~35% single-quarter drop (2020-Q2 GDP-type shock) should NOT trip
  ## the 90% heuristic threshold.
  out <- check_one_concept("real_gdp", c(100, 101, 65, 95, 102))
  expect_equal(out$status, "PASS")
})

test_that("run_plausibility_checks returns one result per canonical column, in order", {
  panel <- tibble::tibble(
    date = as.Date(c("2020-01-01", "2020-04-01", "2020-07-01", "2020-10-01", "2021-01-01")),
    real_gdp = c(100, 101, 102, 103, 104),
    unemployment_rate = c(4.1, 4.3, NA, 4.2, 4.5),
    some_all_na_concept = c(NA_real_, NA_real_, NA_real_, NA_real_, NA_real_)
  )
  out <- run_plausibility_checks(panel, c("real_gdp", "unemployment_rate", "some_all_na_concept"))
  expect_equal(length(out), 3)
  expect_equal(vapply(out, function(x) x$label, character(1)),
               c("real_gdp", "unemployment_rate", "some_all_na_concept"))
  expect_equal(out[[1]]$status, "PASS")
  expect_equal(out[[2]]$status, "PASS")
  expect_equal(out[[3]]$status, "NO_DATA")
})
