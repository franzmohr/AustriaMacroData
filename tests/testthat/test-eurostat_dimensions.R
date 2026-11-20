## Fixtures mirror the real shape of a Eurostat SDMX-CSV answer,
## confirmed live 2026-11-20 against ec.europa.eu/eurostat's SDMX 2.1 API
## for namq_10_gdp (AT): the dimension column names sit strictly between
## "LAST UPDATE" and "TIME_PERIOD", which is what lets a positional key
## be checked against the answer it produced. No test here touches the
## network -- `fetch_text()` is mocked, as everywhere else in this suite.

## The order namq_10_gdp really declares: freq.unit.s_adj.na_item.geo
eurostat_dims_ok_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,SCA,B1GQ,AT,2026-Q1,105150.1,,",
  sep = "\n"
)

## s_adj and na_item transposed: the shape of namq_10_a10_e's trap, where
## the same five-ish segments mean different things in a sibling dataflow
eurostat_dims_transposed_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,na_item,s_adj,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,B1GQ,SCA,AT,2026-Q1,105150.1,,",
  sep = "\n"
)

## One extra dimension (nace_r2) inserted: every segment after it lands on
## the wrong dimension, and the answer still looks like data
eurostat_dims_extra_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,nace_r2,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,TOTAL,SCA,B1GQ,AT,2026-Q1,105150.1,,",
  sep = "\n"
)

## Not an SDMX-CSV answer at all (no TIME_PERIOD column): then there is no
## way to tell what the key filtered on
eurostat_dims_no_time_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,OBS_VALUE,OBS_FLAG",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,SCA,B1GQ,AT,105150.1,",
  sep = "\n"
)

eurostat_dims_fault_fixture <- '<?xml version="1.0" encoding="UTF-8"?><S:Fault xmlns:S="http://schemas.xmlsoap.org/soap/envelope/"><faultcode>150</faultcode><faultstring>INVALID_QUERY_DIMENSION_VALUE</faultstring></S:Fault>'

## ---------------------------------------------------------------
## eurostat_response_dimensions()
## ---------------------------------------------------------------

test_that("eurostat_response_dimensions reads the columns between LAST UPDATE and TIME_PERIOD", {
  expect_equal(eurostat_response_dimensions(eurostat_dims_ok_fixture),
               c("freq", "unit", "s_adj", "na_item", "geo"))
})

test_that("eurostat_response_dimensions returns NULL when the answer has no TIME_PERIOD column", {
  expect_null(eurostat_response_dimensions(eurostat_dims_no_time_fixture))
  expect_null(eurostat_response_dimensions("<html><body>Service unavailable</body></html>"))
})

## ---------------------------------------------------------------
## check_eurostat_dimension_order()
## ---------------------------------------------------------------

test_that("check_eurostat_dimension_order passes an answer whose dimensions are the ones the key assumed", {
  expect_silent(
    dims <- check_eurostat_dimension_order(eurostat_dims_ok_fixture, "namq_10_gdp",
                                           "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp")
  )
  expect_equal(dims, c("freq", "unit", "s_adj", "na_item", "geo"))
})

test_that("check_eurostat_dimension_order stops, naming both orders, when two dimensions are transposed", {
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_transposed_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    "freq.unit.na_item.s_adj.geo",
    fixed = TRUE
  )
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_transposed_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    "freq.unit.s_adj.na_item.geo",
    fixed = TRUE
  )
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_transposed_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    "filtered on something other than what was asked for",
    fixed = TRUE
  )
})

test_that("check_eurostat_dimension_order stops when an extra dimension is inserted", {
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_extra_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    "freq.unit.nace_r2.s_adj.na_item.geo",
    fixed = TRUE
  )
})

test_that("check_eurostat_dimension_order stops when the answer has no TIME_PERIOD column", {
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_no_time_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    "not an SDMX-CSV header",
    fixed = TRUE
  )
})

test_that("check_eurostat_dimension_order stops for a dataflow with no declared order", {
  expect_error(
    check_eurostat_dimension_order(eurostat_dims_ok_fixture, "gov_10q_ggdebt",
                                   "Q.GD.S13.PC_GDP.AT", "government_debt_to_gdp"),
    "no declared key dimension order",
    fixed = TRUE
  )
})

