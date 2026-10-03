## The derivation of the quarterly and mixed-frequency panels from one
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

test_that("to_mixed puts quarterly values in the first month of their quarter and nowhere else", {
  quarterly <- tibble::tibble(date = as.Date(c("2026-01-01", "2026-04-01")), gdp = c(100, 101))
  mixed <- to_mixed(toy_monthly, quarterly, c("rate", "flow", "gdp"))
  expect_equal(names(mixed), c("date", "rate", "flow", "gdp"))
  expect_equal(mixed$rate, toy_monthly$rate)
  expect_equal(mixed$gdp[mixed$date == as.Date("2026-04-01")], 101)
  expect_true(all(is.na(mixed$gdp[!format(mixed$date, "%m") %in% c("01", "04")])))
})

test_that("to_mixed fills unresolved concepts with NA rather than dropping them", {
  mixed <- to_mixed(toy_monthly, tibble::tibble(date = as.Date(character(0))),
                    c("rate", "flow", "never_resolved"))
  expect_true("never_resolved" %in% names(mixed))
  expect_true(all(is.na(mixed$never_resolved)))
})

test_that("series_metadata has one row per concept with codes, source and span", {
  panel <- tibble::tibble(date = as.Date(c("2026-01-01", "2026-02-01")),
                          mortgage_new_lending = c(1500, 1600))
  src <- list(mortgage_new_lending = list(provider = "ECB_MIR", key = "A2C.B.A.2250.EUR.P"))
  md <- series_metadata(panel, src)
  expect_equal(nrow(md), nrow(concept_dictionary))
  row <- md[md$label == "mortgage_new_lending", ]
  expect_equal(row$frequency, "M")
  expect_equal(row$aggregation, "sum")
  expect_equal(row$provider, "ECB_MIR")
  expect_equal(c(row$first, row$last, row$n_obs), c("2026-M01", "2026-M02", "2"))
  expect_true(is.na(md$provider[md$label == "real_gdp"]))
})
