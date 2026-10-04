## Fixtures: the shape of the ECB's csvdata responses, values as published (checked
## live 2026-10-04): Euribor 3M from FM, the Austrian 10-year yield from IRS.
euribor_fixture <- paste(
  "KEY,FREQ,REF_AREA,CURRENCY,PROVIDER_FM,INSTRUMENT_FM,PROVIDER_FM_ID,DATA_TYPE_FM,TIME_PERIOD,OBS_VALUE",
  "FM.M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,U2,EUR,RT,MM,EURIBOR3MD_,HSTA,1998-12,3.25",
  "FM.M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,U2,EUR,RT,MM,EURIBOR3MD_,HSTA,1999-01,3.13",
  "FM.M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,U2,EUR,RT,MM,EURIBOR3MD_,HSTA,2026-07,2.4253913",
  "FM.M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,U2,EUR,RT,MM,EURIBOR3MD_,HSTA,2026-08,2.5131429",
  "FM.M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,U2,EUR,RT,MM,EURIBOR3MD_,HSTA,2026-09,2.6350455",
  sep = "\n"
)
irs_fixture <- paste(
  "KEY,FREQ,REF_AREA,IR_TYPE,TR_TYPE,MATURITY_CAT,BS_COUNT_SECTOR,CURRENCY_TRANS,IR_BUS_COV,IR_FV_TYPE,TIME_PERIOD,OBS_VALUE",
  "IRS.M.AT.L.L40.CI.0000.EUR.N.Z,M,AT,L,L40,CI,0000,EUR,N,Z,2026-06,3.2074",
  "IRS.M.AT.L.L40.CI.0000.EUR.N.Z,M,AT,L,L40,CI,0000,EUR,N,Z,2026-07,3.3239",
  "IRS.M.AT.L.L40.CI.0000.EUR.N.Z,M,AT,L,L40,CI,0000,EUR,N,Z,2026-08,3.4125",
  sep = "\n"
)

test_that("Euribor is requested from FM and kept only from the country's euro adoption on", {
  captured <- NULL
  with_mock_fetch_text(function(url, ...) { captured <<- url; euribor_fixture },
                       out <- fetch_ecb_short_term_rate("AUT", start_period = "1990-M01", frequency = "M"))
  expect_match(captured, "/FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA?", fixed = TRUE)
  expect_match(captured, "startPeriod=1999-01", fixed = TRUE)
  # the synthetic pre-euro month is dropped even if the response holds it
  expect_equal(out$date, as.Date(c("1999-01-01", "2026-07-01", "2026-08-01", "2026-09-01")))
  expect_equal(out$short_term_rate[4], 2.6350455)
})

test_that("a later euro member gets Euribor only from its own adoption", {
  with_mock_fetch_text(const_fetch_text(euribor_fixture),
                       out <- fetch_ecb_short_term_rate("LTU", start_period = "1990-M01", frequency = "M"))
  expect_true(all(out$date >= as.Date("2015-01-01")))
})

test_that("the 10-year yield is requested per country from IRS and averaged into quarters", {
  captured <- NULL
  with_mock_fetch_text(function(url, ...) { captured <<- url; irs_fixture },
                       out <- fetch_ecb_long_term_rate("AUT", start_period = "2026-Q1"))
  expect_match(captured, "/IRS/M.AT.L.L40.CI.0000.EUR.N.Z?", fixed = TRUE)
  expect_equal(out$long_term_rate[out$date == as.Date("2026-04-01")], 3.2074)
  expect_equal(out$long_term_rate[out$date == as.Date("2026-07-01")], mean(c(3.3239, 3.4125)))
})

test_that("countries outside the euro area keep the mirror: no request, NULL", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; euribor_fixture }, {
    expect_null(fetch_ecb_short_term_rate("USA"))
    expect_null(fetch_ecb_long_term_rate("USA"))
  })
  expect_false(called)
})

test_that("a failed request warns and returns NULL, so the mirror stays", {
  with_mock_fetch_text(failing_fetch_text(),
                       expect_warning(out <- fetch_ecb_long_term_rate("DEU"), "mirror stays in place"))
  expect_null(out)
})
