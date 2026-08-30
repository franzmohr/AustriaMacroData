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
