## The derivation of the quarterly panel and the metadata from one
## fetch at native frequency (R/panel_derive.R). No network involved.

toy_dictionary <- tibble::tibble(
  label = c("rate", "flow"),
  aggregation = c("mean", "sum"),
  frequency = c("M", "M")
)

toy_monthly <- tibble::tibble(
  date = seq(as.Date("2026-01-01"), as.Date("2026-08-01"), by = "month"),
  rate = c(1, 2, 3, 4, 5, 6, 7, 8),
  flow = c(10, 20, 30, 40, 50, 60, 70, 80)
)

test_that("to_quarterly averages a stock and sums a flow, each by its own rule", {
  q <- to_quarterly(toy_monthly, dictionary = toy_dictionary)
  expect_equal(q$date[1:2], as.Date(c("2026-01-01", "2026-04-01")))
  expect_equal(q$rate[1:2], c(2, 5))
  expect_equal(q$flow[1:2], c(60, 150))
})

test_that("to_quarterly keeps the current quarter's average but drops its partial sum", {
  q <- to_quarterly(toy_monthly, dictionary = toy_dictionary)
  q3 <- q[q$date == as.Date("2026-07-01"), ]
  ## July and August only: the average of two months is an estimate of
  ## the quarter, the sum of two months is two thirds of it.
  expect_equal(q3$rate, 7.5)
  expect_true(is.na(q3$flow))
})

test_that("to_quarterly ignores months a concept was not observed in", {
  gappy <- toy_monthly
  gappy$rate[1] <- NA
  q <- to_quarterly(gappy, dictionary = toy_dictionary)
  expect_equal(q$rate[1], 2.5)
  expect_false(any(is.nan(q$rate)))
})

test_that("series_metadata has one row per concept with codes, source and span", {
  monthly <- tibble::tibble(date = as.Date(c("2026-01-01", "2026-02-01")),
                            mortgage_new_lending = c(1500, 1600))
  quarterly <- tibble::tibble(date = as.Date(c("2025-10-01", "2026-01-01", "2026-04-01")),
                              mortgage_new_lending = c(4400, 4600, NA),
                              real_gdp = c(100, 101, 102))
  src <- list(mortgage_new_lending = list(provider = "ECB_MIR", key = "A2C.B.A.2250.EUR.P"))
  md <- series_metadata(list(M = monthly, Q = quarterly), src)
  expect_equal(nrow(md), nrow(concept_dictionary))
  row <- md[md$label == "mortgage_new_lending", ]
  expect_equal(row$frequency, "M")
  expect_equal(row$aggregation, "sum")
  expect_equal(row$provider, "ECB_MIR")
  expect_equal(c(row$first, row$last, row$n_obs), c("2026-M01", "2026-M02", "2"))
  expect_true(is.na(md$provider[md$label == "real_gdp"]))
})

test_that("series_metadata reads a quarterly concept's span from the quarterly panel", {
  quarterly <- tibble::tibble(date = as.Date(c("2025-10-01", "2026-01-01")), real_gdp = c(100, 101))
  md <- series_metadata(list(M = toy_monthly, Q = quarterly), list())
  row <- md[md$label == "real_gdp", ]
  expect_equal(row$frequency, "Q")
  expect_equal(c(row$first, row$last, row$n_obs), c("2025-Q4", "2026-Q1", "2"))
})

test_that("series_metadata reads a monthly concept's span quarterly where the country's override says Q", {
  monthly <- tibble::tibble(date = as.Date("2026-01-01"), construction_cost_index = NA_real_)
  quarterly <- tibble::tibble(date = as.Date(c("2026-01-01", "2026-04-01")),
                              construction_cost_index = c(130, 131))
  md <- series_metadata(list(M = monthly, Q = quarterly), list(),
                        frequency = c(construction_cost_index = "Q"))
  row <- md[md$label == "construction_cost_index", ]
  expect_equal(c(row$frequency, row$first, row$last, row$n_obs), c("Q", "2026-Q1", "2026-Q2", "2"))
  expect_equal(md$frequency[md$label == "industrial_production"], "M")
})

test_that("series_metadata gives each concept the unit of the source that resolved for the country", {
  quarterly <- tibble::tibble(date = as.Date(c("2025-10-01", "2026-01-01")),
                              real_gdp = c(24e6, 24.1e6), real_household_disposable_income = c(4.7e6, 4.8e6),
                              unit_labor_cost = c(0.4, 1.7), fx_rate_to_usd = c(0.9, 0.92))
  oecd <- list(real_gdp = list(provider = "OECD_QNA", key = "S1.B1GQ"),
               real_household_disposable_income = list(provider = "OECD_QNA", key = "DF_QSA:..."),
               unit_labor_cost = list(provider = "FRED_MIRROR", key = "ULQEUL01USQ657S"))
  usa <- series_metadata(list(M = toy_monthly, Q = quarterly), oecd, country = "USA")
  unit <- function(md, lbl) md$unit[md$label == lbl]
  expect_equal(unit(usa, "real_gdp"), "USD mn, chain-linked volume (2020), seasonally adjusted annual rate")
  expect_equal(unit(usa, "real_household_disposable_income"), "USD mn at 2020 prices, quarterly level")
  expect_equal(unit(usa, "unit_labor_cost"), "% change on previous quarter")
  expect_false(any(grepl("EUR", usa$unit[usa$label %in% names(oecd)])))

  ## The same OECD source for a euro-area member is in euro, still annualised
  deu <- series_metadata(list(M = toy_monthly, Q = quarterly), oecd, country = "DEU")
  expect_equal(unit(deu, "real_gdp"), "EUR mn, chain-linked volume (2020), seasonally adjusted annual rate")

  ## Eurostat is the dictionary's own unit; a provider with no row keeps it
  eurostat <- list(real_gdp = list(provider = "EUROSTAT", key = "namq_10_gdp:B1GQ"),
                   unit_labor_cost = list(provider = "EUROSTAT_ULC", key = "namq_10_lp_ulc:..."),
                   fx_rate_to_usd = list(provider = "FRED_MIRROR", key = "CCUSMA02DEM618N"))
  aut <- series_metadata(list(M = toy_monthly, Q = quarterly), eurostat, country = "AUT")
  expect_equal(unit(aut, "real_gdp"), concept_dictionary$unit[concept_dictionary$label == "real_gdp"])
  expect_equal(unit(aut, "unit_labor_cost"), "index 2010=100")
  expect_equal(unit(aut, "fx_rate_to_usd"), "EUR per USD")

  ## A unit the fetcher recorded wins; an unknown country keeps the placeholder readable
  expect_equal(source_unit("real_gdp", list(provider = "OECD_QNA", unit = "custom"), "USA"), "custom")
  expect_equal(source_unit("real_gdp", list(provider = "OECD_QNA"), "XYZ"),
               "national currency mn, chain-linked volume (2020), seasonally adjusted annual rate")
  expect_equal(source_unit("real_gdp", NULL, "USA"),
               concept_dictionary$unit[concept_dictionary$label == "real_gdp"])
})

test_that("every concept_source_units row names a dictionary concept, once per provider", {
  expect_true(all(concept_source_units$label %in% concept_dictionary$label))
  expect_false(anyDuplicated(concept_source_units[, c("label", "provider")]) > 0)
})
