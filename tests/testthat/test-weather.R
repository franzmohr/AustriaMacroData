## Helpers: build the two response shapes R/weather.R has to parse --
## Open-Meteo's JSON and Eurostat's SDMX-CSV -- so the module's real
## parsing runs against realistic bytes rather than a mocked return value.

om_json <- function(dates, temps) {
  jsonlite::toJSON(list(
    latitude = 48.19, longitude = 16.38,
    daily = list(time = format(dates, "%Y-%m-%d"), temperature_2m_mean = temps)
  ), auto_unbox = TRUE, digits = 8, na = "null")
}

om_json_const <- function(temp, from = as.Date("1990-01-01"), to = as.Date("1990-03-31")) {
  dates <- seq(from, to, by = "day")
  om_json(dates, rep(temp, length(dates)))
}

estat_csv <- function(indic, geo, periods, values) {
  paste0(
    "DATAFLOW,LAST UPDATE,freq,unit,indic_nrg,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS\n",
    paste0(sprintf("ESTAT:NRG_CHDD_M(1.0),08/05/26 11:00:00,M,NR,%s,%s,%s,%.2f,,",
                    indic, geo, periods, values), collapse = "\n"), "\n"
  )
}

test_that("days_in_month handles month lengths, including February in a leap year", {
  expect_equal(days_in_month(as.Date("2020-01-01")), 31)
  expect_equal(days_in_month(as.Date("2020-02-01")), 29)
  expect_equal(days_in_month(as.Date("2021-02-01")), 28)
  expect_equal(days_in_month(as.Date("2020-04-01")), 30)
  expect_equal(days_in_month(as.Date("2020-12-01")), 31)
  expect_equal(
    days_in_month(as.Date(c("2024-02-01", "2024-06-01"))),
    c(29, 30)
  )
})

test_that("open_meteo_url includes the point, range and daily variable", {
  url <- open_meteo_url(48.21, 16.37, as.Date("1960-01-01"), as.Date("2026-08-31"))
  expect_true(grepl("^https://archive-api\\.open-meteo\\.com/v1/archive\\?", url))
  expect_true(grepl("latitude=48\\.2100", url))
  expect_true(grepl("longitude=16\\.3700", url))
  expect_true(grepl("start_date=1960-01-01", url))
  expect_true(grepl("end_date=2026-08-31", url))
  expect_true(grepl("daily=temperature_2m_mean", url))
})

test_that("open_meteo_url keeps the sign of a western longitude", {
  ## Every US city in `weather_city_weights` has a negative longitude;
  ## a format that dropped or mangled the sign would silently sample the
  ## wrong side of the planet and still return a valid-looking series.
  expect_true(grepl("longitude=-118\\.2400", open_meteo_url(34.05, -118.24, as.Date("2020-01-01"), as.Date("2020-01-31"))))
})

test_that("parse_open_meteo_daily reads a daily block and drops null days", {
  txt <- om_json(as.Date(c("1990-01-01", "1990-01-02", "1990-01-03")), c(1.5, NA, 3.5))
  out <- parse_open_meteo_daily(txt, "test")
  expect_equal(names(out), c("date", "tmean"))
  expect_equal(nrow(out), 2)
  expect_equal(out$tmean, c(1.5, 3.5))
})

test_that("parse_open_meteo_daily returns NULL on the API's own error envelope", {
  txt <- '{"error":true,"reason":"start_date is out of allowed range"}'
  expect_warning(out <- parse_open_meteo_daily(txt, "test"), "out of allowed range")
  expect_null(out)
})

test_that("parse_open_meteo_daily returns NULL on a response with no daily block", {
  expect_warning(out <- parse_open_meteo_daily('{"latitude":48.2}', "test"), "no 'daily' block")
  expect_null(out)
})

test_that("parse_open_meteo_daily returns NULL on unparseable bytes", {
  expect_warning(out <- parse_open_meteo_daily("<html>not json</html>", "test"), "parse")
  expect_null(out)
})

