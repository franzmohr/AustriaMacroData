## R/eurostat_sts.R -- Eurostat's short-term statistics at both frequencies,
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

test_that("the quarterly siblings use the same dimension order with a Q", {
  quarterly <- paste(c(
    "DATAFLOW,LAST UPDATE,freq,indic_bt,nace_r2,s_adj,unit,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
    "ESTAT:STS_INPR_Q(1.0),17/09/26,Q,PRD,B-D,SCA,I21,AT,2024-Q1,102.4,,",
    "ESTAT:STS_INPR_Q(1.0),17/09/26,Q,PRD,B-D,SCA,I21,AT,2024-Q2,101.1,,"
  ), collapse = "
")

  spy <- capture_url(quarterly)
  with_mock_fetch_text(spy$fn, {
    out <- fetch_eurostat_industrial_production("AUT", start_period = "1995-Q1",
                                                frequency = "Q")
  })

  expect_match(spy$seen$url, "sts_inpr_q/Q.PRD.B-D.SCA.I21.AT", fixed = TRUE)
  expect_match(spy$seen$url, "startPeriod=1995-Q1", fixed = TRUE)

  # Eurostat writes a quarterly period as "2024-Q1" and a monthly one as
  # "2024-01"; only the first is what period_to_date() reads, so the two
  # are converted by different branches and both are checked.
  expect_equal(out$date, as.Date(c("2024-01-01", "2024-04-01")))
  expect_equal(out$industrial_production, c(102.4, 101.1))

  spy <- capture_url(quarterly)
  with_mock_fetch_text(spy$fn, {
    fetch_eurostat_retail_sales("AUT", start_period = "1995-Q1", frequency = "Q")
  })
  expect_match(spy$seen$url, "sts_trtu_q/Q.VOL_SLS.G47.SCA.I21.AT", fixed = TRUE)
})

test_that("the unemployment rate refuses a quarterly request rather than 400ing", {
  # une_rt_q exists as a dataflow but not with this key -- confirmed live, it
  # returns a SOAP fault. Refusing here says so; letting it through would
  # produce a warning about a missing key and a silent NA column.
  expect_error(fetch_eurostat_unemployment("AUT", frequency = "Q"),
               "published monthly only")
})

test_that("a national CPI index is an index, and only for a country on the list", {
  fixture <- paste(c("observation_date,CPIAUCSL",
                     "2020-01-01,100.0", "2020-02-01,101.0", "2020-03-01,102.0",
                     "2020-04-01,104.0"), collapse = "
")

  with_mock_fetch_text(const_fetch_text(fixture), {
    monthly <- fetch_national_cpi_index("USA", start_period = "2020-M01", frequency = "M")
    quarterly <- fetch_national_cpi_index("USA", start_period = "2020-Q1", frequency = "Q")
    # A country with no verified national index resolves to NULL, not to
    # whatever the last country fetched.
    expect_null(fetch_national_cpi_index("AUT"))
    expect_null(fetch_national_cpi_index("FRA"))
  })

  expect_equal(monthly$cpi_index, c(100, 101, 102, 104))
  expect_equal(quarterly$cpi_index, c(101, 104))
  expect_identical(attr(monthly, "source_col"), "CPIAUCSL")
})

test_that("no OECD MEI growth rate can reach cpi_index by either route", {
  # The 657 suffix is a period-on-period growth rate and 659 a year-on-year
  # one. Neither belongs in a column of index levels, and the mistake is
  # invisible once it is in a CSV -- a CPI growth rate and a confidence
  # balance look alike.
  expect_false(any(grepl("657|659", other_groups$m_id_template[
    !is.na(other_groups$m_id_template)])))
  expect_false("cpi_index" %in% other_groups$label[!is.na(other_groups$m_id_template)])

  # And the national table names a real index, not a template to be
  # guessed at from a country code.
  expect_true(all(c("country3", "fred_id", "note") %in% names(national_cpi_index)))
  expect_false(any(grepl("[{]cc", national_cpi_index$fred_id)))
  expect_equal(national_cpi_index$fred_id[national_cpi_index$country3 == "USA"],
               "CPIAUCSL")
})
