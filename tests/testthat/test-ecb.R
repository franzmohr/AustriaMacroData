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

## Pure new loans (IR_BUS_COV=P). Values are the real Austrian business
## volumes confirmed live on 2026-10-03; 2026-Q3 is deliberately
## incomplete (July and August only), as the latest quarter usually is.
ecb_mir_volume_fixture <- paste(
  "KEY,FREQ,REF_AREA,BS_REP_SECTOR,BS_ITEM,MATURITY_NOT_IRATE,DATA_TYPE_MIR,AMOUNT_CAT,BS_COUNT_SECTOR,CURRENCY_TRANS,IR_BUS_COV,TIME_PERIOD,OBS_VALUE",
  "MIR.M.AT.B.A2C.A.B.A.2250.EUR.P,M,AT,B,A2C,A,B,A,2250,EUR,P,2026-04,1873",
  "MIR.M.AT.B.A2C.A.B.A.2250.EUR.P,M,AT,B,A2C,A,B,A,2250,EUR,P,2026-05,1699",
  "MIR.M.AT.B.A2C.A.B.A.2250.EUR.P,M,AT,B,A2C,A,B,A,2250,EUR,P,2026-06,2107",
  "MIR.M.AT.B.A2C.A.B.A.2250.EUR.P,M,AT,B,A2C,A,B,A,2250,EUR,P,2026-07,1410",
  "MIR.M.AT.B.A2C.A.B.A.2250.EUR.P,M,AT,B,A2C,A,B,A,2250,EUR,P,2026-08,1284",
  sep = "\n"
)

test_that("fetch_ecb_mortgage_new_lending requests the business volume of pure new loans", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; ecb_mir_volume_fixture }
  with_mock_fetch_text(mock, {
    fetch_ecb_mortgage_new_lending("AUT")
  })
  expect_match(captured_url, "/MIR/M.AT.B.A2C.A.B.A.2250.EUR.P?", fixed = TRUE)
})

test_that("fetch_ecb_mortgage_new_lending SUMS complete quarters and drops an incomplete one", {
  with_mock_fetch_text(const_fetch_text(ecb_mir_volume_fixture), {
    out <- fetch_ecb_mortgage_new_lending("AUT", start_period = "2026-Q1")
  })
  expect_equal(names(out), c("date", "mortgage_new_lending"))
  expect_equal(out$date, as.Date("2026-04-01"))
  expect_equal(out$mortgage_new_lending, 1873 + 1699 + 2107)
})

test_that("fetch_ecb_mortgage_new_lending keeps every month in a monthly panel", {
  with_mock_fetch_text(const_fetch_text(ecb_mir_volume_fixture), {
    out <- fetch_ecb_mortgage_new_lending("AUT", start_period = "2026-M01", frequency = "M")
  })
  expect_equal(out$date, seq(as.Date("2026-04-01"), as.Date("2026-08-01"), by = "month"))
  expect_equal(out$mortgage_new_lending, c(1873, 1699, 2107, 1410, 1284))
})

test_that("fetch_ecb_mortgage_rate_pure_new requests the pure-new-loan rate and averages it", {
  captured_url <- NULL
  fixture <- gsub("EUR,N,", "EUR,P,", gsub("EUR.N,", "EUR.P,", ecb_mir_fixture, fixed = TRUE), fixed = TRUE)
  mock <- function(url, ...) { captured_url <<- url; fixture }
  with_mock_fetch_text(mock, {
    out <- fetch_ecb_mortgage_rate_pure_new("AUT", start_period = "2026-Q1")
  })
  expect_match(captured_url, "/MIR/M.AT.B.A2C.A.R.A.2250.EUR.P?", fixed = TRUE)
  expect_equal(names(out), c("date", "mortgage_rate_pure_new_loans"))
  expect_equal(out$mortgage_rate_pure_new_loans, mean(c(3.40, 3.43, 3.45)))
})

test_that("the pure-new-loan fetchers skip a non-euro-area country without a request", {
  called <- FALSE
  mock <- function(url, ...) { called <<- TRUE; ecb_mir_volume_fixture }
  with_mock_fetch_text(mock, {
    expect_warning(a <- fetch_ecb_mortgage_new_lending("USA"), "not a euro-area country")
    expect_warning(b <- fetch_ecb_mortgage_rate_pure_new("USA"), "not a euro-area country")
  })
  expect_null(a); expect_null(b)
  expect_false(called)
})

test_that("fetch_ecb_mortgage_new_lending warns and returns NULL on a 404", {
  with_mock_fetch_text(const_fetch_text(ecb_mir_not_found_fixture), {
    expect_warning(out <- fetch_ecb_mortgage_new_lending("AUT"), "no new-mortgage-lending observations")
  })
  expect_null(out)
})

## Fixture mirrors the real shape confirmed live against
## data-api.ecb.europa.eu (dataflow BSI, format=csvdata) on 2026-08-30 --
## found via the ECB Data Portal's own published series list, not
## guessed from first principles (see R/ecb.R header for why the naive
## by-analogy-with-MIR key returned zero observations).
ecb_bsi_fixture <- paste(
  "KEY,FREQ,REF_AREA,ADJUSTMENT,BS_REP_SECTOR,BS_ITEM,MATURITY_ORIG,DATA_TYPE,COUNT_AREA,BS_COUNT_SECTOR,CURRENCY_TRANS,BS_SUFFIX,TIME_PERIOD,OBS_VALUE",
  "BSI.M.AT.N.A.A22T.A.1.U6.2250.Z01.E,M,AT,N,A,A22T,A,1,U6,2250,Z01,E,2026-04,131769",
  "BSI.M.AT.N.A.A22T.A.1.U6.2250.Z01.E,M,AT,N,A,A22T,A,1,U6,2250,Z01,E,2026-05,132005",
  "BSI.M.AT.N.A.A22T.A.1.U6.2250.Z01.E,M,AT,N,A,A22T,A,1,U6,2250,Z01,E,2026-06,133060",
  sep = "\n"
)

