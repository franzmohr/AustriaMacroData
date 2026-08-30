## Fixture mirrors the real shape confirmed live against
## ec.europa.eu/eurostat's SDMX 2.1 API on 2026-08-30
## (namq_10_gdp, format=SDMX-CSV): TIME_PERIOD/OBS_VALUE columns, same
## names as OECD's, parsed by the same parse_time_value_csv().
eurostat_gdp_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,SCA,B1GQ,AT,2026-Q1,105150.1,,",
  "ESTAT:NAMQ_10_GDP(1.0),28/08/26 23:00:00,Q,CLV20_MEUR,SCA,B1GQ,AT,2026-Q2,105159.0,,",
  sep = "\n"
)

eurostat_fault_fixture <- '<?xml version="1.0" encoding="UTF-8"?><S:Fault xmlns:S="http://schemas.xmlsoap.org/soap/envelope/"><faultcode>150</faultcode><faultstring>INVALID_QUERY_DIMENSION_VALUE: Query is invalid as per its structure&apos;s definition.</faultstring></S:Fault>'

test_that("fetch_eurostat_series parses a successful response into period/value", {
  with_mock_fetch_text(const_fetch_text(eurostat_gdp_fixture), {
    out <- fetch_eurostat_series("AT", "B1GQ", "real_gdp")
  })
  expect_equal(names(out), c("period", "real_gdp"))
  expect_equal(out$real_gdp, c(105150.1, 105159.0))
})

test_that("fetch_eurostat_series warns and returns NULL on a SOAP Fault (e.g. NA_ITEM not valid for this dataflow)", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_series("AT", "B6G", "real_household_disposable_income"),
                    "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_series warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_series("AT", "B1GQ", "real_gdp"), "Eurostat fetch failed")
  })
  expect_null(out)
})

test_that("fetch_eurostat_series builds the confirmed 5-segment key order (FREQ.UNIT.S_ADJ.NA_ITEM.GEO)", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_gdp_fixture }, {
    fetch_eurostat_series("AT", "B1GQ", "real_gdp")
  })
  expect_true(grepl("namq_10_gdp/Q.CLV20_MEUR.SCA.B1GQ.AT", captured_url, fixed = TRUE))
})

test_that("fetch_eurostat_anchors returns NULL for a non-EU country without any network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; eurostat_gdp_fixture }, {
    out <- fetch_eurostat_anchors("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_eurostat_anchors merges multiple concepts into one wide tibble by period", {
  with_mock_fetch_text(const_fetch_text(eurostat_gdp_fixture), {
    out <- fetch_eurostat_anchors("AUT", start_period = "2026-Q1")
  })
  expect_true("period" %in% names(out))
  expect_true("real_gdp" %in% names(out))
})

test_that("fetch_eurostat_anchors honors a `labels` filter, mirroring fetch_oecd_anchors", {
  requested <- character()
  with_mock_fetch_text(function(url, ...) {
    requested <<- c(requested, url)
    eurostat_gdp_fixture
  }, {
    out <- fetch_eurostat_anchors("AUT", labels = "real_gdp")
  })
  expect_equal(length(requested), 1)
  expect_true(grepl("B1GQ", requested[1]))
})

test_that("fetch_eurostat_anchors never attempts real_household_disposable_income (not valid for this dataflow)", {
  out <- eurostat_anchor_concepts$label
  expect_false("real_household_disposable_income" %in% out)
})
