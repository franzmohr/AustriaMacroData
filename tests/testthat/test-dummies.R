## Policy-event dummies (R/dummies.R). No network involved.

kimv_months <- function() {
  make_monthly_dummies("AUT", as.Date("2021-01-01"), as.Date("2026-06-01"))
}

test_that("every event has a known type, a start, and an end no earlier than its start", {
  expect_true(all(policy_events$type %in% c("step", "impulse")))
  expect_false(anyNA(policy_events$start))
  ends <- policy_events$end[!is.na(policy_events$end)]
  starts <- policy_events$start[!is.na(policy_events$end)]
  expect_true(all(ends >= starts))
  expect_equal(anyDuplicated(policy_events$name), 0L)
  expect_false(anyNA(policy_events$source))
})

test_that("the KIM-V step is 1 from August 2022 through June 2025 and 0 otherwise", {
  m <- kimv_months()
  on <- m$date[m$kimv == 1]
  expect_equal(min(on), as.Date("2022-08-01"))
  expect_equal(max(on), as.Date("2025-06-01"))
  expect_equal(length(on), 35)
  expect_equal(m$kimv[m$date == as.Date("2022-07-01")], 0)
  expect_equal(m$kimv[m$date == as.Date("2025-07-01")], 0)
})

test_that("an impulse is 1 in its month only", {
  m <- kimv_months()
  expect_equal(sum(m$kimv_announcement), 1)
  expect_equal(m$date[m$kimv_announcement == 1], as.Date("2021-12-01"))
})

test_that("a quarterly step is the share of the quarter's months in force", {
  q <- make_quarterly_dummies(kimv_months())
  expect_equal(q$kimv[q$date == as.Date("2022-07-01")], 2 / 3)
  expect_equal(q$kimv[q$date == as.Date("2022-10-01")], 1)
  expect_equal(q$kimv[q$date == as.Date("2025-07-01")], 0)
  expect_equal(q$kimv_announcement[q$date == as.Date("2021-10-01")], 1)
})

test_that("a country without events gets no dummies rather than an empty file", {
  expect_null(make_monthly_dummies("USA", as.Date("2020-01-01"), as.Date("2020-12-01")))
  expect_null(make_quarterly_dummies(NULL))
})