test_that("degree_days_monthly applies Eurostat's reference/threshold asymmetry", {
  jan <- seq(as.Date("1990-01-01"), as.Date("1990-01-31"), by = "day")

  ## 10 C is at or below the 15 C threshold, so every day counts, each
  ## contributing (18 - 10).
  cold <- degree_days_monthly(tibble::tibble(date = jan, tmean = rep(10, 31)))
  expect_equal(cold$hdd, 8 * 31)
  expect_equal(cold$cdd, 0)

  ## 16 C is the case a single-base-temperature definition would get
  ## wrong: above the 15 C heating threshold but below the 24 C cooling
  ## threshold, so it contributes to NEITHER.
  mild <- degree_days_monthly(tibble::tibble(date = jan, tmean = rep(16, 31)))
  expect_equal(mild$hdd, 0)
  expect_equal(mild$cdd, 0)

  ## 25 C is at or above the 24 C threshold, each day contributing
  ## (25 - 21) against the 21 C reference, not against 24.
  hot <- degree_days_monthly(tibble::tibble(date = jan, tmean = rep(25, 31)))
  expect_equal(hot$hdd, 0)
  expect_equal(hot$cdd, 4 * 31)
})

test_that("degree_days_monthly drops a month it has only some days of", {
  partial <- seq(as.Date("1990-01-01"), as.Date("1990-01-20"), by = "day")
  full <- seq(as.Date("1990-02-01"), as.Date("1990-02-28"), by = "day")
  out <- degree_days_monthly(tibble::tibble(
    date = c(partial, full), tmean = rep(0, length(partial) + length(full))
  ))
  expect_equal(out$date, as.Date("1990-02-01"))
  expect_equal(nrow(out), 1)
})

test_that("fetch_open_meteo_degree_days population-weights its cities", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  ## Vienna (weight 1900) at 0 C, every other Austrian city at 10 C.
  with_mock_fetch_text(function(url, ...) {
    if (grepl("latitude=48\\.2100", url)) return(om_json_const(0))
    om_json_const(10)
  }, {
    out <- fetch_open_meteo_degree_days("AUT", as.Date("1990-01-01"), as.Date("1990-03-31"),
                                         landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
  })

  cities <- weather_city_weights[weather_city_weights$country3 == "AUT", ]
  w_vienna <- cities$weight[cities$city == "Vienna"] / sum(cities$weight)
  expected_jan <- (w_vienna * 18 + (1 - w_vienna) * 8) * 31

  expect_equal(names(out), c("date", "heating_degree_days", "cooling_degree_days"))
  expect_equal(nrow(out), 3)
  expect_equal(out$heating_degree_days[1], expected_jan)
  expect_equal(out$cooling_degree_days, c(0, 0, 0))
})

test_that("fetch_open_meteo_degree_days caches its result and makes no second round of calls", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(function(url, ...) om_json_const(5), {
    first <- fetch_open_meteo_degree_days("AUT", as.Date("1990-01-01"), as.Date("1990-03-31"),
                                          landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
  })
  expect_true(all(vapply(
    weather_city_weights$city[weather_city_weights$country3 == "AUT"],
    function(city) file.exists(degree_days_landing_path("AUT", city, as.Date("1990-01-01"),
                                                         as.Date("1990-03-31"), landing_dir)),
    logical(1)
  )))

  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; NULL }, {
    second <- fetch_open_meteo_degree_days("AUT", as.Date("1990-01-01"), as.Date("1990-03-31"),
                                            landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
  })
  expect_false(called)
  expect_equal(second$heating_degree_days, first$heating_degree_days)
})

test_that("fetch_open_meteo_degree_days refuses a country with no city set, without a network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(
      out <- fetch_open_meteo_degree_days("FRA", as.Date("1990-01-01"), as.Date("1990-03-31"),
                                           landing_dir = tempfile(), pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0),
      "No representative cities"
    )
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_open_meteo_degree_days returns NULL rather than reweighting when one city fails", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(function(url, ...) {
    if (grepl("latitude=47\\.0700", url)) return(NULL)  # Graz
    om_json_const(5)
  }, {
    expect_warning(
      out <- fetch_open_meteo_degree_days("AUT", as.Date("1990-01-01"), as.Date("1990-03-31"),
                                           landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0),
      "rather than silently reweighting"
    )
  })
  expect_null(out)
  ## The cities fetched before the failure ARE cached, so a re-run only
  ## has to retry the one that failed.
  expect_true(file.exists(degree_days_landing_path("AUT", "Vienna", as.Date("1990-01-01"),
                                                    as.Date("1990-03-31"), landing_dir)))
  expect_false(file.exists(degree_days_landing_path("AUT", "Graz", as.Date("1990-01-01"),
                                                     as.Date("1990-03-31"), landing_dir)))
})

