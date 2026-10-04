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
