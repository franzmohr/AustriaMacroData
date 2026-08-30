## Fixture mirrors the real shape confirmed live against stats.bis.org
## (BIS:WS_TC v2.0, format=csv) on 2026-08-30, now for the wildcarded
## all-countries bulk pull (BORROWERS_CTY blank in the request, but
## populated per-row in the response).
bis_credit_bulk_fixture <- paste(
  "FREQ,BORROWERS_CTY,TC_BORROWERS,TC_LENDERS,VALUATION,UNIT_TYPE,TC_ADJUST,TIME_PERIOD,OBS_VALUE",
  "Q,DE,P,A,M,770,A,2020-Q1,139",
  "Q,DE,P,A,M,770,A,2020-Q2,144.5",
  "Q,US,P,A,M,770,A,2020-Q1,150",
  sep = "\n"
)

test_that("fetch_bis_credit_bulk parses a successful all-countries response and caches it", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(const_fetch_text(bis_credit_bulk_fixture), {
    out <- fetch_bis_credit_bulk("P", landing_dir = landing_dir)
  })
  expect_equal(names(out), c("country2", "period", "value"))
  expect_setequal(out$country2, c("DE", "US"))
  expect_true(file.exists(file.path(landing_dir, "bis_credit_P.csv")))
})

test_that("fetch_bis_credit_bulk reads from the cache on a second call, without hitting the network again", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(const_fetch_text(bis_credit_bulk_fixture), {
    fetch_bis_credit_bulk("P", landing_dir = landing_dir)
  })

  n_calls <- 0
  with_mock_fetch_text(function(url, ...) { n_calls <<- n_calls + 1; NULL }, {
    out <- fetch_bis_credit_bulk("P", landing_dir = landing_dir)
  })
  expect_equal(n_calls, 0)
  expect_setequal(out$country2, c("DE", "US"))
})

test_that("fetch_bis_credit filters the bulk pull down to one country", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(const_fetch_text(bis_credit_bulk_fixture), {
    out <- fetch_bis_credit("DE", landing_dir = landing_dir)
  })
  expect_equal(names(out), c("period", "credit_to_private_nonfin_sector"))
  expect_equal(out$credit_to_private_nonfin_sector, c(139, 144.5))
})

test_that("fetch_bis_credit warns and returns NULL when the country isn't in the bulk pull", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(const_fetch_text(bis_credit_bulk_fixture), {
    expect_warning(out <- fetch_bis_credit("FR", landing_dir = landing_dir), "no observations for country")
  })
  expect_null(out)
})

test_that("fetch_bis_credit_bulk warns and returns NULL on a structure-mismatch error body", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  err_body <- '<message:Error><com:Text>No structures match query parameters</com:Text></message:Error>'
  with_mock_fetch_text(const_fetch_text(err_body), {
    expect_warning(out <- fetch_bis_credit_bulk("P", landing_dir = landing_dir), "no observations")
  })
  expect_null(out)
})

test_that("fetch_bis_credit_bulk warns and returns NULL when the request fails outright", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_bis_credit_bulk("P", landing_dir = landing_dir), "BIS bulk credit fetch failed")
  })
  expect_null(out)
})

test_that("BIS key uses the verified 7-dimension WS_TC order (FREQ.BORROWERS_CTY.TC_BORROWERS.TC_LENDERS.VALUATION.UNIT_TYPE.TC_ADJUST)", {
  expect_equal(bis_wstc_dims,
               c("FREQ", "BORROWERS_CTY", "TC_BORROWERS", "TC_LENDERS", "VALUATION", "UNIT_TYPE", "TC_ADJUST"))
})