test_that("fetch_eurostat_degree_days parses both indicators into one monthly tibble", {
  periods <- c("1990-01", "1990-02", "1990-03")
  with_mock_fetch_text(function(url, ...) {
    if (grepl("M\\.NR\\.HDD\\.AT", url)) return(estat_csv("HDD", "AT", periods, c(600, 500, 400)))
    if (grepl("M\\.NR\\.CDD\\.AT", url)) return(estat_csv("CDD", "AT", periods, c(0, 0, 1.5)))
    NULL
  }, {
    out <- fetch_eurostat_degree_days("AUT", start_period = "1990-Q1")
  })
  expect_equal(names(out), c("date", "heating_degree_days", "cooling_degree_days"))
  expect_equal(out$date, as.Date(c("1990-01-01", "1990-02-01", "1990-03-01")))
  expect_equal(out$heating_degree_days, c(600, 500, 400))
  expect_equal(out$cooling_degree_days, c(0, 0, 1.5))
})

test_that("fetch_eurostat_degree_days refuses non-EU countries without a network call", {
  called <- FALSE
  with_mock_fetch_text(function(url, ...) { called <<- TRUE; NULL }, {
    out <- fetch_eurostat_degree_days("USA")
  })
  expect_null(out)
  expect_false(called)
})

test_that("degree_day_calibration returns the ratio of sums over the overlap", {
  om <- rep(100, 30)
  es <- rep(120, 30)
  cal <- degree_day_calibration(om, es)
  expect_equal(cal$scale, 1.2)
  expect_equal(cal$n_overlap, 30)
})

test_that("degree_day_calibration declines to calibrate on too short an overlap", {
  cal <- degree_day_calibration(rep(100, 12), rep(120, 12))
  expect_true(is.na(cal$scale))
  expect_equal(cal$n_overlap, 12)
})

test_that("degree_day_calibration declines to calibrate an all-zero source series", {
  ## An all-zero cooling series (a cold country, correctly) must not
  ## produce an infinite scale factor.
  cal <- degree_day_calibration(rep(0, 40), rep(0, 40))
  expect_true(is.na(cal$scale))
})

test_that("monthly_to_quarterly_total sums months and drops an incomplete quarter", {
  monthly <- tibble::tibble(
    date = as.Date(c("1990-01-01", "1990-02-01", "1990-03-01", "1990-04-01", "1990-05-01")),
    heating_degree_days = c(600, 500, 400, 300, 200)
  )
  out <- monthly_to_quarterly_total(monthly, "heating_degree_days")
  expect_equal(out$date, as.Date("1990-01-01"))
  expect_equal(out$heating_degree_days, 1500)
})

test_that("fetch_degree_days prefers Eurostat, calibrates Open-Meteo, and reports how it did", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  ## Open-Meteo sits at a constant 5 C from 1990-01 to 1992-06, so its
  ## own monthly HDD is 13 * (days in month). Eurostat covers exactly the
  ## first 24 months (the calibration minimum) at twice that, making the
  ## expected calibration factor exactly 2.
  es_months <- seq(as.Date("1990-01-01"), as.Date("1991-12-01"), by = "month")
  es_periods <- format(es_months, "%Y-%m")
  es_hdd <- 2 * 13 * days_in_month(es_months)

  with_mock_fetch_text(function(url, ...) {
    if (grepl("archive-api", url)) {
      return(om_json_const(5, from = as.Date("1990-01-01"), to = as.Date("1992-06-30")))
    }
    if (grepl("M\\.NR\\.HDD\\.AT", url)) return(estat_csv("HDD", "AT", es_periods, es_hdd))
    if (grepl("M\\.NR\\.CDD\\.AT", url)) {
      return(estat_csv("CDD", "AT", es_periods, rep(0, length(es_periods))))
    }
    NULL
  }, {
    out <- fetch_degree_days("AUT", start_period = "1990-Q1",
                              reference_date = as.Date("1992-07-15"),
                              landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
  })

  expect_equal(names(out), c("date", "heating_degree_days", "cooling_degree_days"))
  expect_equal(range(out$date), as.Date(c("1990-01-01", "1992-04-01")))

  ## 1990-Q1 is Eurostat's own numbers, untouched.
  expect_equal(out$heating_degree_days[out$date == as.Date("1990-01-01")],
               sum(es_hdd[1:3]))

  ## 1992-Q1 is past the end of Eurostat's coverage, so it is Open-Meteo
  ## scaled by the factor measured over the overlap -- not the raw level.
  expect_equal(out$heating_degree_days[out$date == as.Date("1992-01-01")],
               2 * 13 * (31 + 29 + 31))

  sources <- attr(out, "sources")
  expect_equal(sources$heating_degree_days$provider, "OPEN_METEO")
  expect_true(grepl("level-calibrated to it \\(x2\\.000", sources$heating_degree_days$key))

  ## Eurostat's cooling series is all zeros here, so no factor can be
  ## measured for it -- it must say so rather than divide by zero.
  expect_true(grepl("UNCALIBRATED", sources$cooling_degree_days$key))
})

