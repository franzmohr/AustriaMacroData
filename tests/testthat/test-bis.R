## Fixture mirrors the real shape confirmed live against stats.bis.org
## (BIS:WS_TC v2.0, format=csv) on 2026-08-30.
bis_credit_fixture <- paste(
  "FREQ,BORROWERS_CTY,TC_BORROWERS,TC_LENDERS,VALUATION,UNIT_TYPE,TC_ADJUST,TIME_PERIOD,OBS_VALUE",
  "Q,DE,P,A,M,770,A,2020-Q1,139",
  "Q,DE,P,A,M,770,A,2020-Q2,144.5",
  sep = "\n"
)

test_that("fetch_bis_credit parses a successful response", {
  with_mock_fetch_text(const_fetch_text(bis_credit_fixture), {
    out <- fetch_bis_credit("DE")
  })
  expect_equal(names(out), c("period", "credit_to_private_nonfin_sector"))
  expect_equal(out$credit_to_private_nonfin_sector, c(139, 144.5))
})

test_that("fetch_bis_credit warns and returns NULL on a structure-mismatch error body", {
  err_body <- '<message:Error><com:Text>No structures match query parameters</com:Text></message:Error>'
  with_mock_fetch_text(const_fetch_text(err_body), {
    expect_warning(out <- fetch_bis_credit("DE"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_bis_credit warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_bis_credit("DE"), "BIS credit fetch failed")
  })
  expect_null(out)
})

test_that("BIS key uses the verified 7-dimension WS_TC order (FREQ.BORROWERS_CTY.TC_BORROWERS.TC_LENDERS.VALUATION.UNIT_TYPE.TC_ADJUST)", {
  expect_equal(bis_wstc_dims,
               c("FREQ", "BORROWERS_CTY", "TC_BORROWERS", "TC_LENDERS", "VALUATION", "UNIT_TYPE", "TC_ADJUST"))
})
