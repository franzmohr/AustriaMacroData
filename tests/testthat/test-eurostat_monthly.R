## R/eurostat_monthly.R -- the monthly-only Eurostat short-term statistics,
## and the frequency argument the shared fetchers grew for the monthly panel.
##
## The keys are the whole point of this module: every one of the three
## dataflows orders its dimensions differently from namq_10_gdp, and a
## wrong order is an HTTP 400 in production and nothing at all in a test
## that only checks the parsed output. So the URL is inspected, not just
## the tibble that comes back from it.

sts_fixture <- function(dataflow, value_rows) {
  header <- "DATAFLOW,LAST UPDATE,freq,indic_bt,nace_r2,s_adj,unit,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS"
  paste(c(header, value_rows), collapse = "\n")
}

inpr_fixture <- sts_fixture("STS_INPR_M", c(
  "ESTAT:STS_INPR_M(1.0),17/09/26,M,PRD,B-D,SCA,I21,AT,2024-01,102.4,,",
  "ESTAT:STS_INPR_M(1.0),17/09/26,M,PRD,B-D,SCA,I21,AT,2024-02,101.1,,",
  "ESTAT:STS_INPR_M(1.0),17/09/26,M,PRD,B-D,SCA,I21,AT,2024-03,103.9,,"
))

une_fixture <- paste(c(
  "DATAFLOW,LAST UPDATE,freq,s_adj,age,unit,sex,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:UNE_RT_M(1.0),22/09/26,M,SA,TOTAL,PC_ACT,T,AT,2024-01,4.9,,",
  "ESTAT:UNE_RT_M(1.0),22/09/26,M,SA,TOTAL,PC_ACT,T,AT,2024-02,5.1,,"
), collapse = "\n")

capture_url <- function(text) {
  seen <- new.env(parent = emptyenv())
  seen$url <- NA_character_
  list(
    fn = function(url, ...) { seen$url <- url; text },
    seen = seen
  )
}

test_that("industrial production is fetched on the key sts_inpr_m actually wants", {
  spy <- capture_url(inpr_fixture)
  with_mock_fetch_text(spy$fn, {
    out <- fetch_eurostat_industrial_production("AUT")
  })

  # freq.indic_bt.nace_r2.s_adj.unit.geo -- NOT the namq_10_gdp order.
  expect_match(spy$seen$url, "sts_inpr_m/M.PRD.B-D.SCA.I21.AT", fixed = TRUE)
  expect_match(spy$seen$url, "startPeriod=1995-01", fixed = TRUE)

  expect_equal(names(out), c("date", "industrial_production"))
  expect_equal(out$date, as.Date(c("2024-01-01", "2024-02-01", "2024-03-01")))
  expect_equal(out$industrial_production, c(102.4, 101.1, 103.9))
  expect_identical(attr(out, "source_col"), "sts_inpr_m:M.PRD.B-D.SCA.I21.AT")
})

test_that("retail trade asks for the VOLUME of sales, not turnover", {
  spy <- capture_url(inpr_fixture)
  with_mock_fetch_text(spy$fn, fetch_eurostat_retail_sales("AUT"))

  # NETTUR is turnover in current prices and would put a price index into a
  # quantity column, so the indicator must be VOL_SLS.
  expect_match(spy$seen$url, "sts_trtu_m/M.VOL_SLS.G47.SCA.I21.AT", fixed = TRUE)
  expect_false(grepl("NETTUR", spy$seen$url, fixed = TRUE))
})

test_that("the unemployment rate uses une_rt_m's own dimension order", {
  spy <- capture_url(une_fixture)
  with_mock_fetch_text(spy$fn, {
    out <- fetch_eurostat_unemployment("AUT")
  })

  # freq.s_adj.age.unit.sex.geo -- a different order again from sts_*.
  expect_match(spy$seen$url, "une_rt_m/M.SA.TOTAL.PC_ACT.T.AT", fixed = TRUE)
  expect_equal(out$unemployment_rate, c(4.9, 5.1))
})