ecb_bsi_not_found_fixture <- '{"type":"/service/data/BSI/M.XX.N.A.A22T.A.1.U6.2250.Z01.E","title":"Not Found","status":404,"detail":"No Series was returned for the query"}'

test_that("fetch_ecb_household_mortgage_loans returns NULL for a non-euro-area country without making a request", {
  called <- FALSE
  mock <- function(url, ...) { called <<- TRUE; ecb_bsi_fixture }
  with_mock_fetch_text(mock, {
    expect_warning(out <- fetch_ecb_household_mortgage_loans("USA"), "not a euro-area country")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_ecb_household_mortgage_loans builds the confirmed 11-segment BSI key, not the MIR-by-analogy guess", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; ecb_bsi_fixture }
  with_mock_fetch_text(mock, {
    fetch_ecb_household_mortgage_loans("AUT")
  })
  expect_match(captured_url, "M\\.AT\\.N\\.A\\.A22T\\.A\\.1\\.U6\\.2250\\.Z01\\.E", perl = TRUE)
})

test_that("fetch_ecb_household_mortgage_loans averages monthly outstanding amounts into a quarterly value", {
  with_mock_fetch_text(const_fetch_text(ecb_bsi_fixture), {
    out <- fetch_ecb_household_mortgage_loans("AUT", start_period = "2026-Q2")
  })
  expect_equal(names(out), c("date", "household_mortgage_loans"))
  expect_equal(out$date, as.Date("2026-04-01"))
  expect_equal(out$household_mortgage_loans, mean(c(131769, 132005, 133060)))
})

test_that("fetch_ecb_household_mortgage_loans warns and returns NULL on a 404 (no series for this country)", {
  with_mock_fetch_text(const_fetch_text(ecb_bsi_not_found_fixture), {
    expect_warning(out <- fetch_ecb_household_mortgage_loans("AUT"), "no household-mortgage-loan observations")
  })
  expect_null(out)
})

test_that("fetch_ecb_household_mortgage_loans warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_ecb_household_mortgage_loans("AUT"), "ECB household mortgage loans fetch failed")
  })
  expect_null(out)
})

## Fixture mirrors the real shape confirmed live against
## data-api.ecb.europa.eu (dataflow CISS, format=csvdata) on 2026-09-14:
## daily, with rows that carry an empty OBS_VALUE before the country's
## coverage starts (Austria's first non-missing day is 1999-01-05).
ecb_ciss_fixture <- paste(
  "KEY,FREQ,REF_AREA,CURRENCY,PROVIDER_FM,INSTRUMENT_FM,PROVIDER_FM_ID,DATA_TYPE_FM,TIME_PERIOD,OBS_VALUE,OBS_STATUS",
  "CISS.D.AT.Z0Z.4F.EC.SS_CIN.IDX,D,AT,Z0Z,4F,EC,SS_CIN,IDX,1999-01-04,,M",
  "CISS.D.AT.Z0Z.4F.EC.SS_CIN.IDX,D,AT,Z0Z,4F,EC,SS_CIN,IDX,1999-01-05,0.020,A",
  "CISS.D.AT.Z0Z.4F.EC.SS_CIN.IDX,D,AT,Z0Z,4F,EC,SS_CIN,IDX,1999-02-15,0.040,A",
  "CISS.D.AT.Z0Z.4F.EC.SS_CIN.IDX,D,AT,Z0Z,4F,EC,SS_CIN,IDX,1999-04-01,0.100,A",
  sep = "\n"
)

ecb_ciss_not_found_fixture <- '{"type":"/service/data/CISS/D.XX.Z0Z.4F.EC.SS_CIN.IDX","title":"Not Found","status":404,"detail":"No Series was returned for the query"}'

test_that("fetch_ecb_ciss averages daily values to quarters, skipping days with an empty value", {
  with_mock_fetch_text(const_fetch_text(ecb_ciss_fixture), {
    out <- fetch_ecb_ciss("AUT")
  })
  expect_equal(names(out), c("date", "financial_stress"))
  expect_equal(out$date, as.Date(c("1999-01-01", "1999-04-01")))
  expect_equal(out$financial_stress, c(0.03, 0.10))
  expect_equal(attr(out, "key"), "D.AT.Z0Z.4F.EC.SS_CIN.IDX")
})

test_that("fetch_ecb_ciss builds the confirmed 7-segment daily key and a day-precision startPeriod", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; ecb_ciss_fixture }, {
    fetch_ecb_ciss("USA", start_period = "1980-Q1")
  })
  expect_match(captured_url, "/CISS/D.US.Z0Z.4F.EC.SS_CIN.IDX?", fixed = TRUE)
  expect_match(captured_url, "startPeriod=1980-01-01", fixed = TRUE)
})

test_that("fetch_ecb_ciss warns and returns NULL when the ECB publishes no CISS for a country", {
  with_mock_fetch_text(const_fetch_text(ecb_ciss_not_found_fixture), {
    expect_warning(out <- fetch_ecb_ciss("DEU"), "publishes no CISS")
  })
  expect_null(out)
})

test_that("fetch_ecb_ciss warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_ecb_ciss("AUT"), "ECB CISS fetch failed")
  })
  expect_null(out)
})
