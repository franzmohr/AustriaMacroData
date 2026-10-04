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

test_that("real_household_disposable_income is not a namq_10_gdp row (B6G is not valid for that dataflow)", {
  expect_false("real_household_disposable_income" %in% eurostat_anchor_concepts$label)
})

## Fixtures mirror the real shapes confirmed live 2026-10-04: AT B6G for
## S14_S15 from nasq_10_nf_tr, and P31_S14_S15 from namq_10_gdp at
## current prices and at chain-linked 2020 volumes.
eurostat_b6g_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,direct,sector,na_item,s_adj,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NASQ_10_NF_TR(1.0),02/10/26 11:00:00,Q,CP_MEUR,RECV,S14_S15,B6G,SCA,AT,2025-Q4,78228,,",
  "ESTAT:NASQ_10_NF_TR(1.0),02/10/26 11:00:00,Q,CP_MEUR,RECV,S14_S15,B6G,SCA,AT,2026-Q1,79000,,",
  sep = "
"
)
eurostat_p31_cp_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CP_MEUR,SCA,P31_S14_S15,AT,2025-Q4,66000,,",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CP_MEUR,SCA,P31_S14_S15,AT,2026-Q1,66600,,",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CP_MEUR,SCA,P31_S14_S15,AT,2026-Q2,69369.4,,",
  sep = "
"
)
eurostat_p31_clv_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CLV20_MEUR,SCA,P31_S14_S15,AT,2025-Q4,52800,,",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CLV20_MEUR,SCA,P31_S14_S15,AT,2026-Q1,52800,,",
  "ESTAT:NAMQ_10_GDP(1.0),02/10/26 23:00:00,Q,CLV20_MEUR,SCA,P31_S14_S15,AT,2026-Q2,53715.7,,",
  sep = "
"
)
disposable_income_mock <- function(url, ...) {
  if (grepl("nasq_10_nf_tr", url, fixed = TRUE)) eurostat_b6g_fixture
  else if (grepl("CP_MEUR.SCA.P31_S14_S15", url, fixed = TRUE)) eurostat_p31_cp_fixture
  else eurostat_p31_clv_fixture
}

test_that("fetch_eurostat_disposable_income deflates B6G by the P31_S14_S15 implicit deflator", {
  with_mock_fetch_text(disposable_income_mock, {
    out <- fetch_eurostat_disposable_income("AT")
  })
  expect_equal(names(out), c("period", "real_household_disposable_income"))
  ## only quarters all three inputs share; 2026-Q2 has no B6G yet
  expect_equal(out$period, c("2025-Q4", "2026-Q1"))
  expect_equal(out$real_household_disposable_income,
               c(78228 / (66000 / 52800), 79000 / (66600 / 52800)))
})

test_that("fetch_eurostat_disposable_income requests the confirmed sector-accounts key", {
  requested <- character()
  with_mock_fetch_text(function(url, ...) { requested <<- c(requested, url); disposable_income_mock(url) }, {
    fetch_eurostat_disposable_income("AT")
  })
  expect_true(any(grepl("nasq_10_nf_tr/Q.CP_MEUR.RECV.S14_S15.B6G.SCA.AT", requested, fixed = TRUE)))
  expect_true(any(grepl("namq_10_gdp/Q.CP_MEUR.SCA.P31_S14_S15.AT", requested, fixed = TRUE)))
  expect_true(any(grepl("namq_10_gdp/Q.CLV20_MEUR.SCA.P31_S14_S15.AT", requested, fixed = TRUE)))
})

test_that("fetch_eurostat_disposable_income returns NULL with a warning on a SOAP Fault", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_disposable_income("AT"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_anchors resolves real_household_disposable_income when asked for it alone", {
  with_mock_fetch_text(disposable_income_mock, {
    out <- fetch_eurostat_anchors("AUT", labels = "real_household_disposable_income")
  })
  expect_equal(names(out), c("period", "real_household_disposable_income"))
})

