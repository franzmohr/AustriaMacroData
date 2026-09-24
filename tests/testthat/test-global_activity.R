## R/global_activity.R -- Kilian's index of global real economic activity.
##
## The thing worth testing here is not the arithmetic of the quarterly
## average, which R/fred_mirror.R's own tests already cover, but the two
## properties that make this concept different from every other one in the
## panel: it is signed, so nothing may quietly drop or clamp its negative
## observations, and it is a world series, so the `country3` argument has
## to be accepted and ignored rather than reaching the URL.

igrea_fixture <- paste(
  "observation_date,IGREA",
  "1959-10-01,10.0",        # before the default start, must be clipped
  "1960-01-01,-12.2",
  "1960-02-01,-8.9",
  "1960-03-01,-10.1",
  "1960-04-01,60.0",
  "1960-05-01,-60.0",
  "1960-06-01,30.0",
  sep = "\n"
)

test_that("the quarterly index keeps its sign and its negative quarters", {
  with_mock_fetch_text(const_fetch_text(igrea_fixture), {
    out <- fetch_global_activity("AUT")
  })

  expect_equal(names(out), c("date", "global_activity"))
  # 1960-Q1 averages three negative months and must stay negative; a
  # positivity rule borrowed from the "level" concepts would destroy it.
  expect_equal(round(out$global_activity[1], 4), round(mean(c(-12.2, -8.9, -10.1)), 4))
  expect_lt(out$global_activity[1], 0)
  # 1960-Q2 averages a large positive and a large negative month, so the
  # quarter is near zero even though neither month is.
  expect_equal(round(out$global_activity[2], 4), 10)
})

test_that("observations before start_period are clipped, as for the oil price", {
  with_mock_fetch_text(const_fetch_text(igrea_fixture), {
    out <- fetch_global_activity("AUT", start_period = "1960-Q1")
    later <- fetch_global_activity("AUT", start_period = "1960-Q2")
  })

  expect_equal(min(out$date), as.Date("1960-01-01"))
  expect_equal(nrow(later), 1L)
})

test_that("the country argument is accepted and never reaches the request", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); igrea_fixture }

  with_mock_fetch_text(spy, {
    austria <- fetch_global_activity("AUT")
    germany <- fetch_global_activity("DEU")
    unnamed <- fetch_global_activity()
  })

  expect_identical(austria, germany)
  expect_identical(austria, unnamed)
  expect_true(all(grepl("id=IGREA", seen, fixed = TRUE)))
  expect_false(any(grepl("AUT|DEU", seen)))
  expect_identical(attr(austria, "source_col"), "IGREA")
})

test_that("a failed fetch warns and returns NULL rather than a partial column", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_global_activity("AUT"), "FRED fetch failed")
  })
  expect_null(out)
})

test_that("the concept is registered with a category that allows negatives", {
  expect_true("global_activity" %in% concept_dictionary$label)
  category <- plausibility_category("global_activity")
  expect_identical(category, "deviation")
  expect_lt(plausibility_bounds[[category]][1], 0)
})
