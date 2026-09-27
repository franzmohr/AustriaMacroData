test_that("ec_survey_zip_url builds the YYMM-based archive URL", {
  expect_equal(
    ec_survey_zip_url(2026, 8),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2608/main_indicators_sa_nace2.zip"
  )
  expect_equal(
    ec_survey_zip_url(2025, 1),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2501/main_indicators_sa_nace2.zip"
  )
})

test_that("ec_survey_landing_path names the cache file by year/month", {
  expect_equal(
    ec_survey_landing_path(2026, 8, "data/landing"),
    file.path("data/landing", "ec_bcs_main_indicators_2608.xlsx")
  )
})

## ---- Build a tiny real .xlsx + .zip fixture at test time --------------
## Rather than checking in a binary fixture, this constructs a
## MONTHLY-sheet-shaped workbook so the parser and cache logic are
## exercised against a real xlsx/zip, not a mock of their contents.
build_fixture_zip_bytes <- function() {
  skip_if_not_installed("writexl")
  tmp_xlsx <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_xlsx), add = TRUE)

  monthly <- data.frame(
    c1 = c(NA, "1985-01-31", "1985-02-28"),
    c2 = c("EU.CONS", "-10.2", "-10.6"),
    c3 = c("AT.CONS", "-5.1", "-6.2"),
    c4 = c("DE.CONS", "-8.0", "-8.3"),
    c5 = c("AT.ESI", "95.4", "96.1"),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(
    list(Index = data.frame(x = 1), INFO = data.frame(x = 1), MONTHLY = monthly),
    tmp_xlsx, col_names = FALSE
  )

  tmp_zip <- tempfile(fileext = ".zip")
  old_wd <- setwd(dirname(tmp_xlsx))
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(tmp_zip, basename(tmp_xlsx), flags = "-q")
  readBin(tmp_zip, "raw", file.info(tmp_zip)$size)
}

test_that("get_ec_survey_xlsx tries the current month first, fetches, and caches it", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  calls <- character()
  with_mock_fetch_binary(function(url, ...) {
    calls <<- c(calls, url)
    if (grepl("2608", url)) return(zip_bytes)
    NULL
  }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_equal(length(calls), 1)
  expect_true(grepl("2608", calls[1]))
  expect_equal(out$year, 2026)
  expect_equal(out$month, 8)
  expect_false(out$cached)
  expect_true(file.exists(out$path))
  expect_true(file.exists(ec_survey_landing_path(2026, 8, landing_dir)))
})

test_that("get_ec_survey_xlsx reads from the cache on a second call, without hitting the network again", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })

  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_false(called)
  expect_true(out$cached)
  expect_equal(out$month, 8)
})

test_that("get_ec_survey_xlsx walks back a month at a time until one succeeds", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  calls <- character()
  with_mock_fetch_binary(function(url, ...) {
    calls <<- c(calls, url)
    if (grepl("2607", url)) return(zip_bytes)
    NULL
  }, {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), max_lookback = 3, landing_dir = landing_dir)
  })
  expect_equal(length(calls), 2)
  expect_true(grepl("2608", calls[1]))
  expect_true(grepl("2607", calls[2]))
  expect_equal(out$month, 7)
})

test_that("get_ec_survey_xlsx returns NULL after exhausting the lookback window", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(failing_fetch_binary(), {
    out <- get_ec_survey_xlsx(reference_date = as.Date("2026-08-30"), max_lookback = 2, landing_dir = landing_dir)
  })
  expect_null(out)
})

test_that("parse_ec_survey_indicator extracts the requested country's CONS column by default", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  out <- parse_ec_survey_indicator(xlsx_path, "AT", "consumer_confidence")
  expect_equal(names(out), c("date", "consumer_confidence"))
  expect_equal(out$consumer_confidence, c(-5.1, -6.2))
})