## Fixture mirrors the real shape confirmed live against
## ec.europa.eu/eurostat's SDMX 2.1 API on 2026-10-03
## (PRC_HICP_MINR, format=SDMX-CSV, key M.I25.TOTAL.AT): monthly
## TIME_PERIOD values ("YYYY-MM"), a `coicop18` column where the frozen
## prc_hicp_midx had `coicop`, and the flash estimate for the latest month
## flagged "e" in OBS_FLAG. Same TIME_PERIOD/OBS_VALUE columns as
## namq_10_gdp, parsed by the same parse_time_value_csv().
eurostat_hicp_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,coicop18,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:PRC_HICP_MINR(1.0),02/10/26 11:00:00,M,I25,TOTAL,AT,2026-07,102.59,,",
  "ESTAT:PRC_HICP_MINR(1.0),02/10/26 11:00:00,M,I25,TOTAL,AT,2026-08,103.15,,",
  "ESTAT:PRC_HICP_MINR(1.0),02/10/26 11:00:00,M,I25,TOTAL,AT,2026-09,103.81,e,",
  sep = "
"
)

test_that("fetch_eurostat_hicp aggregates the monthly fixture to one quarterly observation", {
  with_mock_fetch_text(const_fetch_text(eurostat_hicp_fixture), {
    out <- fetch_eurostat_hicp("AUT")
  })
  expect_equal(names(out), c("date", "cpi_index"))
  expect_equal(out$date, as.Date("2026-07-01"))
  expect_equal(out$cpi_index, mean(c(102.59, 103.15, 103.81)))
})

test_that("fetch_eurostat_hicp keeps the flash-estimated latest month at monthly frequency", {
  with_mock_fetch_text(const_fetch_text(eurostat_hicp_fixture), {
    out <- fetch_eurostat_hicp("AUT", frequency = "M")
  })
  expect_equal(nrow(out), 3)
  expect_equal(max(out$date), as.Date("2026-09-01"))
  expect_equal(out$cpi_index[out$date == as.Date("2026-09-01")], 103.81)
})

test_that("fetch_eurostat_hicp returns NULL for a non-EU country without any network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; eurostat_hicp_fixture }, {
    out <- fetch_eurostat_hicp("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_eurostat_hicp builds the confirmed 4-segment key order (FREQ.UNIT.COICOP18.GEO)", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_hicp_fixture }, {
    fetch_eurostat_hicp("AUT")
  })
  expect_true(grepl("prc_hicp_minr/M.I25.TOTAL.AT", captured_url, fixed = TRUE))
})

test_that("the HICP defaults point at the current 2025=100 dataflow, not the one frozen at 2025-12", {
  ## prc_hicp_midx ends at 2025-12 in every unit, rejects I25, and its
  ## all-items code CP00 is a SOAP Fault in prc_hicp_minr (all confirmed
  ## live 2026-10-03; see R/eurostat.R). Reverting any one of the three
  ## either freezes the panels at 2025-12 again or fails every request.
  expect_equal(eurostat_hicp_dataflow, "prc_hicp_minr")
  expect_equal(eurostat_hicp_unit, "I25")
  expect_equal(eurostat_hicp_coicop, "TOTAL")
})

test_that("fetch_eurostat_hicp warns and returns NULL on a SOAP Fault (e.g. the old CP00 code)", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_hicp("AUT", coicop = "CP00"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_hicp warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_hicp("AUT"), "Eurostat HICP fetch failed")
  })
  expect_null(out)
})

## Fixture mirrors the real shape confirmed live for a non-default COICOP18
## category (core inflation, TOT_X_NRG_FOOD) on 2026-10-03.
eurostat_hicp_core_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,coicop18,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:PRC_HICP_MINR(1.0),02/10/26 11:00:00,M,I25,TOT_X_NRG_FOOD,AT,2026-09,103.34,e,",
  sep = "
"
)

