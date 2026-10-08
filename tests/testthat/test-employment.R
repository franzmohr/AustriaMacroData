## R/employment.R -- persons employed, quarterly.
##
## The same routes as population (R/population.R, whose Eurostat fetch it
## shares): what is pinned down here is that the shared fetch asks for
## EMP_DC rather than POP_NC, that the USA goes to PAYEMS, and that a
## country with no quarterly source resolves to NULL.

eurostat_emp_fixture <- paste(
  "DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS",
  "ESTAT:NAMQ_10_PE(1.0),07/10/26 23:00:00,Q,THS_PER,SCA,EMP_DC,AT,1995-Q1,3573.99,,",
  "ESTAT:NAMQ_10_PE(1.0),07/10/26 23:00:00,Q,THS_PER,SCA,EMP_DC,AT,1995-Q2,3571.12,,",
  sep = "\n"
)

payems_fixture <- paste(
  "observation_date,PAYEMS",
  "1959-10-01,53000",       # before the requested start, must be clipped
  "1960-01-01,54000",
  "1960-02-01,54300",
  "1960-03-01,54600",
  "1960-04-01,54500",
  sep = "\n"
)

test_that("an EU member resolves through Eurostat EMP_DC", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); eurostat_emp_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_employment("AUT", start_period = "1995-Q1")
  })

  expect_equal(names(out), c("date", "employment"))
  expect_equal(out$date, as.Date(c("1995-01-01", "1995-04-01")))
  expect_equal(out$employment[1], 3573.99)
  expect_length(seen, 1)
  expect_match(seen, "/namq_10_pe/Q.THS_PER.SCA.EMP_DC.AT?", fixed = TRUE)
  expect_identical(attr(out, "provider"), "EUROSTAT_EMP")
  expect_identical(attr(out, "source_col"), "namq_10_pe:Q.THS_PER.SCA.EMP_DC.AT")
})

test_that("the United States resolves through FRED PAYEMS, averaged within the quarter", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); payems_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_employment("USA", start_period = "1960-Q1")
  })

  expect_true(all(grepl("id=PAYEMS", seen, fixed = TRUE)))
  expect_false(any(grepl("eurostat", seen)))
  expect_equal(out$date, as.Date(c("1960-01-01", "1960-04-01")))
  expect_equal(out$employment[1], mean(c(54000, 54300, 54600)))
  expect_identical(attr(out, "provider"), "FRED")
  expect_identical(attr(out, "source_col"), "PAYEMS")
})

test_that("a country with no quarterly source is NULL and makes no request", {
  seen <- character(0)
  spy <- function(url, ...) { seen <<- c(seen, url); payems_fixture }

  with_mock_fetch_text(spy, {
    out <- fetch_employment("JPN")
  })

  expect_null(out)
  expect_length(seen, 0)
})

test_that("a failed Eurostat request warns and returns NULL", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_employment("AUT"), "Eurostat employment fetch failed")
  })
  expect_null(out)
})

test_that("the concept is registered as a quarterly-only level", {
  row <- concept_dictionary[concept_dictionary$label == "employment", ]
  expect_equal(nrow(row), 1L)
  expect_identical(row$plausibility_category, "level")
  expect_false(row$available_monthly)
  expect_identical(row$fred_qd_mnemonic, "PAYEMS")
})
