## R/inventories.R -- change in inventories, percent of GDP.
##
## The properties worth pinning down: the Eurostat request asks for the
## PC_GDP unit of P52 (not a chain-linked volume, which does not exist,
## and not P52_P53, which adds valuables), negative quarters survive
## untouched, and the concept carries a category that allows them.

eurostat_inv_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_GDP(1.0),25/09/26 23:00:00,Q,PC_GDP,SCA,P52,AT,1995-Q1,0.3,,",
  "ESTAT:NAMQ_10_GDP(1.0),25/09/26 23:00:00,Q,PC_GDP,SCA,P52,AT,1995-Q2,-1.2,,",
  sep = "\n"
)

fred_inv_fixture <- paste(
  "observation_date,A014RE1Q156NBEA",
  "1959-10-01,0.9",
  "1960-01-01,1.5",
  "1960-04-01,-0.4",
  sep = "\n"
)

test_that("an EU member asks Eurostat for P52 as a percent of GDP and keeps negatives", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); eurostat_inv_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_inventory_change("AUT", start_period = "1995-Q1")
  })

  expect_length(seen, 1)
  expect_match(seen, "/namq_10_gdp/Q.PC_GDP.SCA.P52.AT?", fixed = TRUE)
  expect_equal(names(out), c("date", "inventory_change_to_gdp"))
  expect_equal(out$inventory_change_to_gdp, c(0.3, -1.2))
  expect_identical(attr(out, "provider"), "EUROSTAT")
  expect_identical(attr(out, "source_col"), "namq_10_gdp:Q.PC_GDP.SCA.P52.AT")
})

test_that("the United States takes FRED-QD's own series, clipped to the start", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); fred_inv_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_inventory_change("USA", start_period = "1960-Q1")
  })

  expect_true(all(grepl("id=A014RE1Q156NBEA", seen, fixed = TRUE)))
  expect_equal(out$date, as.Date(c("1960-01-01", "1960-04-01")))
  expect_equal(out$inventory_change_to_gdp, c(1.5, -0.4))
  expect_identical(attr(out, "provider"), "FRED")
})

test_that("a country with no source is NULL and makes no request", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); fred_inv_fixture }
  with_mock_fetch_text(spy, out <- fetch_inventory_change("JPN"))
  expect_null(out)
  expect_length(seen, 0)
})

test_that("the concept's category admits negative values", {
  category <- plausibility_category("inventory_change_to_gdp")
  expect_identical(category, "balance")
  expect_lt(plausibility_bounds[[category]][1], 0)
  row <- concept_dictionary[concept_dictionary$label == "inventory_change_to_gdp", ]
  expect_identical(row$fred_qd_mnemonic, "A014RE1Q156NBEA")
  expect_false(row$available_monthly)
})