test_that("fetch_eurostat_hicp's coicop parameter selects a different sub-category series", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_hicp_core_fixture }, {
    out <- fetch_eurostat_hicp("AUT", label = "core_cpi_index", coicop = "TOT_X_NRG_FOOD")
  })
  expect_true(grepl("prc_hicp_minr/M.I25.TOT_X_NRG_FOOD.AT", captured_url, fixed = TRUE))
  expect_equal(names(out), c("date", "core_cpi_index"))
  expect_equal(out$core_cpi_index, 103.34)
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

## Fixture mirrors the real shape confirmed live against
## ec.europa.eu/eurostat's SDMX 2.1 API on 2026-09-14
## (gov_10q_ggnfa, format=SDMX-CSV, key Q.PC_GDP.NSA.S13.B9+D41PAY.AT):
## both components arrive in one long response, told apart by na_item.
## The 2026-Q2 row has B9 but no D41PAY, to exercise the both-or-nothing rule.
eurostat_gov_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,sector,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:GOV_10Q_GGNFA(1.0),21/07/26 11:00:00,Q,PC_GDP,NSA,S13,B9,AT,2025-Q4,-5.1,,",
  "ESTAT:GOV_10Q_GGNFA(1.0),21/07/26 11:00:00,Q,PC_GDP,NSA,S13,B9,AT,2026-Q1,-3.9,p,",
  "ESTAT:GOV_10Q_GGNFA(1.0),21/07/26 11:00:00,Q,PC_GDP,NSA,S13,B9,AT,2026-Q2,-2.0,p,",
  "ESTAT:GOV_10Q_GGNFA(1.0),21/07/26 11:00:00,Q,PC_GDP,NSA,S13,D41PAY,AT,2025-Q4,1.6,,",
  "ESTAT:GOV_10Q_GGNFA(1.0),21/07/26 11:00:00,Q,PC_GDP,NSA,S13,D41PAY,AT,2026-Q1,1.7,p,",
  sep = "\n"
)

test_that("fetch_eurostat_primary_balance adds interest payable back to net lending, quarter by quarter", {
  with_mock_fetch_text(const_fetch_text(eurostat_gov_fixture), {
    out <- fetch_eurostat_primary_balance("AUT")
  })
  expect_equal(names(out), c("date", "government_primary_balance_to_gdp"))
  expect_equal(out$date, as.Date(c("2025-10-01", "2026-01-01")))
  expect_equal(out$government_primary_balance_to_gdp, c(-3.5, -2.2))
})

test_that("fetch_eurostat_primary_balance returns NULL for a non-EU country without any network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; eurostat_gov_fixture }, {
    out <- fetch_eurostat_primary_balance("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_eurostat_primary_balance requests both NSA components in one 6-segment key", {
  captured_url <- NULL
  with_mock_fetch_text(function(url, ...) { captured_url <<- url; eurostat_gov_fixture }, {
    fetch_eurostat_primary_balance("AUT")
  })
  expect_true(grepl("gov_10q_ggnfa/Q.PC_GDP.NSA.S13.B9+D41PAY.AT", captured_url, fixed = TRUE))
})

test_that("fetch_eurostat_primary_balance warns and returns NULL when a component is missing entirely", {
  b9_only <- paste(strsplit(eurostat_gov_fixture, "\n")[[1]][1:4], collapse = "\n")
  with_mock_fetch_text(const_fetch_text(b9_only), {
    expect_warning(out <- fetch_eurostat_primary_balance("AUT"), "both B9 and D41PAY")
  })
  expect_null(out)
})

test_that("fetch_eurostat_primary_balance warns and returns NULL on a SOAP Fault (e.g. NA_ITEM=D41)", {
  with_mock_fetch_text(const_fetch_text(eurostat_fault_fixture), {
    expect_warning(out <- fetch_eurostat_primary_balance("AUT"), "no observations")
  })
  expect_null(out)
})

test_that("fetch_eurostat_primary_balance warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_primary_balance("AUT"), "government finance fetch failed")
  })
  expect_null(out)
})
