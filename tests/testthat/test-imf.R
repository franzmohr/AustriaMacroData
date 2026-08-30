## Fixture mirrors the real shape confirmed live against
## api.imf.org/external/sdmx/3.0 (IMF.STA:QNEA v7.0.0, format=csv) on
## 2026-08-30.
imf_gdp_fixture <- paste(
  "STRUCTURE,STRUCTURE_ID,ACTION,COUNTRY,INDICATOR,PRICE_TYPE,S_ADJUSTMENT,TYPE_OF_TRANSFORMATION,FREQUENCY,TIME_PERIOD,OBS_VALUE",
  "dataflow,IMF.STA:QNEA(7.0.0),R,USA,B1GQ,Q,SA,XDC,Q,2020-Q1,21538032000000",
  "dataflow,IMF.STA:QNEA(7.0.0),R,USA,B1GQ,Q,SA,XDC,Q,2020-Q2,19636731000000",
  sep = "\n"
)

## Real shape of an empty match: header only, one all-blank data row --
## confirmed live for USA + B6G (household disposable income), which IMF
## QNEA does not carry for the US.
imf_empty_fixture <- paste(
  "STRUCTURE,STRUCTURE_ID,ACTION,COUNTRY,INDICATOR,PRICE_TYPE,S_ADJUSTMENT,TYPE_OF_TRANSFORMATION,FREQUENCY,TIME_PERIOD,OBS_VALUE",
  "dataflow,IMF.STA:QNEA(7.0.0),R,,,,,,,,",
  sep = "\n"
)

test_that("fetch_imf_qnea parses a successful response", {
  with_mock_fetch_text(const_fetch_text(imf_gdp_fixture), {
    out <- fetch_imf_qnea("USA", "B1GQ", "real_gdp")
  })
  expect_equal(names(out), c("period", "real_gdp"))
  expect_equal(out$real_gdp, c(21538032000000, 19636731000000))
})

test_that("fetch_imf_qnea warns and returns NULL when the series exists but has no observations", {
  with_mock_fetch_text(const_fetch_text(imf_empty_fixture), {
    expect_warning(out <- fetch_imf_qnea("USA", "B6G", "real_household_disposable_income"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_imf_qnea detects and warns when the API returns JSON instead of the requested CSV", {
  json_body <- '{"meta":{},"data":{"dataSets":[{"structure":0}]}}'
  with_mock_fetch_text(const_fetch_text(json_body), {
    expect_warning(out <- fetch_imf_qnea("USA", "B1GQ", "real_gdp"), "returned JSON")
  })
  expect_null(out)
})

test_that("fetch_imf_qnea never throws, wrapping unexpected errors as a warning", {
  with_mock_fetch_text(function(url, ...) stop("simulated network chaos"), {
    expect_warning(out <- fetch_imf_qnea("USA", "B1GQ", "real_gdp"), "errored unexpectedly")
  })
  expect_null(out)
})

test_that("fetch_imf_fallbacks only attempts the requested missing labels", {
  with_mock_fetch_text(const_fetch_text(imf_gdp_fixture), {
    out <- fetch_imf_fallbacks("USA", c("real_gdp"))
  })
  expect_named(out, "real_gdp")
})

test_that("imf_indicator_map has no row for household disposable income (verified absent from QNEA)", {
  expect_false("real_household_disposable_income" %in% imf_indicator_map$label)
})
