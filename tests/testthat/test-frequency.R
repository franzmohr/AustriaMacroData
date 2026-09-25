## R/frequency.R -- the switch between a quarterly and a monthly panel.
##
## What is worth testing here is not that a mean is a mean, but the three
## things that would silently produce a wrong panel: a frequency argument
## that falls through instead of being refused, a period string read at the
## wrong frequency, and a daily series that is averaged into the wrong bucket.

test_that("a frequency that is not Q or M is refused where it is written", {
  expect_error(check_frequency("W"), "must be one of")
  expect_error(check_frequency("monthly"), "'monthly'")
  expect_error(check_frequency(NA_character_), "must be one of")
  expect_error(check_frequency(c("Q", "M")), "must be one of")
  expect_error(check_frequency(12), "must be one of")

  expect_identical(check_frequency("Q"), "Q")
  expect_identical(check_frequency("M"), "M")
})

test_that("period strings are read at both frequencies and nowhere in between", {
  expect_equal(period_to_date("1995-Q1"), as.Date("1995-01-01"))
  expect_equal(period_to_date("1995-Q4"), as.Date("1995-10-01"))
  expect_equal(period_to_date("2020-M07"), as.Date("2020-07-01"))
  expect_equal(period_to_date("2020-M01"), as.Date("2020-01-01"))
  expect_equal(period_to_date("2020-M12"), as.Date("2020-12-01"))

  # Vectorised, and mixing the two forms is fine -- the form is read per
  # element rather than guessed once for the vector.
  expect_equal(period_to_date(c("1995-Q1", "2020-M07")),
               as.Date(c("1995-01-01", "2020-07-01")))

  # A month that does not exist, a quarter that does not exist, and two
  # shapes that are nearly right, all come back NA rather than as a
  # plausible-looking wrong date.
  expect_true(all(is.na(period_to_date(c("2020-M13", "2020-M00", "1995-Q5",
                                         "2020-07", "2020-M7", "rubbish")))))
})

test_that("a date becomes a period string at the frequency that was asked for", {
  expect_equal(date_to_period(as.Date("2020-07-15")), "2020-Q3")
  expect_equal(date_to_period(as.Date("2020-07-15"), frequency = "M"), "2020-M07")
  expect_equal(date_to_period(as.Date("2020-01-01"), frequency = "M"), "2020-M01")

  # Round trip, both ways.
  expect_equal(period_to_date(date_to_period(as.Date("2020-07-01"), "M")),
               as.Date("2020-07-01"))
  expect_equal(as_period("1995-Q2", "M"), "1995-M04")
  expect_equal(as_period("2020-M08", "Q"), "2020-Q3")
  expect_equal(as_period("2020-M08", "M"), "2020-M08")
  expect_error(as_period("nonsense", "M"), "neither")
})

test_that("a daily series lands in the right bucket at each frequency", {
  daily <- data.frame(
    date = as.Date(c("2020-01-05", "2020-01-20", "2020-02-03", "2020-04-10")),
    x = c(1, 3, 10, 100)
  )

  monthly <- aggregate_to(daily, "x", "M")
  expect_equal(monthly$date, as.Date(c("2020-01-01", "2020-02-01", "2020-04-01")))
  expect_equal(monthly$x, c(2, 10, 100))

  quarterly <- aggregate_to(daily, "x", "Q")
  expect_equal(quarterly$date, as.Date(c("2020-01-01", "2020-04-01")))
  # The quarterly mean is over observations, not over the monthly means.
  expect_equal(quarterly$x, c(mean(c(1, 3, 10)), 100))

  expect_error(aggregate_to(daily, "x", "D"), "must be one of")
})

test_that("an already-monthly series is unchanged but for its ordering", {
  out_of_order <- data.frame(
    date = as.Date(c("2020-03-01", "2020-01-01", "2020-02-01")),
    x = c(3, 1, 2)
  )
  out <- aggregate_to(out_of_order, "x", "M")
  expect_equal(out$date, as.Date(c("2020-01-01", "2020-02-01", "2020-03-01")))
  expect_equal(out$x, c(1, 2, 3))
})

test_that("the default start period is written in the form its frequency uses", {
  expect_equal(default_start_period("Q"), "1995-Q1")
  expect_equal(default_start_period("M"), "1995-M01")
  expect_equal(default_start_period("M", year = 1960), "1960-M01")
  # And whatever it returns must be readable by the function that reads it.
  expect_equal(period_to_date(default_start_period("M", 1960)), as.Date("1960-01-01"))
})

test_that("splice_prefer can key on a date column and rescales to the primary", {
  primary <- data.frame(date = as.Date(c("2000-01-01", "2000-02-01")), x = c(100, 102))
  secondary <- data.frame(date = as.Date(c("1999-12-01", "2000-01-01", "2000-02-01")),
                          x = c(48, 50, 51))

  out <- splice_prefer(primary, secondary, by = "date")
  expect_equal(out$date, as.Date(c("1999-12-01", "2000-01-01", "2000-02-01")))
  # The secondary is doubled to meet the primary at the first overlap, so its
  # own dynamics survive and its level does not.
  expect_equal(out$x, c(96, 100, 102))

  # The default key is still "period", so nothing that called it before moves.
  quarterly <- splice_prefer(
    data.frame(period = c("2000-Q1", "2000-Q2"), x = c(100, 102)),
    data.frame(period = c("1999-Q4", "2000-Q1"), x = c(48, 50))
  )
  expect_equal(quarterly$x, c(96, 100, 102))
})