test_that("a dimension mismatch signals a classed condition, so a tryCatch can let it through", {
  cond <- tryCatch(
    check_eurostat_dimension_order(eurostat_dims_transposed_fixture, "namq_10_gdp",
                                   "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
    error = function(e) e
  )
  expect_s3_class(cond, "eurostat_dimension_mismatch")
})

test_that("every declared dimension order is lower case and non-empty", {
  expect_true(length(eurostat_key_dimensions) > 0)
  for (dataflow in names(eurostat_key_dimensions)) {
    dims <- eurostat_key_dimensions[[dataflow]]
    expect_true(length(dims) >= 2, info = dataflow)
    expect_equal(dims, tolower(dims), info = dataflow)
    expect_true("geo" %in% dims, info = dataflow)
  }
})

## ---------------------------------------------------------------
## fetch_eurostat_text()
## ---------------------------------------------------------------

test_that("fetch_eurostat_text returns the body unchanged when the dimensions match", {
  with_mock_fetch_text(const_fetch_text(eurostat_dims_ok_fixture), {
    txt <- fetch_eurostat_text("https://example.invalid/x", "namq_10_gdp",
                               "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp")
  })
  expect_identical(txt, eurostat_dims_ok_fixture)
})

test_that("fetch_eurostat_text leaves a failed request and a SOAP fault to the callers' warnings", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_null(fetch_eurostat_text("https://example.invalid/x", "namq_10_gdp",
                                    "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"))
  })
  with_mock_fetch_text(const_fetch_text(eurostat_dims_fault_fixture), {
    txt <- fetch_eurostat_text("https://example.invalid/x", "namq_10_gdp",
                               "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp")
  })
  expect_identical(txt, eurostat_dims_fault_fixture)
})

test_that("fetch_eurostat_text stops on a transposed answer", {
  with_mock_fetch_text(const_fetch_text(eurostat_dims_transposed_fixture), {
    expect_error(
      fetch_eurostat_text("https://example.invalid/x", "namq_10_gdp",
                          "Q.CLV20_MEUR.SCA.B1GQ.AT", "real_gdp"),
      class = "eurostat_dimension_mismatch"
    )
  })
})

## ---------------------------------------------------------------
## The guard reaches the fetchers, including the three that otherwise
## turn an unexpected error into a warning and NULL
## ---------------------------------------------------------------

test_that("fetch_eurostat_series stops rather than warning when the dimensions don't match", {
  with_mock_fetch_text(const_fetch_text(eurostat_dims_transposed_fixture), {
    expect_error(fetch_eurostat_series("AT", "B1GQ", "real_gdp"),
                 class = "eurostat_dimension_mismatch")
  })
})

test_that("fetch_eurostat_hours stops rather than warning when the dimensions don't match", {
  ## namq_10_a10_e declares six dimensions; the five-dimension answer of
  ## namq_10_gdp means the key filtered on the wrong ones.
  with_mock_fetch_text(const_fetch_text(eurostat_dims_ok_fixture), {
    expect_error(fetch_eurostat_hours("AUT"), class = "eurostat_dimension_mismatch")
  })
})

test_that("fetch_eurostat_population stops rather than warning when the dimensions don't match", {
  with_mock_fetch_text(const_fetch_text(eurostat_dims_transposed_fixture), {
    expect_error(fetch_eurostat_population("AUT"), class = "eurostat_dimension_mismatch")
  })
})

test_that("fetch_eurostat_sts_key stops when the answer's dimensions don't match its key", {
  with_mock_fetch_text(const_fetch_text(eurostat_dims_ok_fixture), {
    expect_error(
      fetch_eurostat_sts_key("sts_inpr_m", "M.PRD.B-D.SCA.I21.AT", "industrial_production",
                             "2020-M01", "M"),
      class = "eurostat_dimension_mismatch"
    )
  })
})

test_that("every Eurostat dataflow the fetchers request has a declared dimension order", {
  ## The dataflow ids built in R/ -- if one of these is ever renamed, the
  ## guard would stop the build with "no declared key dimension order",
  ## which this test catches first.
  requested <- c(
    eurostat_dataflow,
    eurostat_disposable_income_dataflow,
    eurostat_hicp_dataflow,
    eurostat_ulc_dataflow,
    eurostat_gov_dataflow,
    eurostat_hours_dataflow,
    eurostat_population_dataflow,
    eurostat_chdd_dataflow,
    sts_dataflow("sts_inpr", "M"), sts_dataflow("sts_inpr", "Q"),
    sts_dataflow("sts_trtu", "M"), sts_dataflow("sts_trtu", "Q"),
    sts_dataflow("sts_copi", "M"), sts_dataflow("sts_copi", "Q"),
    "une_rt_m"
  )
  missing <- setdiff(tolower(requested), names(eurostat_key_dimensions))
  expect_equal(missing, character(0))
})
