## Opt-in integration test that hits the REAL APIs (no mocking). Skipped
## by default so the ordinary test suite stays fast and offline-safe.
##
## Run explicitly with:
##   AUSTRIAMACRODATA_RUN_INTEGRATION=true Rscript -e 'testthat::test_dir("tests/testthat")'
## or on Windows PowerShell:
##   $env:AUSTRIAMACRODATA_RUN_INTEGRATION="true"; Rscript -e "testthat::test_dir('tests/testthat')"

skip_integration_unless_opted_in <- function() {
  testthat::skip_if_not(
    identical(Sys.getenv("AUSTRIAMACRODATA_RUN_INTEGRATION"), "true"),
    "integration test skipped (set AUSTRIAMACRODATA_RUN_INTEGRATION=true to run)"
  )
  testthat::skip_if_offline()
}

test_that("OECD QNA returns real USA GDP data (live)", {
  skip_integration_unless_opted_in()
  out <- fetch_oecd_series("USA", "S1", "", "B1GQ", "real_gdp", start_period = "2020-Q1")
  expect_false(is.null(out))
  expect_true(nrow(out) > 0)
  expect_true(all(out$real_gdp > 0))
})

test_that("IMF QNEA returns real USA GDP data (live)", {
  skip_integration_unless_opted_in()
  out <- fetch_imf_qnea("USA", "B1GQ", "real_gdp", start_period = "2020-Q1")
  expect_false(is.null(out))
  expect_true(nrow(out) > 0)
})

test_that("BIS WS_TC returns real US credit data (live)", {
  skip_integration_unless_opted_in()
  out <- fetch_bis_credit("US", start_period = "2020-Q1")
  expect_false(is.null(out))
  expect_true(nrow(out) > 0)
})

test_that("ECB QSA_PUB returns the real euro-area household net worth series (live)", {
  skip_integration_unless_opted_in()
  out <- fetch_ecb_household_networth("DEU", start_period = "2020-Q1")
  expect_false(is.null(out))
  expect_true(nrow(out) > 0)
})

test_that("FRED mirror returns real German long-term rate data (live)", {
  skip_integration_unless_opted_in()
  out <- get_fred_series("IRLTLT01DEQ156N")
  expect_false(is.null(out))
  expect_true(nrow(out) > 0)
})

test_that("end-to-end USA validation run passes for at least the core GDP concept (live)", {
  skip_integration_unless_opted_in()
  anchor_merged <- fetch_oecd_anchors("USA", start_period = "2015-Q1")
  expect_false(is.null(anchor_merged))
  expect_true("real_gdp" %in% names(anchor_merged))

  fred_qd_actual <- fetch_actual_fred_qd(
    "https://www.stlouisfed.org/-/media/project/frbstl/stlouisfed/research/fred-md/quarterly/2026-07-qd.csv"
  )
  skip_if(is.null(fred_qd_actual), "FRED-QD vintage URL unavailable")

  results <- validate_against_fred_qd(anchor_merged, fred_qd_actual)
  gdp_row <- results[results$our_label == "real_gdp", ]
  expect_equal(gdp_row$status, "PASS")
  expect_gt(gdp_row$correlation, 0.9)
})
