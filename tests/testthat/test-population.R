## R/population.R -- total population, quarterly.
##
## What is worth pinning down: the Eurostat key is built in namq_10_gdp's
## dimension order (not namq_10_a10_e's, which a copy of the hours-worked
## fetcher would silently inherit), the route taken depends on the country,
## and a country with no quarterly source resolves to NULL rather than to
## anything interpolated.

eurostat_pop_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_PE(1.0),25/09/26 23:00:00,Q,THS_PER,SCA,POP_NC,AT,1995-Q1,7946.14,,",
  "ESTAT:NAMQ_10_PE(1.0),25/09/26 23:00:00,Q,THS_PER,SCA,POP_NC,AT,1995-Q2,7946.99,,",
  "ESTAT:NAMQ_10_PE(1.0),25/09/26 23:00:00,Q,THS_PER,SCA,POP_NC,AT,1995-Q3,7948.71,,",
  sep = "\n"
)

popthm_fixture <- paste(
  "observation_date,POPTHM",
  "1959-10-01,175000",       # before the requested start, must be clipped
  "1960-01-01,180000",
  "1960-02-01,180300",
  "1960-03-01,180600",
  "1960-04-01,181000",
  sep = "\n"
)

test_that("an EU member resolves through Eurostat with the right key", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); eurostat_pop_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_population("AUT", start_period = "1995-Q1")
  })

  expect_equal(names(out), c("date", "population"))
  expect_equal(out$date, as.Date(c("1995-01-01", "1995-04-01", "1995-07-01")))
  expect_equal(out$population[1], 7946.14)
  expect_length(seen, 1)
  expect_match(seen, "/namq_10_pe/Q.THS_PER.SCA.POP_NC.AT?", fixed = TRUE)
  expect_identical(attr(out, "provider"), "EUROSTAT_POP")
  expect_identical(attr(out, "source_col"), "namq_10_pe:Q.THS_PER.SCA.POP_NC.AT")
})

test_that("the United States resolves through FRED POPTHM, averaged within the quarter", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); popthm_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_population("USA", start_period = "1960-Q1")
  })

  expect_true(all(grepl("id=POPTHM", seen, fixed = TRUE)))
  expect_false(any(grepl("eurostat", seen)))
  expect_equal(out$date, as.Date(c("1960-01-01", "1960-04-01")))
  expect_equal(out$population[1], mean(c(180000, 180300, 180600)))
  expect_identical(attr(out, "provider"), "FRED")
  expect_identical(attr(out, "source_col"), "POPTHM")
})

test_that("a country with no quarterly source is NULL and makes no request", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); popthm_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_population("JPN")
  })

  expect_null(out)
  expect_length(seen, 0)
})

test_that("a failed Eurostat request warns and returns NULL", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_population("AUT"), "Eurostat population fetch failed")
  })
  expect_null(out)
})

test_that("the concept is registered as a quarterly-only level", {
  row <- concept_dictionary[concept_dictionary$label == "population", ]
  expect_equal(nrow(row), 1L)
  expect_identical(row$plausibility_category, "level")
  expect_false(row$available_monthly)
})