test_that("a start period is accepted in either form", {
  spy <- capture_url(inpr_fixture)
  with_mock_fetch_text(spy$fn, {
    fetch_eurostat_industrial_production("AUT", start_period = "2010-M04")
  })
  expect_match(spy$seen$url, "startPeriod=2010-04", fixed = TRUE)

  with_mock_fetch_text(spy$fn, {
    fetch_eurostat_industrial_production("AUT", start_period = "2010-Q2")
  })
  expect_match(spy$seen$url, "startPeriod=2010-04", fixed = TRUE)
})

test_that("non-EU countries get NULL rather than a malformed request", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; inpr_fixture }, {
    expect_null(fetch_eurostat_industrial_production("USA"))
    expect_null(fetch_eurostat_retail_sales("USA"))
    expect_null(fetch_eurostat_unemployment("USA"))
  })
  expect_false(called)
})

test_that("a SOAP fault is a failure and not an empty series", {
  fault <- '<?xml version="1.0"?><S:Fault><faultstring>INVALID_QUERY</faultstring></S:Fault>'
  with_mock_fetch_text(const_fetch_text(fault), {
    expect_warning(out <- fetch_eurostat_industrial_production("AUT"), "no observations")
  })
  expect_null(out)

  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_eurostat_unemployment("AUT"), "fetch failed")
  })
  expect_null(out)
})

test_that("the monthly FRED mirror table holds only monthly, index-valued series", {
  monthly <- other_groups[!is.na(other_groups$m_id_template), ]

  # Every monthly mnemonic carries FRED's monthly marker where its quarterly
  # twin carries "Q", so a quarterly id cannot be pasted into this column by
  # accident.
  expect_true(all(grepl("M[0-9]|MISMEI", monthly$m_id_template)))
  expect_false(any(grepl("Q[0-9]|QISMEI", monthly$m_id_template)))

  # cpi_index is deliberately absent: CPALTT01{cc2}M657N exists but the OECD
  # MEI suffix 657 is a growth rate, and splicing one onto the HICP index
  # produced a monthly cpi_index reaching -377 before this was caught. The
  # monthly panel takes the CPI from Eurostat's HICP or not at all.
  expect_false("cpi_index" %in% monthly$label)
  expect_false(any(grepl("657", monthly$m_id_template)))

  # And the concepts with no monthly publication at all stay out.
  expect_false(any(c("employment_rate", "unit_labor_cost", "house_price_real",
                     "world_uncertainty_index") %in% monthly$label))
})

test_that("the monthly concept list comes from the dictionary, not a second list", {
  monthly <- concept_dictionary$label[concept_dictionary$available_monthly]

  expect_gt(length(monthly), 20)
  expect_true(all(c("cpi_index", "industrial_production", "geopolitical_risk",
                    "oil_price", "global_activity") %in% monthly))

  # Nothing quarterly at source may claim to be monthly: a national-accounts
  # concept in this list would be interpolated somewhere or empty everywhere.
  expect_false(any(c("real_gdp", "real_household_consumption", "hours_worked",
                     "credit_to_private_nonfin_sector", "government_debt_to_gdp",
                     "unit_labor_cost", "heating_degree_days") %in% monthly))
})

test_that("the shared fetchers keep monthly dates when asked for them", {
  # fetch_geopolitical_risk() aggregates on the way out, so the frequency
  # argument is what decides whether the panel sees months or quarters. The
  # bulk file is mocked through the same cache path the module uses.
  skip_if_not_installed("writexl")

  landing <- tempfile()
  dir.create(landing)
  on.exit(unlink(landing, recursive = TRUE), add = TRUE)

  months <- seq(as.Date("2020-01-01"), as.Date("2020-12-01"), by = "month")
  writexl::write_xlsx(
    list(Sheet1 = data.frame(month = months, GPR = seq_along(months) * 10)),
    file.path(landing, "gpr_data")
  )

  monthly <- fetch_geopolitical_risk("AUT", start_period = "2020-M01",
                                     landing_dir = landing, frequency = "M")
  quarterly <- fetch_geopolitical_risk("AUT", start_period = "2020-Q1",
                                       landing_dir = landing, frequency = "Q")

  expect_equal(nrow(monthly), 12)
  expect_equal(nrow(quarterly), 4)
  expect_equal(monthly$geopolitical_risk, seq_along(months) * 10)
  expect_equal(quarterly$geopolitical_risk[1], mean(c(10, 20, 30)))
})