test_that("fetch_degree_days falls back to Eurostat alone for an EU country with no city set", {
  periods <- format(seq(as.Date("1990-01-01"), as.Date("1990-03-01"), by = "month"), "%Y-%m")
  with_mock_fetch_text(function(url, ...) {
    if (grepl("M\\.NR\\.HDD\\.FR", url)) return(estat_csv("HDD", "FR", periods, c(600, 500, 400)))
    if (grepl("M\\.NR\\.CDD\\.FR", url)) return(estat_csv("CDD", "FR", periods, c(0, 0, 0)))
    NULL
  }, {
    expect_warning(
      out <- fetch_degree_days("FRA", start_period = "1990-Q1",
                                reference_date = as.Date("1990-07-15"),
                                landing_dir = tempfile(), pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0),
      "No representative cities"
    )
  })
  expect_equal(out$heating_degree_days, 1500)
  sources <- attr(out, "sources")
  expect_equal(sources$heating_degree_days$provider, "EUROSTAT_CHDD")
  expect_true(grepl("official series only", sources$heating_degree_days$key))
})

test_that("fetch_degree_days uses Open-Meteo uncalibrated for a non-EU country", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_text(function(url, ...) {
    if (grepl("archive-api", url)) {
      return(om_json_const(5, from = as.Date("1990-01-01"), to = as.Date("1990-03-31")))
    }
    NULL
  }, {
    out <- fetch_degree_days("USA", start_period = "1990-Q1",
                              reference_date = as.Date("1990-04-15"),
                              landing_dir = landing_dir, pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
  })
  expect_equal(out$heating_degree_days, 13 * (31 + 28 + 31))
  sources <- attr(out, "sources")
  expect_equal(sources$heating_degree_days$provider, "OPEN_METEO")
  expect_true(grepl("UNCALIBRATED", sources$heating_degree_days$key))
})

test_that("fetch_degree_days returns NULL when neither source resolves", {
  suppressWarnings(
    with_mock_fetch_text(failing_fetch_text(), {
      out <- fetch_degree_days("USA", start_period = "1990-Q1",
                                reference_date = as.Date("1990-04-15"),
                                landing_dir = tempfile(), pause_seconds = 0,
                                         max_attempts = 2, retry_pause_seconds = 0)
    })
  )
  expect_null(out)
})

test_that("weather_city_weights is well formed and covers the CI's three countries", {
  expect_setequal(unique(weather_city_weights$country3), c("AUT", "DEU", "USA"))
  expect_true(all(weather_city_weights$weight > 0))
  expect_true(all(abs(weather_city_weights$lat) <= 90))
  expect_true(all(abs(weather_city_weights$lon) <= 180))
  expect_equal(nrow(weather_city_weights),
               nrow(dplyr::distinct(weather_city_weights, country3, city)))
})

test_that("the degree-day concepts are in concept_dictionary with a category that has bounds", {
  for (lbl in degree_day_indicators$label) {
    expect_true(lbl %in% concept_dictionary$label)
    expect_equal(plausibility_category(lbl), "nonneg_seasonal")
  }
  ## A quarter of exactly 0.00 cooling degree days is a real value, not a
  ## failure -- the whole reason these concepts are not category "level".
  expect_equal(check_one_concept("cooling_degree_days", c(0, 0, 350, 0, 0, 410))$status, "PASS")
})