test_that("parse_ec_survey_indicator's indicator parameter selects a different column", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  out <- parse_ec_survey_indicator(xlsx_path, "AT", "economic_sentiment_indicator", indicator = "ESI")
  expect_equal(names(out), c("date", "economic_sentiment_indicator"))
  expect_equal(out$economic_sentiment_indicator, c(95.4, 96.1))
})

test_that("parse_ec_survey_indicator returns NULL with a warning for an unknown country column", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  expect_warning(out <- parse_ec_survey_indicator(xlsx_path, "ZZ", "consumer_confidence"), "not found")
  expect_null(out)
})

test_that("fetch_ec_consumer_confidence refuses non-EU countries without a network call", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(out <- fetch_ec_consumer_confidence("USA"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_ec_survey_indicator refuses non-EU countries without a network call", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(out <- fetch_ec_survey_indicator("USA", "economic_sentiment_indicator", indicator = "ESI"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
})

test_that("fetch_ec_survey_indicator fetches and quarterly-averages a non-CONS indicator", {
  zip_bytes <- build_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    out <- fetch_ec_survey_indicator("AUT", "economic_sentiment_indicator", indicator = "ESI",
                                      start_period = "1985-Q1", reference_date = as.Date("2026-08-30"),
                                      landing_dir = landing_dir)
  })
  expect_equal(names(out), c("date", "economic_sentiment_indicator"))
  expect_equal(out$date, as.Date("1985-01-01"))
  expect_equal(out$economic_sentiment_indicator, mean(c(95.4, 96.1)))
})

test_that("ec_survey_indicators lists the six confirmed-live sub-indicators with their column suffixes", {
  expect_equal(ec_survey_indicators$label,
               c("economic_sentiment_indicator", "industrial_confidence", "employment_expectations",
                 "services_confidence", "retail_confidence", "construction_confidence"))
  expect_equal(ec_survey_indicators$indicator,
               c("ESI", "INDU", "EEI", "SERV", "RETA", "BUIL"))
})

## ---- Construction survey archive (weather as a limiting factor) -------

test_that("ec_survey_zip_url and ec_survey_landing_path address the construction archive", {
  expect_equal(
    ec_survey_zip_url(2026, 8, archive = "building"),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2608/building_total_sa_nace2.zip"
  )
  expect_equal(
    ec_survey_landing_path(2026, 8, "data/landing", archive = "building"),
    file.path("data/landing", "ec_bcs_building_2608.xlsx")
  )
})

test_that("the two archives cache to different files, so one cannot be served for the other", {
  expect_false(identical(
    ec_survey_landing_path(2026, 8, "data/landing", archive = "main"),
    ec_survey_landing_path(2026, 8, "data/landing", archive = "building")
  ))
})

test_that("an unknown archive name is an error, not a silent fall back to the main one", {
  expect_error(ec_survey_zip_url(2026, 8, archive = "financial_services"), "Unknown EC survey archive")
  expect_error(get_ec_survey_xlsx(archive = "financial_services"), "Unknown EC survey archive")
})

test_that("ec_building_factor_column builds the construction survey's series code", {
  expect_equal(ec_building_factor_column("AT"), "BUIL.AT.TOT.2.F3S.M")
  expect_equal(ec_building_factor_column("DE"), "BUIL.DE.TOT.2.F3S.M")
  ## The answer code is a parameter so the choice of F3S stays visible
  ## and checkable rather than being baked into a format string.
  expect_equal(ec_building_factor_column("AT", "F4S"), "BUIL.AT.TOT.2.F4S.M")
})

