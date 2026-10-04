## Fixtures mirror the real shape confirmed live 2026-10-04 against
## api.statistiken.bundesbank.de (format=csv): a block of metadata rows,
## then one row per period, with "." for a day without a value.
bbk_daily_fixture <- paste(
  "﻿\"\",BBSIS.D.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A,BBSIS.D.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A_FLAGS",
  "\"\",Term structure of interest rates on listed Federal securities (method by Svensson) / residual maturity of 2.0 years / daily data,",
  "BBK_UNIT_ENG,percent,",
  "last update,2026-10-01 10:32:51,",
  "1997-08-01,.,No value available",
  "1997-08-04,3.90,",
  "1997-08-05,4.02,",
  "1997-09-01,4.04,",
  sep = "\n"
)
bbk_monthly_fixture <- paste(
  "﻿\"\",BBSIS.M.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A,BBSIS.M.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A_FLAGS",
  "BBK_UNIT_ENG,percent,",
  "1997-06,3.54,",
  "1997-07,3.78,",
  "1997-08,4.10,",
  "1997-09,4.04,",
  sep = "\n"
)
bbk_mock <- function(url, ...) {
  if (grepl("BBSIS/D.", url, fixed = TRUE)) bbk_daily_fixture else bbk_monthly_fixture
}

test_that("parse_bundesbank_csv keeps only observation rows and drops '.' days", {
  out <- parse_bundesbank_csv(bbk_daily_fixture)
  expect_equal(out$date, as.Date(c("1997-08-04", "1997-08-05", "1997-09-01")))
  expect_equal(out$value, c(3.90, 4.02, 4.04))
  monthly <- parse_bundesbank_csv(bbk_monthly_fixture)
  expect_equal(monthly$date[1], as.Date("1997-06-01"))
})

test_that("German yields average the daily values and take end-of-month values only before them", {
  with_mock_fetch_text(bbk_mock, {
    out <- fetch_gov_yield("DEU", "government_bond_yield_2y", start_period = "1997-M01", frequency = "M")
  })
  expect_equal(out$date, as.Date(c("1997-06-01", "1997-07-01", "1997-08-01", "1997-09-01")))
  ## 1997-08 is the daily mean (3.96), not the end-of-month 4.10
  expect_equal(out$government_bond_yield_2y, c(3.54, 3.78, mean(c(3.90, 4.02)), 4.04))
  expect_equal(attr(out, "provider"), "BUNDESBANK")
})

test_that("German yields request the Svensson curve at the concept's maturity", {
  requested <- character()
  with_mock_fetch_text(function(url, ...) { requested <<- c(requested, url); bbk_mock(url) }, {
    fetch_gov_yield("DEU", "government_bond_yield_5y", frequency = "M")
  })
  expect_true(any(grepl("BBSIS/D.I.ZST.ZI.EUR.S1311.B.A604.R05XX.R.A.A._Z._Z.A", requested, fixed = TRUE)))
  expect_true(any(grepl("BBSIS/M.I.ZST.ZI.EUR.S1311.B.A604.R05XX.R.A.A._Z._Z.A", requested, fixed = TRUE)))
})

test_that("US yields come from FRED's GS2 / GS5", {
  requested <- character()
  fred_fixture <- "observation_date,GS5\n2026-08-01,4.70\n2026-09-01,4.80\n"
  with_mock_fetch_text(function(url, ...) { requested <<- c(requested, url); fred_fixture }, {
    out <- fetch_gov_yield("USA", "government_bond_yield_5y", start_period = "2026-M01", frequency = "M")
  })
  expect_true(grepl("id=GS5", requested[1], fixed = TRUE))
  expect_equal(out$government_bond_yield_5y, c(4.70, 4.80))
  expect_equal(attr(out, "source_col"), "GS5")
})

test_that("Austria and other countries resolve to NULL without a request", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; "" }, {
    expect_null(fetch_gov_yield("AUT", "government_bond_yield_2y"))
    expect_null(fetch_gov_yield("FRA", "government_bond_yield_5y"))
  })
  expect_false(called)
})

test_that("a failed Bundesbank request warns and returns NULL", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_gov_yield("DEU", "government_bond_yield_2y"), "Bundesbank fetch failed")
  })
  expect_null(out)
})
