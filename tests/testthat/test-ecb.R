## Fixture mirrors the real shape confirmed live against
## data-api.ecb.europa.eu (ECB.DISS:QSA_PUB v1.0, format=csvdata) on
## 2026-08-30. Note REF_AREA is always "I8" (euro-area aggregate) --
## no per-country series exists for this concept, see R/ecb.R header.
ecb_networth_fixture <- paste(
  "KEY,FREQ,ADJUSTMENT,REF_AREA,TIME_PERIOD,OBS_VALUE",
  "QSA.Q.N.I8...,Q,N,I8,2020-Q1,3.69",
  "QSA.Q.N.I8...,Q,N,I8,2020-Q2,4.73",
  sep = "\n"
)

test_that("fetch_ecb_household_networth returns NULL for a non-euro-area country without making a request", {
  called <- FALSE
  mock <- function(url, ...) { called <<- TRUE; ecb_networth_fixture }
  with_mock_fetch_text(mock, {
    expect_warning(out <- fetch_ecb_household_networth("USA"), "not a euro-area country")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_ecb_household_networth parses the euro-area aggregate for a euro-area country", {
  with_mock_fetch_text(const_fetch_text(ecb_networth_fixture), {
    out <- fetch_ecb_household_networth("DEU")
  })
  expect_equal(names(out), c("period", "euro_area_household_net_worth_growth"))
  expect_equal(out$euro_area_household_net_worth_growth, c(3.69, 4.73))
})

test_that("fetch_ecb_household_networth always requests REF_AREA=I8, never a country code, regardless of which euro-area country was asked for", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; ecb_networth_fixture }
  with_mock_fetch_text(mock, {
    fetch_ecb_household_networth("AUT")
  })
  expect_match(captured_url, "\\.I8\\.", perl = TRUE)
  expect_false(grepl("\\.AUT\\.", captured_url))
})

test_that("euro_area_countries covers the countries the original script listed", {
  expect_true(all(c("AUT", "DEU", "FRA", "ITA", "ESP", "NLD") %in% euro_area_countries))
  expect_false("USA" %in% euro_area_countries)
  expect_false("GBR" %in% euro_area_countries)
})

## Fixture mirrors the real shape confirmed live against
## data-api.ecb.europa.eu (dataflow MIR, format=csvdata) on 2026-08-30 --
## monthly, genuinely country-specific (KEY's REF_AREA segment is the
## requested country, unlike the QSA_PUB net-worth series above).
ecb_mir_fixture <- paste(
  "KEY,FREQ,REF_AREA,BS_REP_SECTOR,BS_ITEM,MATURITY_NOT_IRATE,DATA_TYPE_MIR,AMOUNT_CAT,BS_COUNT_SECTOR,CURRENCY_TRANS,IR_BUS_COV,TIME_PERIOD,OBS_VALUE",
  "MIR.M.AT.B.A2C.A.R.A.2250.EUR.N,M,AT,B,A2C,A,R,A,2250,EUR,N,2026-01,3.40",
  "MIR.M.AT.B.A2C.A.R.A.2250.EUR.N,M,AT,B,A2C,A,R,A,2250,EUR,N,2026-02,3.43",
  "MIR.M.AT.B.A2C.A.R.A.2250.EUR.N,M,AT,B,A2C,A,R,A,2250,EUR,N,2026-03,3.45",
  sep = "\n"
)

ecb_mir_not_found_fixture <- '{"type":"/service/data/MIR/M.US.B.A2C.A.R.A.2250.EUR.N","title":"Not Found","status":404,"detail":"No Series was returned for the query"}'

test_that("fetch_ecb_mortgage_rate returns NULL for a non-euro-area country without making a request", {
  called <- FALSE
  mock <- function(url, ...) { called <<- TRUE; ecb_mir_fixture }
  with_mock_fetch_text(mock, {
    expect_warning(out <- fetch_ecb_mortgage_rate("USA"), "not a euro-area country")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_ecb_mortgage_rate requests the country's own REF_AREA, not a shared aggregate", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; ecb_mir_fixture }
  with_mock_fetch_text(mock, {
    fetch_ecb_mortgage_rate("AUT")
  })
  expect_match(captured_url, "M\\.AT\\.B\\.A2C", perl = TRUE)
})

test_that("fetch_ecb_mortgage_rate averages monthly rates into a quarterly value", {
  with_mock_fetch_text(const_fetch_text(ecb_mir_fixture), {
    out <- fetch_ecb_mortgage_rate("AUT", start_period = "2026-Q1")
  })
  expect_equal(names(out), c("date", "mortgage_rate"))
  expect_equal(out$date, as.Date("2026-01-01"))
  expect_equal(out$mortgage_rate, mean(c(3.40, 3.43, 3.45)))
})

test_that("fetch_ecb_mortgage_rate warns and returns NULL on a 404 (no series for this country)", {
  with_mock_fetch_text(const_fetch_text(ecb_mir_not_found_fixture), {
    expect_warning(out <- fetch_ecb_mortgage_rate("AUT"), "no mortgage-rate observations")
  })
  expect_null(out)
})

test_that("fetch_ecb_mortgage_rate warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_ecb_mortgage_rate("AUT"), "ECB mortgage rate fetch failed")
  })
  expect_null(out)
})
