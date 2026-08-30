test_that("build_sdmx_key produces dot-separated keys with wildcards for NA/missing", {
  dims <- c(FREQ = "Q", ADJUSTMENT = "Y", REF_AREA = "DEU", SECTOR = "S1",
            COUNTERPART_SECTOR = "", TRANSACTION = "B1GQ")
  expect_equal(build_sdmx_key(dims), "Q.Y.DEU.S1..B1GQ")
})

test_that("build_sdmx_key treats NA as a wildcard segment", {
  dims <- c(A = "X", B = NA, C = "Y")
  expect_equal(build_sdmx_key(dims), "X..Y")
})

test_that("period_to_date converts YYYY-Qn to the first day of the quarter", {
  expect_equal(period_to_date("1995-Q1"), as.Date("1995-01-01"))
  expect_equal(period_to_date("2023-Q3"), as.Date("2023-07-01"))
  expect_equal(period_to_date("2000-Q4"), as.Date("2000-10-01"))
})

test_that("parse_time_value_csv extracts TIME_PERIOD/OBS_VALUE by regex regardless of other columns", {
  csv_text <- paste(
    "STRUCTURE,REF_AREA,TIME_PERIOD,OBS_VALUE,UNIT_MEASURE",
    "DATAFLOW,DEU,2020-Q1,100.5,XDC",
    "DATAFLOW,DEU,2020-Q2,101.2,XDC",
    sep = "\n"
  )
  out <- parse_time_value_csv(csv_text, "real_gdp")
  expect_equal(names(out), c("period", "real_gdp"))
  expect_equal(out$period, c("2020-Q1", "2020-Q2"))
  expect_equal(out$real_gdp, c(100.5, 101.2))
})

test_that("parse_time_value_csv returns NULL with a warning when columns are unrecognizable", {
  csv_text <- "A,B\n1,2\n"
  expect_warning(out <- parse_time_value_csv(csv_text, "some_label"), "Could not identify")
  expect_null(out)
})

test_that("parse_time_value_csv returns NULL with a warning on an empty body", {
  expect_warning(out <- parse_time_value_csv("", "some_label"), "Empty response")
  expect_null(out)
})

test_that("parse_time_value_csv returns NULL with a warning on a structurally valid but zero-row response", {
  ## Same shape as a real Eurostat 200 response for a UNIT/NA_ITEM
  ## combination that validates against the DSD but has no data for the
  ## requested country (confirmed live: namq_10_lp_ulc, unit=I10, geo=DE).
  csv_text <- "STRUCTURE,REF_AREA,TIME_PERIOD,OBS_VALUE,UNIT_MEASURE\n"
  expect_warning(out <- parse_time_value_csv(csv_text, "some_label"), "zero observations")
  expect_null(out)
})

test_that("merge_prefer fills in periods primary doesn't cover, from secondary", {
  primary <- tibble::tibble(period = c("1995-Q1", "1995-Q2"), real_gdp = c(100, 101))
  secondary <- tibble::tibble(period = c("1960-Q1", "1995-Q1", "1995-Q2"), real_gdp = c(10, 999, 999))
  out <- merge_prefer(primary, secondary)
  expect_equal(out$period, c("1960-Q1", "1995-Q1", "1995-Q2"))
  ## primary's own values win where both cover the same period
  expect_equal(out$real_gdp, c(10, 100, 101))
})

test_that("merge_prefer prefers primary's non-NA value but falls back to secondary's when primary is NA", {
  primary <- tibble::tibble(period = c("2000-Q1", "2000-Q2"), x = c(NA_real_, 5))
  secondary <- tibble::tibble(period = c("2000-Q1", "2000-Q2"), x = c(1, 2))
  out <- merge_prefer(primary, secondary)
  expect_equal(out$x, c(1, 5))
})

test_that("merge_prefer carries through columns present in only one input", {
  primary <- tibble::tibble(period = "2000-Q1", a = 1)
  secondary <- tibble::tibble(period = "2000-Q1", b = 2)
  out <- merge_prefer(primary, secondary)
  expect_equal(sort(names(out)), c("a", "b", "period"))
  expect_equal(out$a, 1)
  expect_equal(out$b, 2)
})

test_that("merge_prefer returns the non-NULL side unchanged when the other is NULL", {
  df <- tibble::tibble(period = "2000-Q1", x = 1)
  expect_equal(merge_prefer(df, NULL), df)
  expect_equal(merge_prefer(NULL, df), df)
})

test_that("merge_prefer returns NULL when both inputs are NULL", {
  expect_null(merge_prefer(NULL, NULL))
})

test_that("has_data correctly detects a usable column", {
  df <- tibble::tibble(period = c("2000-Q1", "2000-Q2"), x = c(NA_real_, 1), y = c(NA_real_, NA_real_))
  expect_true(has_data(df, "x"))
  expect_false(has_data(df, "y"))
  expect_false(has_data(df, "z"))
  expect_false(has_data(NULL, "x"))
})