build_building_fixture_zip_bytes <- function() {
  skip_if_not_installed("writexl")
  tmp_xlsx <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_xlsx), add = TRUE)

  ## Column order deliberately mirrors the real workbook, where the
  ## weather answer (F3S) sits between "insufficient demand" (F2S) and
  ## "shortage of labour force" (F4S) -- a parser that picked a column by
  ## position rather than by name would pass against a one-column fixture.
  building <- data.frame(
    c1 = c(NA, "1985-01-31", "1985-02-28", "1985-03-31"),
    c2 = c("BUIL.AT.TOT.2.F2S.M", "40.0", "41.0", "42.0"),
    c3 = c("BUIL.AT.TOT.2.F3S.M", "18.0", "12.0", "9.0"),
    c4 = c("BUIL.AT.TOT.2.F4S.M", "3.0", "3.5", "4.0"),
    c5 = c("BUIL.DE.TOT.2.F3S.M", "22.0", "20.0", "15.0"),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(
    list(Index = data.frame(x = 1), INFO = data.frame(x = 1), `BUILDING MONTHLY` = building),
    tmp_xlsx, col_names = FALSE
  )

  tmp_zip <- tempfile(fileext = ".zip")
  old_wd <- setwd(dirname(tmp_xlsx))
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(tmp_zip, basename(tmp_xlsx), flags = "-q")
  readBin(tmp_zip, "raw", file.info(tmp_zip)$size)
}

test_that("parse_ec_survey_building_factor picks the weather column by name, not position", {
  zip_bytes <- build_building_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  out <- parse_ec_survey_building_factor(xlsx_path, "AT", "construction_weather_constraint")
  expect_equal(names(out), c("date", "construction_weather_constraint"))
  expect_equal(out$construction_weather_constraint, c(18, 12, 9))

  de <- parse_ec_survey_building_factor(xlsx_path, "DE", "construction_weather_constraint")
  expect_equal(de$construction_weather_constraint, c(22, 20, 15))
})

test_that("parse_ec_survey_building_factor returns NULL with a warning for a country not surveyed", {
  zip_bytes <- build_building_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  xlsx_path <- extract_ec_survey_xlsx(zip_bytes)

  ## Not hypothetical: the UK's building survey stopped in 2019 and the
  ## workbook's INFO sheet lists further suspended countries.
  expect_warning(
    out <- parse_ec_survey_building_factor(xlsx_path, "UK", "construction_weather_constraint"),
    "not found"
  )
  expect_null(out)
})

test_that("fetch_ec_construction_weather_constraint quarterly-averages the monthly series", {
  zip_bytes <- build_building_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  urls <- character()
  with_mock_fetch_binary(function(url, ...) { urls <<- c(urls, url); zip_bytes }, {
    out <- fetch_ec_construction_weather_constraint(
      "AUT", start_period = "1985-Q1", reference_date = as.Date("2026-08-30"),
      landing_dir = landing_dir
    )
  })
  expect_true(grepl("building_total_sa_nace2\\.zip", urls[1]))
  expect_equal(names(out), c("date", "construction_weather_constraint"))
  expect_equal(out$date, as.Date("1985-01-01"))
  expect_equal(out$construction_weather_constraint, mean(c(18, 12, 9)))
})

