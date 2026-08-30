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
