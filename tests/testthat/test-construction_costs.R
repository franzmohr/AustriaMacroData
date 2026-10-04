## Fixtures mirror the real shape confirmed live 2026-10-04 against
## Eurostat's SDMX 2.1 API (format=SDMX-CSV) for sts_copi_m / sts_copi_q,
## and FRED's fredgraph.csv for WPUIP2311001.
copi_fixture <- function(freq, indic, geo, periods, values) {
  paste(c("DATAFLOW,LAST UPDATE,freq,indic_bt,cpa2_1,s_adj,unit,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
          sprintf("ESTAT:STS_COPI_%s(1.0),01/10/26 11:00:00,%s,%s,CPA_F41001_X_410014,NSA,I21,%s,%s,%s,,",
                  freq, freq, indic, geo, periods, values)),
        collapse = "\n")
}

test_that("construction_index_key follows the verified sts_copi dimension order", {
  expect_equal(construction_index_key("COST", "AT", "M"), "M.COST.CPA_F41001_X_410014.NSA.I21.AT")
})

test_that("Austria's cost index comes monthly from sts_copi_m", {
  requested <- character()
  mock <- function(url, ...) {
    requested <<- c(requested, url)
    copi_fixture("M", "COST", "AT", c("2026-07", "2026-08"), c(124.5, 124.6))
  }
  with_mock_fetch_text(mock, {
    out <- fetch_construction_index("AUT", "construction_cost_index", start_period = "2026-M01", frequency = "M")
  })
  expect_true(grepl("sts_copi_m/M.COST.CPA_F41001_X_410014.NSA.I21.AT", requested, fixed = TRUE))
  expect_equal(out$date, as.Date(c("2026-07-01", "2026-08-01")))
  expect_equal(out$construction_cost_index, c(124.5, 124.6))
  expect_equal(attr(out, "provider"), "EUROSTAT_STS")
})

test_that("Germany's quarterly producer prices come from sts_copi_q", {
  with_mock_fetch_text(function(url, ...) {
    expect_true(grepl("sts_copi_q/Q.PRC_PRR.", url, fixed = TRUE))
    copi_fixture("Q", "PRC_PRR", "DE", c("2026-Q1", "2026-Q2"), c(137.0, 140.3))
  }, {
    out <- fetch_construction_index("DEU", "construction_producer_prices", start_period = "2026-Q1", frequency = "Q")
  })
  expect_equal(out$date, as.Date(c("2026-01-01", "2026-04-01")))
  expect_equal(out$construction_producer_prices, c(137.0, 140.3))
})

test_that("a missing Eurostat series returns NULL with a warning, so the caller can fall back", {
  with_mock_fetch_text(const_fetch_text("<S:Fault>No results found</S:Fault>"), {
    expect_warning(out <- fetch_construction_index("DEU", "construction_cost_index", frequency = "M"),
                   "no observations")
  })
  expect_null(out)
})

test_that("the USA's cost index comes from FRED, and it has no producer price index", {
  fred <- "observation_date,WPUIP2311001\n2026-07-01,348.0\n2026-08-01,349.0\n2026-09-01,350.0\n"
  with_mock_fetch_text(const_fetch_text(fred), {
    m <- fetch_construction_index("USA", "construction_cost_index", start_period = "2026-M01", frequency = "M")
    q <- fetch_construction_index("USA", "construction_cost_index", start_period = "2026-Q1", frequency = "Q")
  })
  expect_equal(m$construction_cost_index, c(348, 349, 350))
  expect_equal(attr(m, "provider"), "FRED")
  expect_equal(q$construction_cost_index, 349)
  with_mock_fetch_text(function(url, ...) stop("no request expected"), {
    expect_null(fetch_construction_index("USA", "construction_producer_prices", frequency = "M"))
    expect_null(fetch_construction_index("JPN", "construction_cost_index", frequency = "M"))
  })
})

test_that("fetch_quarterly_fallbacks fetches only the unresolved concepts it knows, and marks them", {
  requested <- character()
  mock <- function(url, ...) {
    requested <<- c(requested, url)
    copi_fixture("Q", "COST", "DE", c("2026-Q1", "2026-Q2"), c(130.1, 131.2))
  }
  with_mock_fetch_text(mock, {
    out <- fetch_quarterly_fallbacks("DEU", "2026-Q1", c("construction_cost_index", "industrial_production"))
  })
  expect_length(requested, 1)
  expect_equal(names(out$panel), c("date", "construction_cost_index"))
  expect_true(out$concept_source$construction_cost_index$quarterly_at_source)
})