test_that("fetch_ec_construction_weather_constraint refuses non-EU countries without a network call", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(out <- fetch_ec_construction_weather_constraint("USA"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
})

## ---- Consumer survey archive: the individual questions -----------------

test_that("the consumer archive has its own URL and cache file", {
  expect_equal(
    ec_survey_zip_url(2026, 8, archive = "consumer"),
    "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2608/consumer_total_sa_nace2.zip"
  )
  expect_equal(
    ec_survey_landing_path(2026, 8, "data/landing", archive = "consumer"),
    file.path("data/landing", "ec_bcs_consumer_2608.xlsx")
  )
})

test_that("ec_consumer_question_column builds the consumer survey's series code", {
  expect_equal(ec_consumer_question_column("AT", "2"), "CONS.AT.TOT.2.BS.M")
  expect_equal(ec_consumer_question_column("AT", "14", "Q"), "CONS.AT.TOT.14.BS.Q")
})

test_that("ec_consumer_questions leaves out COF, which is consumer_confidence, and the withdrawn 10 and 13", {
  expect_false(any(ec_consumer_questions$question %in% c("COF", "10", "13")))
  expect_equal(nrow(ec_consumer_questions), length(unique(ec_consumer_questions$label)))
  expect_setequal(ec_consumer_questions$question[ec_consumer_questions$frequency == "Q"], c("14", "15"))
  ## Every question is a concept, so the panel builders keep its column
  expect_true(all(ec_consumer_questions$label %in% concept_dictionary$label))
})

build_consumer_fixture_zip_bytes <- function() {
  skip_if_not_installed("writexl")
  tmp_xlsx <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_xlsx), add = TRUE)

  ## Q1 sits beside Q2 and COF, so a parser that picked by position
  ## rather than by name would read the wrong question.
  monthly <- data.frame(
    c1 = c(NA, "1985-01-31", "1985-02-28", "1985-03-31", "1985-04-30"),
    c2 = c("CONS.AT.TOT.COF.BS.M", "-5.0", "-6.0", "-7.0", "-8.0"),
    c3 = c("CONS.AT.TOT.1.BS.M", "-10.0", "-11.0", "-12.0", "-13.0"),
    c4 = c("CONS.AT.TOT.2.BS.M", "3.0", "6.0", "9.0", "12.0"),
    stringsAsFactors = FALSE
  )
  quarterly <- data.frame(
    c1 = c(NA, "1985-Q1", "1985-Q2"),
    c2 = c("CONS.AT.TOT.14.BS.Q", "-80.0", "-82.5"),
    c3 = c("CONS.AT.TOT.15.BS.Q", "-40.0", "-41.0"),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(
    list(Index = data.frame(x = 1), INFO = data.frame(x = 1),
         `CONSUMER MONTHLY` = monthly, `CONSUMER QUARTERLY` = quarterly),
    tmp_xlsx, col_names = FALSE
  )

  tmp_zip <- tempfile(fileext = ".zip")
  old_wd <- setwd(dirname(tmp_xlsx))
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(tmp_zip, basename(tmp_xlsx), flags = "-q")
  readBin(tmp_zip, "raw", file.info(tmp_zip)$size)
}

test_that("fetch_ec_consumer_question quarterly-averages a monthly question, picked by name", {
  zip_bytes <- build_consumer_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  urls <- character()
  with_mock_fetch_binary(function(url, ...) { urls <<- c(urls, url); zip_bytes }, {
    out <- fetch_ec_consumer_question("AUT", "consumer_financial_situation_expected", "2",
                                      start_period = "1985-Q1", reference_date = as.Date("2026-08-30"),
                                      landing_dir = landing_dir)
  })
  expect_true(grepl("consumer_total_sa_nace2\\.zip", urls[1]))
  expect_equal(names(out), c("date", "consumer_financial_situation_expected"))
  expect_equal(out$date, as.Date(c("1985-01-01", "1985-04-01")))
  expect_equal(out$consumer_financial_situation_expected, c(mean(c(3, 6, 9)), 12))
})

test_that("fetch_ec_consumer_question keeps the months for a monthly panel", {
  zip_bytes <- build_consumer_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    out <- fetch_ec_consumer_question("AUT", "consumer_financial_situation_past", "1",
                                      start_period = "1985-M01", reference_date = as.Date("2026-08-30"),
                                      landing_dir = landing_dir, frequency = "M")
  })
  expect_equal(out$date, as.Date(c("1985-01-01", "1985-02-01", "1985-03-01", "1985-04-01")))
  expect_equal(out$consumer_financial_situation_past, c(-10, -11, -12, -13))
})

test_that("fetch_ec_consumer_question reads a quarterly question off the quarterly sheet", {
  zip_bytes <- build_consumer_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    out <- fetch_ec_consumer_question("AUT", "consumer_home_purchase_intentions", "14",
                                      start_period = "1985-Q1", reference_date = as.Date("2026-08-30"),
                                      landing_dir = landing_dir)
  })
  expect_equal(out$date, as.Date(c("1985-01-01", "1985-04-01")))
  expect_equal(out$consumer_home_purchase_intentions, c(-80, -82.5))
})

