test_that("ec_survey_zip_url builds the YYMM-based archive URL", {
  expect_equal(
    ec_survey_zip_url(2026, 8),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2608/main_indicators_sa_nace2.zip"
  )
  expect_equal(
    ec_survey_zip_url(2025, 1),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2501/main_indicators_sa_nace2.zip"
  )
})

test_that("ec_survey_landing_path names the cache file by year/month", {
  expect_equal(
    ec_survey_landing_path(2026, 8, "data/landing"),
    file.path("data/landing", "ec_bcs_main_indicators_2608.xlsx")
  )
})

## ---- Build a tiny real .xlsx + .zip fixture at test time --------------
## Rather than checking in a binary fixture, this constructs a
## MONTHLY-sheet-shaped workbook so the parser and cache logic are
## exercised against a real xlsx/zip, not a mock of their contents.
build_fixture_zip_bytes <- function() {
  skip_if_not_installed("writexl")
  tmp_xlsx <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_xlsx), add = TRUE)

  monthly <- data.frame(
    c1 = c(NA, "1985-01-31", "1985-02-28"),
    c2 = c("EU.CONS", "-10.2", "-10.6"),
    c3 = c("AT.CONS", "-5.1", "-6.2"),
    c4 = c("DE.CONS", "-8.0", "-8.3"),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(
    list(Index = data.frame(x = 1), INFO = data.frame(x = 1), MONTHLY = monthly),
    tmp_xlsx, col_names = FALSE
  )

  tmp_zip <- tempfile(fileext = ".zip")
  old_wd <- setwd(dirname(tmp_xlsx))
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(tmp_zip, basename(tmp_xlsx), flags = "-q")
  readBin(tmp_zip, "raw", file.info(tmp_zip)$size)
}

test_that("get_ec_survey_xlsx tries the current month first, fetches, and caches it", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  calls <- character()
  with_mock_fetch_binary(function(url, ...) {
    calls <<- c(calls, url)
    if (grepl("2608", url)) return(zip_bytes)
    NULL
  }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_equal(length(calls), 1)
  expect_true(grepl("2608", calls[1]))
  expect_equal(out$year, 2026)
  expect_equal(out$month, 8)
  expect_false(out$cached)
  expect_true(file.exists(out$path))
  expect_true(file.exists(ec_survey_landing_path(2026, 8, landing_dir)))
})

test_that("get_ec_survey_xlsx reads from the cache on a second call, without hitting the network again", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })

  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_false(called)
  expect_true(out$cached)
  expect_equal(out$month, 8)
})

test_that("get_ec_survey_xlsx walks back a month at a time until one succeeds", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  calls <- character()
  with_mock_fetch_binary(function(url, ...) {
    calls <<- c(calls, url)
    if (grepl("2607", url)) return(zip_bytes)
    NULL
  }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), max_lookback = 3, landing_dir = landing_dir)
  })
  expect_equal(length(calls), 2)
  expect_true(grepl("2608", calls[1]))
  expect_true(grepl("2607", calls[2]))
  expect_equal(out$month, 7)
})

test_that("get_ec_survey_xlsx returns NULL after exhausting the lookback window", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(failing_fetch_binary(), {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), max_lookback = 2, landing_dir = landing_dir)
  })
  expect_null(out)
})

test_that("parse_ec_consumer_confidence extracts the requested country's column", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  out <- parse_ec_consumer_confidence(xlsx_path, "AT", "consumer_confidence")
  expect_equal(names(out), c("date", "consumer_confidence"))
  expect_equal(out$consumer_confidence, c(-5.1, -6.2))
})

test_that("parse_ec_consumer_confidence returns NULL with a warning for an unknown country column", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  expect_warning(out <- parse_ec_consumer_confidence(xlsx_path, "ZZ", "consumer_confidence"), "not found")
  expect_null(out)
})

test_that("fetch_ec_consumer_confidence refuses non-EU countries without a network call", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(out <- fetch_ec_consumer_confidence("USA"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
})
