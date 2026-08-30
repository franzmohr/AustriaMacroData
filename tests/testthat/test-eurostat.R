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

## Fixture mirrors the real shape confirmed live against
## ec.europa.eu/eurostat's SDMX 2.1 API on 2026-08-30
## (prc_hicp_midx, format=SDMX-CSV, key M.I05.CP00.AT): monthly
## TIME_PERIOD values ("YYYY-MM"), same TIME_PERIOD/OBS_VALUE columns as
## namq_10_gdp, parsed by the same parse_time_value_csv().
eurostat_hicp_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,coicop,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:PRC_HICP_MIDX(1.0),06/02/26 23:00:00,M,I05,CP00,AT,2025-10,170.19,,",
  "ESTAT:PRC_HICP_MIDX(1.0),06/02/26 23:00:00,M,I05,CP00,AT,2025-11,170.56,,",
  "ESTAT:PRC_HICP_MIDX(1.0),06/02/26 23:00:00,M,I05,CP00,AT,2025-12,171.44,,",
  sep = "\n"
)

test_that("fetch_eurostat_hicp aggregates the monthly fixture to one quarterly observation", {
  with_mock_fetch_text(const_fetch_text(eurostat_hicp_fixture), {
    out <- fetch_eurostat_hicp("AUT")
  })
  expect_equal(names(out), c("date", "cpi_index"))
  expect_equal(out$date, as.Date("2025-10-01"))
  expect_equal(out$cpi_index, mean(c(170.19, 170.56, 171.44)))
})

test_that("fetch_eurostat_hicp returns NULL for a non-EU country without any network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; eurostat_hicp_fixture }, {
    out <- fetch_eurostat_hicp("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_eurostat_hicp builds the confirmed 4-segment key order (FREQ.UNIT.COICOP.GEO)", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_hicp_fixture }, {
    fetch_eurostat_hicp("AUT")
  })
  expect_true(grepl("prc_hicp_midx/M.I05.CP00.AT", captured_url, fixed = TRUE))
})

test_that("fetch_eurostat_hicp warns and returns NULL on a SOAP Fault (e.g. wrong UNIT code)", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_hicp("AUT"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_hicp warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_hicp("AUT"), "Eurostat HICP fetch failed")
  })
  expect_null(out)
})

## Fixture mirrors the real shape confirmed live for a non-default COICOP
## category (core inflation, TOT_X_NRG_FOOD) on 2026-08-30.
eurostat_hicp_core_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,coicop,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:PRC_HICP_MIDX(1.0),06/02/26 23:00:00,M,I05,TOT_X_NRG_FOOD,AT,2025-12,165.24,,",
  sep = "\n"
)

test_that("fetch_eurostat_hicp's coicop parameter selects a different sub-category series", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_hicp_core_fixture }, {
    out <- fetch_eurostat_hicp("AUT", label = "core_cpi_index", coicop = "TOT_X_NRG_FOOD")
  })
  expect_true(grepl("prc_hicp_midx/M.I05.TOT_X_NRG_FOOD.AT", captured_url, fixed = TRUE))
  expect_equal(names(out), c("date", "core_cpi_index"))
  expect_equal(out$core_cpi_index, 165.24)
})

test_that("eurostat_hicp_subcategories lists the four confirmed-live sub-categories with their COICOP codes", {
  expect_equal(eurostat_hicp_subcategories$label,
               c("core_cpi_index", "food_price_index", "energy_price_index", "services_price_index"))
  expect_equal(eurostat_hicp_subcategories$coicop,
               c("TOT_X_NRG_FOOD", "CP01", "NRG", "SERV"))
})

## Fixture mirrors the real shape confirmed live against
## ec.europa.eu/eurostat's SDMX 2.1 API on 2026-08-30
## (namq_10_lp_ulc, format=SDMX-CSV, key Q.I10.SCA.NULC_HW.AT).
eurostat_ulc_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_LP_ULC(1.0),28/08/26 23:00:00,Q,I10,SCA,NULC_HW,AT,2025-Q4,154.879,,",
  "ESTAT:NAMQ_10_LP_ULC(1.0),28/08/26 23:00:00,Q,I10,SCA,NULC_HW,AT,2026-Q1,154.393,,",
  sep = "\n"
)

## Same shape as the real HTTP 200 confirmed live for this exact key with
## Germany substituted for Austria: a valid header, zero data rows (only
## the percentage-change NA_ITEM variants are published for DE, not the
## index-level one this module requests).
eurostat_ulc_empty_fixture <- "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS\n"

test_that("fetch_eurostat_ulc parses a successful response into date/value", {
  with_mock_fetch_text(const_fetch_text(eurostat_ulc_fixture), {
    out <- fetch_eurostat_ulc("AUT")
  })
  expect_equal(names(out), c("unit_labor_cost", "date"))
  expect_equal(out$date, as.Date(c("2025-10-01", "2026-01-01")))
  expect_equal(out$unit_labor_cost, c(154.879, 154.393))
})

test_that("fetch_eurostat_ulc returns NULL for a non-EU country without any network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; eurostat_ulc_fixture }, {
    out <- fetch_eurostat_ulc("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_eurostat_ulc builds the confirmed 5-segment key order (FREQ.UNIT.S_ADJ.NA_ITEM.GEO)", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_ulc_fixture }, {
    fetch_eurostat_ulc("AUT")
  })
  expect_true(grepl("namq_10_lp_ulc/Q.I10.SCA.NULC_HW.AT", captured_url, fixed = TRUE))
})

test_that("fetch_eurostat_ulc returns NULL (not an empty tibble) when the index-level unit isn't published for a country", {
  with_mock_fetch_text(const_fetch_text(eurostat_ulc_empty_fixture), {
    expect_warning(out <- fetch_eurostat_ulc("DEU"), "zero observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_ulc warns and returns NULL on a SOAP Fault", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_ulc("AUT"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_ulc warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_ulc("AUT"), "Eurostat ULC fetch failed")
  })
  expect_null(out)
})