test_that("a quarterly-only question is absent from a monthly panel, without a network call", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    out <- fetch_ec_consumer_question("AUT", "consumer_home_purchase_intentions", "14",
                                      start_period = "1985-M01", frequency = "M")
  })
  expect_null(out)
  expect_false(called)
})

test_that("an unknown consumer question is an error, and a non-EU country is refused", {
  expect_error(fetch_ec_consumer_question("AUT", "x", "COF"), "Unknown EC consumer survey question")
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_warning(out <- fetch_ec_consumer_question("USA", "x", "2"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
})

## ---- Business surveys: industry, services, retail, construction --------

test_that("industry, services and retail come out of the one all-surveys bundle", {
  for (archive in c("industry", "services", "retail")) {
    expect_equal(
      ec_survey_zip_url(2026, 8, archive = archive),
      "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2608/all_surveys_total_sa_nace2.zip"
    )
  }
  expect_equal(ec_survey_landing_path(2026, 8, "data/landing", archive = "services"),
               file.path("data/landing", "ec_bcs_services_2608.xlsx"))
})

test_that("ec_business_question_key builds the survey's own series codes", {
  expect_equal(ec_business_question_key("industry_order_books", "AT"), "INDU.AT.TOT.2.BS.M")
  expect_equal(ec_business_question_key("industry_capacity_utilization", "AT"), "INDU.AT.TOT.13.QPS.Q")
  ## "Financial" is F5S in services but F6S in industry -- read off each
  ## workbook's Index sheet, not assumed to line up.
  expect_equal(ec_business_question_key("services_limits_financial", "AT"), "SERV.AT.TOT.7.F5S.Q")
  expect_equal(ec_business_question_key("industry_limits_financial", "AT"), "INDU.AT.TOT.8.F6S.Q")
  expect_equal(ec_business_question_key("construction_limits_financial", "EL"), "BUIL.EL.TOT.2.F7S.M")
})

test_that("ec_business_questions leaves out the confidence composites and the weather answer", {
  expect_false(any(ec_business_questions$question == "COF"))
  expect_false(any(ec_business_questions$sector == "BUIL" & ec_business_questions$answer == "F3S"))
  expect_equal(nrow(ec_business_questions), length(unique(ec_business_questions$label)))
  expect_true(all(ec_business_questions$archive %in% names(ec_survey_archives)))
  ## A quarterly question needs a quarterly sheet to be read from
  quarterly_archives <- unique(ec_business_questions$archive[ec_business_questions$frequency == "Q"])
  for (a in quarterly_archives) expect_false(is.null(ec_survey_archives[[a]]$quarterly_sheet))
  expect_true(all(ec_business_questions$label %in% concept_dictionary$label))
})

build_all_surveys_fixture_zip_bytes <- function() {
  skip_if_not_installed("writexl")
  dir <- tempfile()
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  ## Q1 sits between COF and Q2, so a parser that picked by position
  ## rather than by name would read the wrong question.
  industry_monthly <- data.frame(
    c1 = c(NA, "1985-01-31", "1985-02-28", "1985-03-31", "1985-04-30"),
    c2 = c("INDU.AT.TOT.COF.BS.M", "-5.0", "-6.0", "-7.0", "-8.0"),
    c3 = c("INDU.AT.TOT.1.BS.M", "1.0", "2.0", "3.0", "4.0"),
    c4 = c("INDU.AT.TOT.2.BS.M", "-20.0", "-21.0", "-22.0", "-23.0"),
    stringsAsFactors = FALSE
  )
  industry_quarterly <- data.frame(
    c1 = c(NA, "1985-Q1", "1985-Q2"),
    c2 = c("INDU.AT.TOT.8.F2S.Q", "30.0", "31.0"),
    c3 = c("INDU.AT.TOT.13.QPS.Q", "82.5", "83.1"),
    stringsAsFactors = FALSE
  )
  services_monthly <- data.frame(
    c1 = c(NA, "1985-01-31"),
    c2 = c("SERV.AT.TOT.1.BS.M", "7.0"),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(list(Index = data.frame(x = 1), `INDUSTRY MONTHLY` = industry_monthly,
                           `INDUSTRY QUARTERLY` = industry_quarterly),
                      file.path(dir, "industry_total_sa_nace2.xlsx"), col_names = FALSE)
  writexl::write_xlsx(list(Index = data.frame(x = 1), `SERVICES MONTHLY` = services_monthly),
                      file.path(dir, "services_total_sa_nace2.xlsx"), col_names = FALSE)
  ## The bundle's other workbooks; the first in the archive, so a reader
  ## that took the first .xlsx rather than the named member would fail.
  writexl::write_xlsx(list(MONTHLY = data.frame(x = 1)),
                      file.path(dir, "building_total_sa_nace2.xlsx"), col_names = FALSE)

  tmp_zip <- tempfile(fileext = ".zip")
  old_wd <- setwd(dir)
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(tmp_zip, c("building_total_sa_nace2.xlsx", "industry_total_sa_nace2.xlsx",
                        "services_total_sa_nace2.xlsx"), flags = "-q")
  readBin(tmp_zip, "raw", file.info(tmp_zip)$size)
}

test_that("fetch_ec_business_question reads a monthly question by name and averages it", {
  zip_bytes <- build_all_surveys_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  urls <- character()
  with_mock_fetch_binary(function(url, ...) { urls <<- c(urls, url); zip_bytes }, {
    out <- fetch_ec_business_question("AUT", "industry_production_past", start_period = "1985-Q1",
                                      reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_true(grepl("all_surveys_total_sa_nace2\\.zip", urls[1]))
  expect_equal(out$date, as.Date(c("1985-01-01", "1985-04-01")))
  expect_equal(out$industry_production_past, c(2, 4))
})

test_that("fetch_ec_business_question reads a quarterly answer off the quarterly sheet", {
  zip_bytes <- build_all_surveys_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(const_fetch_binary(zip_bytes), {
    out <- fetch_ec_business_question("AUT", "industry_capacity_utilization", start_period = "1985-Q1",
                                      reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_equal(out$date, as.Date(c("1985-01-01", "1985-04-01")))
  expect_equal(out$industry_capacity_utilization, c(82.5, 83.1))
})

test_that("one download of the bundle serves every sector in it", {
  zip_bytes <- build_all_surveys_fixture_zip_bytes()
  skip_if(is.null(zip_bytes) || length(zip_bytes) == 0, "could not build test fixture (zip/writexl unavailable)")
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  calls <- 0
  with_mock_fetch_binary(function(url, ...) { calls <<- calls + 1; zip_bytes }, {
    fetch_ec_business_question("AUT", "industry_order_books", start_period = "1985-Q1",
                               reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
    out <- fetch_ec_business_question("AUT", "services_business_situation_past",
                                      start_period = "1985-M01", frequency = "M",
                                      reference_date = as.Date("2026-08-30"), landing_dir = landing_dir)
  })
  expect_equal(calls, 1)
  expect_equal(out$services_business_situation_past, 7)
})

test_that("a quarterly business question is absent from a monthly panel, and non-EU is refused", {
  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    expect_null(fetch_ec_business_question("AUT", "industry_capacity_utilization",
                                           start_period = "1985-M01", frequency = "M"))
    expect_warning(out <- fetch_ec_business_question("USA", "industry_order_books"), "EU member states")
  })
  expect_null(out)
  expect_false(called)
  expect_error(fetch_ec_business_question("AUT", "industry_confidence_composite"),
               "Unknown EC business survey question")
})
