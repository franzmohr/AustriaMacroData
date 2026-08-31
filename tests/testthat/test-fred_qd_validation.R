## Fixture mirrors the real FRED-QD file structure confirmed by
## downloading the actual 2026-07 vintage: row 1 = mnemonics (first
## column literally "sasdate"), row 2 = "factors" flags, row 3 =
## "transform" codes, then data rows with M/D/YYYY dates.
fred_qd_fixture <- paste(
  "sasdate,GDPC1,PCECC96",
  "factors,1,1",
  "transform,5,5",
  "1/1/2020,19000,13000",
  "4/1/2020,18200,12500",
  "7/1/2020,19500,13400",
  sep = "\n"
)

test_that("fetch_actual_fred_qd parses the 3-header-row FRED-QD structure", {
  with_mock_fetch_text(const_fetch_text(fred_qd_fixture), {
    out <- fetch_actual_fred_qd("https://example.invalid/2026-07-qd.csv")
  })
  expect_equal(nrow(out$data), 3)
  expect_equal(out$data$sasdate, as.Date(c("2020-01-01", "2020-04-01", "2020-07-01")))
  expect_equal(out$data$GDPC1, c(19000, 18200, 19500))
  expect_equal(unname(out$transform_codes["GDPC1"]), 5)
  expect_equal(unname(out$factor_flags["PCECC96"]), 1)
})

test_that("fetch_actual_fred_qd warns and returns NULL when the vintage URL 404s", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_actual_fred_qd("https://example.invalid/1999-01-qd.csv"), "updated monthly")
  })
  expect_null(out)
})

test_that("validate_against_fred_qd marks a near-perfect growth-rate match as PASS", {
  ## our_label real_gdp tracks fred_qd_mnemonic GDPC1 almost exactly
  anchor_merged <- data.frame(
    period = c("2020-Q1", "2020-Q2", "2020-Q3", "2020-Q4", "2021-Q1", "2021-Q2", "2021-Q3", "2021-Q4", "2022-Q1"),
    real_gdp = c(100, 96, 101, 103, 105, 104, 107, 109, 110)
  )
  fred_qd_data <- data.frame(
    sasdate = as.Date(c("2020-01-01","2020-04-01","2020-07-01","2020-10-01",
                         "2021-01-01","2021-04-01","2021-07-01","2021-10-01","2022-01-01")),
    GDPC1 = c(200, 192, 202, 206, 210, 208, 214, 218, 220) # exactly 2x -> identical growth rates
  )
  results <- validate_against_fred_qd(anchor_merged, list(data = fred_qd_data))
  expect_equal(results$status[results$our_label == "real_gdp"], "PASS")
  expect_gt(results$correlation[results$our_label == "real_gdp"], 0.99)
})

test_that("validate_against_fred_qd marks an unrelated series as FAIL, not silently passing", {
  anchor_merged <- data.frame(
    period = c("2020-Q1","2020-Q2","2020-Q3","2020-Q4","2021-Q1","2021-Q2","2021-Q3","2021-Q4","2022-Q1"),
    real_gdp = c(100, 96, 101, 103, 105, 90, 130, 60, 200)
  )
  fred_qd_data <- data.frame(
    sasdate = as.Date(c("2020-01-01","2020-04-01","2020-07-01","2020-10-01",
                         "2021-01-01","2021-04-01","2021-07-01","2021-10-01","2022-01-01")),
    GDPC1 = c(50, 51, 49, 52, 40, 60, 20, 90, 10) # unrelated pattern
  )
  results <- validate_against_fred_qd(anchor_merged, list(data = fred_qd_data))
  expect_equal(results$status[results$our_label == "real_gdp"], "FAIL")
})

test_that("validate_against_fred_qd reports NO_DATA rather than erroring when a concept is missing from one side", {
  anchor_merged <- data.frame(period = "2020-Q1", real_gdp = 100)
  fred_qd_data <- data.frame(sasdate = as.Date("2020-01-01"))  # no GDPC1 column
  results <- validate_against_fred_qd(anchor_merged, list(data = fred_qd_data))
  expect_equal(results$status[results$our_label == "real_gdp"], "NO_DATA")
  expect_true(is.na(results$correlation[results$our_label == "real_gdp"]))
})

test_that("fred_qd_validation_map has a row for household disposable income (it IS a real FRED-QD mnemonic)", {
  ## real_household_disposable_income has a genuine FRED-QD mnemonic
  ## (DPIC96), so it belongs in this table -- derived straight from
  ## R/concept_dictionary.R's fred_qd_mnemonic column, not hand-curated
  ## per concept. It is still never actually validated for USA, because
  ## the next test shows validate_against_fred_qd() only validates
  ## concepts present in anchor_merged, and that concept has no reliable
  ## USA source (see R/oecd.R), so it's simply absent from anchor_merged
  ## at runtime -- there's no need to also leave it out of this table.
  expect_true("real_household_disposable_income" %in% fred_qd_validation_map$our_label)
  expect_equal(
    fred_qd_validation_map$fred_qd_mnemonic[fred_qd_validation_map$our_label == "real_household_disposable_income"],
    "DPIC96"
  )
})

test_that("validate_against_fred_qd skips a concept with a real mnemonic but absent from anchor_merged", {
  ## Mirrors the actual USA runtime case: real_household_disposable_income
  ## has a row in fred_qd_validation_map (DPIC96) but is never resolved
  ## for the US, so it's simply not a column of anchor_merged.
  anchor_merged <- data.frame(period = "2020-Q1", real_gdp = 100)
  fred_qd_data <- data.frame(sasdate = as.Date("2020-01-01"), GDPC1 = 100, DPIC96 = 50)
  results <- validate_against_fred_qd(anchor_merged, list(data = fred_qd_data))
  expect_false("real_household_disposable_income" %in% results$our_label)
})
