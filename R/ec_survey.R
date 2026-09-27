## ---------------------------------------------------------------
## ec_survey.R -- European Commission Business and Consumer Survey (BCS),
## consumer confidence indicator, for EU member states
##
## STATUS: VERIFIED 2026-08-30 against ec.europa.eu's own monthly archive:
##   https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_<YYMM>/main_indicators_sa_nace2.zip
## <YYMM> is a 2-digit year + 2-digit month (e.g. "2608" = August 2026).
## An unpublished month 301-redirects to a generic landing page (still
## HTTP 200 after the redirect, Content-Type text/html) rather than
## returning a clean 404 -- confirmed live, caught by `fetch_binary()`'s
## (R/utils.R) Content-Type check; a mislabeled response would still be
## caught downstream since `extract_ec_survey_xlsx()`'s `unzip()` call
## fails cleanly (returns NULL, not an error) on non-ZIP bytes.
##
## The archive is a single .xlsx (main_indicators_nace2.xlsx) with a
## "MONTHLY" sheet: column 1 = month-end date, and one column per
## "<EC 2-letter code>.<INDICATOR>" (e.g. "AT.CONS", "DE.CONS" for
## consumer confidence; also .INDU/.SERV/.RETA/.BUIL/.ESI/.EEI for other
## sectors, not used here). Confirmed live with real, CURRENT data
## through 2026-08 for AT and DE (values around -18 to -20, a plausible
## consumer-confidence balance) -- unlike the OECD-MEI-via-FRED
## `consumer_confidence` source in R/fred_mirror.R, whose data is frozen
## around 2024 (see that file's header comment).
##
## Motivation: for EU countries, this is a fresher, primary-source
## alternative to the frozen `CSCICP03{cc2}M665S` FRED mirror --
## scripts/build_country_panel.R tries this FIRST for EU member states
## (see R/country_codes.R's `eu_member_countries`) and overrides the
## FRED-mirror value with it on success, falling back to the FRED mirror
## otherwise (e.g. a transient failure, or a future EU member not yet in
## the archive).
##
## CACHING: the archive covers every EU country in one file and only
## changes once a month, so it is cached in `data/landing/` (gitignored,
## like the rest of that directory) rather than re-downloaded for every
## country. `get_ec_survey_xlsx()` checks the local cache for each
## candidate month BEFORE ever hitting the network; building the panel
## for e.g. AUT then DEU in the same month downloads the archive once.
##
## EXTENDED 2026-09-07: the same monthly folder publishes the SECTORAL
## survey archives alongside the headline one, and the construction
## survey carries something no other source in this project does -- a
## harmonised, self-reported measure of WEATHER as a constraint on real
## economic activity. `building_total_sa_nace2.zip` (confirmed live:
## HTTP 200, 1.0 MB for month "2608"; an unpublished month 301-redirects
## exactly like the main archive, so the same month-walkback logic
## applies unchanged) contains one .xlsx whose "BUILDING MONTHLY" sheet
## uses a DIFFERENT column-naming scheme from the main archive's
## "MONTHLY" sheet: `<SECTOR>.<COUNTRY>.<SUBSECTOR>.<QUESTION>.<ANSWER>.<FREQ>`,
## e.g. "BUIL.AT.TOT.2.F3S.M". Question 2 is "Main factors currently
## limiting your building activity" and answer F3S is documented by the
## workbook's own Index sheet as "Weather conditions (% s.a. - monthly
## question 2)" -- read off that sheet, not inferred from the
## questionnaire's answer ordering, which is a real trap here: the
## published order puts financial constraints LAST (F7S) while "other
## factors" is F6S, so counting down the questionnaire would have picked
## the wrong column. Confirmed live for Austria: monthly, seasonally
## adjusted, 500 non-NA observations from 1985-01 through 2026-08.
##
## That the series is already seasonally adjusted is what makes it
## usable here: the raw share of construction firms blaming the weather
## is overwhelmingly a January-versus-July effect, whereas the s.a.
## series is by construction a weather ANOMALY -- how unusually
## obstructive this month's weather was for building activity, relative
## to a normal month of the same name.
## ---------------------------------------------------------------

ec_survey_base_url <- "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series"
ec_survey_landing_dir <- "data/landing"

## The two archives this project reads out of the same monthly folder.
## Both are zipped single-.xlsx downloads that behave identically as far
## as fetching, month-walkback and caching are concerned -- they differ
## only in file name, sheet name and column-naming scheme, so everything
## below is parameterised by this table rather than duplicated.
ec_survey_archives <- list(
  main = list(
    zip_name   = "main_indicators_sa_nace2.zip",
    cache_stem = "ec_bcs_main_indicators",
    sheet      = "MONTHLY"
  ),
  building = list(
    zip_name   = "building_total_sa_nace2.zip",
    cache_stem = "ec_bcs_building",
    sheet      = "BUILDING MONTHLY"
  ),
  consumer = list(
    zip_name   = "consumer_total_sa_nace2.zip",
    cache_stem = "ec_bcs_consumer",
    sheet      = "CONSUMER MONTHLY"
  ),
  ## The three business surveys this project reads question by question
  ## come out of ONE download, `all_surveys_total_sa_nace2.zip`, which
  ## bundles every sector's workbook (see "Business surveys" below). A
  ## `member` names the workbook inside it, and a download caches every
  ## member of that archive at once, so the three cost one request.
  industry = list(
    zip_name         = "all_surveys_total_sa_nace2.zip",
    member           = "industry_total_sa_nace2.xlsx",
    cache_stem       = "ec_bcs_industry",
    sheet            = "INDUSTRY MONTHLY",
    quarterly_sheet  = "INDUSTRY QUARTERLY"
  ),
  services = list(
    zip_name         = "all_surveys_total_sa_nace2.zip",
    member           = "services_total_sa_nace2.xlsx",
    cache_stem       = "ec_bcs_services",
    sheet            = "SERVICES MONTHLY",
    quarterly_sheet  = "SERVICES QUARTERLY"
  ),
  retail = list(
    zip_name         = "all_surveys_total_sa_nace2.zip",
    member           = "retail_total_sa_nace2.xlsx",
    cache_stem       = "ec_bcs_retail",
    sheet            = "RETAIL TRADE MONTHLY"
  )
)

#' Look up one archive's spec, erroring loudly on an unknown name rather
#' than silently falling back to the main archive
ec_survey_archive <- function(archive = "main") {
  spec <- ec_survey_archives[[archive]]
  if (is.null(spec)) {
    stop(sprintf("Unknown EC survey archive '%s' -- known: %s",
                 archive, paste(names(ec_survey_archives), collapse = ", ")),
         call. = FALSE)
  }
  spec
}

#' Build the archive URL for a given calendar year/month
ec_survey_zip_url <- function(year, month, archive = "main") {
  yymm <- sprintf("%02d%02d", year %% 100, month)
  sprintf("%s/nace2_ecfin_%s/%s", ec_survey_base_url, yymm, ec_survey_archive(archive)$zip_name)
}

#' Local cache path for a given calendar year/month's workbook
ec_survey_landing_path <- function(year, month, landing_dir = ec_survey_landing_dir,
                                    archive = "main") {
  file.path(landing_dir, sprintf("%s_%02d%02d.xlsx", ec_survey_archive(archive)$cache_stem,
                                  year %% 100, month))
}

#' Unzip archive bytes and return the path to the .xlsx inside, or NULL
#'
#' A single-workbook archive returns its one .xlsx. For a multi-workbook
#' archive, `member` names the workbook wanted; NULL is returned if it is
#' not in the archive rather than falling back to whichever came first.
extract_ec_survey_xlsx <- function(zip_bytes, member = NULL) {
  tmp_zip <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp_zip), add = TRUE)
  writeBin(zip_bytes, tmp_zip)

  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  extracted <- tryCatch(utils::unzip(tmp_zip, exdir = tmp_dir), error = function(e) character(0))
  xlsx_path <- extracted[stringr::str_detect(extracted, stringr::regex("\\.xlsx$", ignore_case = TRUE))]
  if (!is.null(member)) {
    xlsx_path <- xlsx_path[tolower(basename(xlsx_path)) == tolower(member)]
  }
  if (length(xlsx_path) == 0) {
    unlink(tmp_dir, recursive = TRUE)
    return(NULL)
  }
  xlsx_path[1]
}

#' Cache every registered member of a multi-workbook archive
#'
#' Called once a multi-workbook archive has been downloaded for one of its
#' members: the other members registered in `ec_survey_archives` with the
#' same `zip_name` are written into the cache as well, so fetching the
#' industry questions and then the services questions downloads the
#' bundle once, not twice.
cache_ec_survey_siblings <- function(zip_bytes, zip_name, year, month, landing_dir) {
  for (name in names(ec_survey_archives)) {
    spec <- ec_survey_archives[[name]]
    if (is.null(spec$member) || !identical(spec$zip_name, zip_name)) next
    cached_path <- ec_survey_landing_path(year, month, landing_dir, name)
    if (file.exists(cached_path)) next
    extracted_path <- extract_ec_survey_xlsx(zip_bytes, member = spec$member)
    if (is.null(extracted_path)) next
    dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
    file.copy(extracted_path, cached_path, overwrite = TRUE)
    unlink(dirname(extracted_path), recursive = TRUE)
  }
}

#' Get a local path to the EC survey workbook for the most recent
#' available month, downloading and caching it if not already there
#'
#' For each candidate month, current first then walking back up to
#' `max_lookback` months: a local cache hit returns immediately (no
#' network call at all); otherwise this tries the network and, on
#' success, saves the workbook into `landing_dir` before returning it, so
#' every later call (any country, same month) hits the cache. Returns
#' NULL if no candidate month is either cached or fetchable.
get_ec_survey_xlsx <- function(reference_date = Sys.Date(), max_lookback = 3,
                                landing_dir = ec_survey_landing_dir,
                                archive = "main") {
  ec_survey_archive(archive)  # fail fast on a typo'd archive name
  ym0 <- as.integer(format(reference_date, "%Y")) * 12 + (as.integer(format(reference_date, "%m")) - 1)
  for (back in 0:max_lookback) {
    ym <- ym0 - back
    year <- ym %/% 12
    month <- ym %% 12 + 1
    cached_path <- ec_survey_landing_path(year, month, landing_dir, archive)
    if (file.exists(cached_path)) {
      return(list(path = cached_path, year = year, month = month, cached = TRUE))
    }

    bytes <- fetch_binary(ec_survey_zip_url(year, month, archive))
    if (!is.null(bytes)) {
      spec <- ec_survey_archive(archive)
      if (!is.null(spec$member)) {
        cache_ec_survey_siblings(bytes, spec$zip_name, year, month, landing_dir)
        if (file.exists(cached_path)) {
          return(list(path = cached_path, year = year, month = month, cached = FALSE))
        }
        next
      }
      extracted_path <- extract_ec_survey_xlsx(bytes)
      if (!is.null(extracted_path)) {
        dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
        file.copy(extracted_path, cached_path, overwrite = TRUE)
        unlink(dirname(extracted_path), recursive = TRUE)
        return(list(path = cached_path, year = year, month = month, cached = FALSE))
      }
    }
  }
  NULL
}

#' Extract one country's column for a given survey indicator from a
#' workbook path
#'
#' `ec_country2` is the Commission's own 2-letter code (see
#' R/country_codes.R's `lookup_ec_country2()` -- identical to the usual
#' FRED 2-letter code except Greece, "EL" not "GR"). `indicator` selects
#' which of the archive's seven per-country columns to read (see
#' `ec_survey_indicators` below for the confirmed suffixes). Returns a
#' `date` + `label` monthly tibble, or NULL (with a warning) if the
#' workbook can't be read or the country's column isn't in it.
parse_ec_survey_indicator <- function(xlsx_path, ec_country2, label, indicator = "CONS") {
  parse_ec_survey_column(xlsx_path, sheet = "MONTHLY",
                          col_name = paste0(ec_country2, ".", indicator), label = label)
}

#' Extract one named column from one sheet of an EC survey workbook
#'
#' Both archives lay their sheets out the same way -- row 1 is a header
#' of series codes, column 1 is a month-end date -- and differ only in
#' the sheet name and the shape of the series codes, so both
#' `parse_ec_survey_indicator()` (main archive, "<CC>.<INDICATOR>") and
#' `parse_ec_survey_building_factor()` (construction archive,
#' "BUIL.<CC>.TOT.<Q>.<ANSWER>.M") come through here. Returns a `date` +
#' `label` monthly tibble, or NULL (with a warning) if the sheet can't be
#' read or the column isn't in it.
parse_ec_survey_column <- function(xlsx_path, sheet, col_name, label) {
  monthly <- tryCatch(
    suppressMessages(readxl::read_excel(xlsx_path, sheet = sheet, col_names = FALSE)),
    error = function(e) NULL
  )
  if (is.null(monthly)) {
    warning(sprintf("[%s] Could not read the '%s' sheet from the EC survey archive", label, sheet))
    return(NULL)
  }

  header <- as.character(monthly[1, ])
  col_idx <- which(header == col_name)
  if (length(col_idx) == 0) {
    warning(sprintf("[%s] Column '%s' not found in the EC survey archive", label, col_name))
    return(NULL)
  }

  out <- tibble::tibble(
    date = suppressWarnings(as.Date(monthly[[1]][-1])),
    value = suppressWarnings(as.numeric(monthly[[col_idx[1]]][-1]))
  ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value))
  names(out)[2] <- label
  out
}

## EXTENDED 2026-08-30: the archive's "MONTHLY" sheet carries SEVEN
## per-country columns, not just ".CONS" -- confirmed live in the
## already-cached workbook (data/landing/ec_bcs_main_indicators_*.xlsx):
## "<cc2>.INDU", ".SERV", ".CONS", ".RETA", ".BUIL", ".ESI", ".EEI",
## present for every EU member checked (AT, DE). ESI (Economic Sentiment
## Indicator) and INDU (Industrial Confidence) are the two with
## documented predictive power for GDP/business-cycle turning points --
## ESI is DG ECFIN's own flagship composite, explicitly constructed and
## validated to track and lead euro-area GDP growth; INDU is one of the
## oldest EU survey series (since 1985) and a standard input to the
## OECD's Composite Leading Indicators for many countries. EEI
## (Employment Expectations Indicator) is DG ECFIN's own purpose-built
## leading indicator for employment turning points, introduced in 2013
## specifically because the employment sub-components of the sectoral
## surveys lead employment growth. SERV/RETA/BUIL (services/retail/
## construction confidence) are the remaining ESI sub-components --
## standard, EC-published sentiment measures without the same
## individually-validated leading-indicator literature behind them, but
## a low-cost extension since they are already in the same archive this
## project caches.
ec_survey_indicators <- tibble::tribble(
  ~label,                         ~indicator,
  "economic_sentiment_indicator", "ESI",
  "industrial_confidence",        "INDU",
  "employment_expectations",      "EEI",
  "services_confidence",          "SERV",
  "retail_confidence",            "RETA",
  "construction_confidence",      "BUIL"
)

#' Fetch quarterly consumer confidence for an EU country from the EC's own
#' Business and Consumer Survey, averaging the underlying monthly series
#'
#' Returns NULL (with a warning) if the country isn't an EU member, the
#' archive can't be found (cached or fetched) within the lookback window,
#' or the country's column isn't in it.
fetch_ec_consumer_confidence <- function(country3, label = "consumer_confidence",
                                          start_period = "1995-Q1",
                                          reference_date = Sys.Date(),
                                          landing_dir = ec_survey_landing_dir,
                                          frequency = "Q") {
  fetch_ec_survey_indicator(country3, label, indicator = "CONS",
                             start_period = start_period, reference_date = reference_date,
                             landing_dir = landing_dir, frequency = frequency)
}

#' Fetch any one of the EC Business and Consumer Survey's seven
#' per-country indicators for an EU country, quarterly-averaged
#'
#' `indicator` is one of the confirmed suffixes in `ec_survey_indicators`
#' (or "CONS", the consumer-confidence column `fetch_ec_consumer_confidence()`
#' wraps this function for). Returns NULL (with a warning) if the country
#' isn't an EU member, the archive can't be found (cached or fetched)
#' within the lookback window, or the country's column isn't in it.
#'
#' BUG FIX 2026-08-30: this always called `get_ec_survey_xlsx()` with its
#' OWN default `landing_dir` ("data/landing"), silently ignoring any
#' `landing_dir` a caller might have intended -- unlike every other
#' caching module in this project (`fetch_bis_credit_bulk()`,
#' `fetch_gpr_bulk()`), which do expose and thread through `landing_dir`.
#' No caller in `scripts/build_country_panel.R` was ever affected (none
#' pass a non-default `landing_dir` here), but a test that mocked the
#' network layer and expected an isolated temp cache was instead writing
#' a real fixture file into the project's own `data/landing/` on every
#' run -- caught by noticing an untracked `tests/testthat/data/landing/`
#' directory reappear after a full test-suite run, not by a failing
#' assertion (the test still passed; the leak was silent).
fetch_ec_survey_indicator <- function(country3, label, indicator = "CONS",
                                       start_period = "1995-Q1",
                                       reference_date = Sys.Date(),
                                       landing_dir = ec_survey_landing_dir,
                                       frequency = "Q") {
  if (!country3 %in% eu_member_countries) {
    warning(sprintf("[%s] EC Business and Consumer Survey only covers EU member states -- '%s' is not one", label, country3))
    return(NULL)
  }
  ec_country2 <- lookup_ec_country2(country3)
  if (is.na(ec_country2)) return(NULL)

  found <- get_ec_survey_xlsx(reference_date, landing_dir = landing_dir)
  if (is.null(found)) {
    warning(sprintf("[%s] Could not find a published EC survey archive (cached or live) within the lookback window", label))
    return(NULL)
  }

  monthly_df <- parse_ec_survey_indicator(found$path, ec_country2, label, indicator = indicator)
  if (is.null(monthly_df)) return(NULL)

  aggregate_to(monthly_df, label, frequency) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}

## ---------------------------------------------------------------
## Construction survey: weather as a reported constraint on activity
## ---------------------------------------------------------------
## The construction survey's question 2 ("Main factors currently limiting
## your building activity") is a multiple-choice question whose answers
## are published as the percentage of firms citing each factor, s.a.
## F3S is weather (see this file's header for why the code is read off
## the workbook's Index sheet rather than counted out of the
## questionnaire). The remaining answer codes are listed here because
## having them written down is what makes the F3S choice checkable by
## the next reader, not because this project fetches them.
##
## F1S none, F2S insufficient demand, F3S weather conditions,
## F4S shortage of labour force, F5S shortage of material and/or
## equipment, F6S other factors, F7S financial constraints.
ec_building_weather_answer <- "F3S"

#' Build the construction-survey column name for one country's answer to
#' the "factors limiting building activity" question
ec_building_factor_column <- function(ec_country2, answer = ec_building_weather_answer) {
  sprintf("BUIL.%s.TOT.2.%s.M", ec_country2, answer)
}

#' Extract one country's "factors limiting building activity" answer from
#' a construction-survey workbook
parse_ec_survey_building_factor <- function(xlsx_path, ec_country2, label,
                                             answer = ec_building_weather_answer) {
  parse_ec_survey_column(xlsx_path, sheet = ec_survey_archives$building$sheet,
                          col_name = ec_building_factor_column(ec_country2, answer),
                          label = label)
}

#' Fetch the quarterly share of construction firms reporting weather as a
#' factor limiting their building activity, for an EU country
#'
#' Quarterly-AVERAGED (not summed) like every other survey balance in
#' this project: this is a percentage of respondents, so a quarter's
#' value is the average of its months, and unlike degree days (see
#' R/weather.R) a partially-observed quarter is a noisier estimate rather
#' than a systematically smaller number.
#'
#' Returns NULL (with a warning) if the country isn't an EU member, the
#' construction archive can't be found (cached or fetched) within the
#' lookback window, or the country's column isn't in it -- the last of
#' which is a real case, not a defensive one: the UK's building survey
#' stopped in November 2019, and the workbook's own INFO sheet records
#' several countries whose surveys are suspended.
fetch_ec_construction_weather_constraint <- function(country3,
                                                      label = "construction_weather_constraint",
                                                      start_period = "1995-Q1",
                                                      reference_date = Sys.Date(),
                                                      landing_dir = ec_survey_landing_dir,
                                                      frequency = "Q") {
  if (!country3 %in% eu_member_countries) {
    warning(sprintf("[%s] EC Business and Consumer Survey only covers EU member states -- '%s' is not one", label, country3))
    return(NULL)
  }
  ec_country2 <- lookup_ec_country2(country3)
  if (is.na(ec_country2)) return(NULL)

  found <- get_ec_survey_xlsx(reference_date, landing_dir = landing_dir, archive = "building")
  if (is.null(found)) {
    warning(sprintf("[%s] Could not find a published EC construction survey archive (cached or live) within the lookback window", label))
    return(NULL)
  }

  monthly_df <- parse_ec_survey_building_factor(found$path, ec_country2, label)
  if (is.null(monthly_df)) return(NULL)

  aggregate_to(monthly_df, label, frequency) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
}

## ---------------------------------------------------------------
## Consumer survey: the individual questions behind consumer confidence
## ---------------------------------------------------------------
## ADDED 2026-09-27. `consumer_total_sa_nace2.zip` (confirmed live: HTTP
## 200, application/zip, 1.1 MB for month "2608") sits in the same
## monthly folder as the two archives above and walks back the same way.
## Its one .xlsx has two data sheets with the building archive's naming
## scheme, `<SECTOR>.<COUNTRY>.<SUBSECTOR>.<QUESTION>.<ANSWER>.<FREQ>`:
##   "CONSUMER MONTHLY"    e.g. "CONS.AT.TOT.2.BS.M", column 1 a month-end
##                         date, like every other monthly sheet here;
##   "CONSUMER QUARTERLY"  e.g. "CONS.AT.TOT.14.BS.Q", column 1 a
##                         "YYYY-Qn" period string rather than a date.
## Every answer is "BS", the balance (positive minus negative answers),
## seasonally adjusted -- read off the workbook's Index sheet, as are the
## question numbers below. "TOT" is all consumers; the archive also
## splits them by income quartile, age, education and occupation, which
## this project does not fetch.
##
## Confirmed live for Austria: every monthly question from 1995-10 to
## 2026-08 (371 months), the two quarterly questions likewise from
## 1995-Q4. Question numbers skip 10 and 13 because the Commission
## withdrew them from dissemination in July 2024 (INFO sheet).
##
## "COF", the confidence indicator (Q1 + Q2 + Q4 + Q9) / 4, is the same
## series as the main archive's "AT.CONS" (checked: identical for
## Austria), so it is NOT fetched again here -- `consumer_confidence`
## stays the one concept for it. The questions are fetched because they
## say which part of household sentiment moved, which the composite
## cannot: e.g. price expectations (Q6) and major purchases (Q8) went in
## opposite directions in 2022.
##
## The INFO sheet notes that Q7 (unemployment expectations) was not
## seasonally adjusted up to June 2009 across the archive; the Austrian
## series is published as s.a. throughout and is used as published.
ec_consumer_questions <- tibble::tribble(
  ~label,                                   ~question, ~frequency,
  "consumer_financial_situation_past",      "1",       "M",
  "consumer_financial_situation_expected",  "2",       "M",
  "consumer_economic_situation_past",       "3",       "M",
  "consumer_economic_situation_expected",   "4",       "M",
  "consumer_price_trends_past",             "5",       "M",
  "consumer_price_expectations",            "6",       "M",
  "consumer_unemployment_expectations",     "7",       "M",
  "consumer_major_purchases_now",           "8",       "M",
  "consumer_major_purchases_expected",      "9",       "M",
  "consumer_savings_expected",              "11",      "M",
  "consumer_household_finances_now",        "12",      "M",
  "consumer_home_purchase_intentions",      "14",      "Q",
  "consumer_home_improvement_intentions",   "15",      "Q"
)

#' Build the consumer-survey column name for one country's balance on one
#' question, e.g. "CONS.AT.TOT.2.BS.M"
ec_consumer_question_column <- function(ec_country2, question, frequency = "M") {
  sprintf("CONS.%s.TOT.%s.BS.%s", ec_country2, question, frequency)
}

#' Extract one country's balance on one quarterly consumer question
#'
#' The quarterly sheet labels its rows "YYYY-Qn" rather than with dates,
#' so it cannot go through `parse_ec_survey_column()`'s date parsing; the
#' periods are turned into the quarter's first day, the panel's own date
#' convention.
parse_ec_survey_quarterly_column <- function(xlsx_path, sheet, col_name, label) {
  quarterly <- tryCatch(
    suppressMessages(readxl::read_excel(xlsx_path, sheet = sheet, col_names = FALSE)),
    error = function(e) NULL
  )
  if (is.null(quarterly)) {
    warning(sprintf("[%s] Could not read the '%s' sheet from the EC survey archive", label, sheet))
    return(NULL)
  }
  header <- as.character(quarterly[1, ])
  col_idx <- which(header == col_name)
  if (length(col_idx) == 0) {
    warning(sprintf("[%s] Column '%s' not found in the EC survey archive", label, col_name))
    return(NULL)
  }
  out <- tibble::tibble(
    date = period_to_date(as.character(quarterly[[1]][-1])),
    value = suppressWarnings(as.numeric(quarterly[[col_idx[1]]][-1]))
  ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$value))
  names(out)[2] <- label
  out
}

#' Fetch one consumer-survey question's balance for an EU country
#'
#' `question` is one of `ec_consumer_questions$question`. A monthly
#' question is averaged to the panel's frequency like every other survey
#' balance; a quarterly question is only asked quarterly and so returns
#' NULL, without a warning, for a monthly panel. Returns NULL (with a
#' warning) if the country isn't an EU member, the consumer archive can't
#' be found within the lookback window, or the country's column isn't in
#' it.
fetch_ec_consumer_question <- function(country3, label, question,
                                        start_period = "1995-Q1",
                                        reference_date = Sys.Date(),
                                        landing_dir = ec_survey_landing_dir,
                                        frequency = "Q") {
  row <- ec_consumer_questions[ec_consumer_questions$question == question, ]
  if (nrow(row) != 1) {
    stop(sprintf("Unknown EC consumer survey question '%s' -- known: %s", question,
                 paste(ec_consumer_questions$question, collapse = ", ")), call. = FALSE)
  }
  asked <- row$frequency
  if (identical(asked, "Q") && identical(frequency, "M")) return(NULL)

  if (!country3 %in% eu_member_countries) {
    warning(sprintf("[%s] EC Business and Consumer Survey only covers EU member states -- '%s' is not one", label, country3))
    return(NULL)
  }
  ec_country2 <- lookup_ec_country2(country3)
  if (is.na(ec_country2)) return(NULL)

  found <- get_ec_survey_xlsx(reference_date, landing_dir = landing_dir, archive = "consumer")
  if (is.null(found)) {
    warning(sprintf("[%s] Could not find a published EC consumer survey archive (cached or live) within the lookback window", label))
    return(NULL)
  }

  col_name <- ec_consumer_question_column(ec_country2, question, asked)
  if (identical(asked, "Q")) {
    out <- parse_ec_survey_quarterly_column(found$path, "CONSUMER QUARTERLY", col_name, label)
  } else {
    out <- parse_ec_survey_column(found$path, ec_survey_archives$consumer$sheet, col_name, label)
    if (!is.null(out)) out <- aggregate_to(out, label, frequency)
  }
  if (is.null(out)) return(NULL)
  dplyr::filter(out, .data$date >= period_to_date(start_period))
}

## ---------------------------------------------------------------
## Business surveys: the individual questions of industry, services,
## retail trade and construction
## ---------------------------------------------------------------
## ADDED 2026-09-27. `all_surveys_total_sa_nace2.zip` (confirmed live:
## HTTP 200, application/zip, 5.2 MB for month "2608") sits in the same
## monthly folder as the archives above and walks back the same way. It
## bundles six workbooks -- the main indicators and one per sector,
## including the building and consumer workbooks this project already
## reads from their own archives -- and is read here for the three it
## does not: industry, services and retail trade (registered above as
## members of it, so one download caches all three). The construction
## questions below come from the building archive already cached.
##
## Every workbook uses the naming scheme of the building and consumer
## ones, `<SECTOR>.<COUNTRY>.TOT.<QUESTION>.<ANSWER>.<FREQ>`, with
## monthly questions on a "<SECTOR> MONTHLY" sheet (month-end dates) and
## quarterly ones on "<SECTOR> QUARTERLY" ("YYYY-Qn" periods). Question
## numbers and answer codes are read off each workbook's Index sheet --
## the same trap as the building archive's weather answer applies, e.g.
## "Financial" is F6S in industry but F5S in services:
##   BS     balance (positive minus negative answers), seasonally adjusted
##   F<n>S  % of firms naming factor n as limiting activity, s.a.
##   QPS    capacity utilisation in %, s.a.
##
## Confirmed live for Austria in month 2608: industry monthly Q1-Q7 and
## quarterly Q8 (six factors), Q9, Q11, Q13, Q15, Q16; services monthly
## Q1, Q2, Q3, Q5, Q6 and quarterly Q7 (six factors), Q8; retail monthly
## Q1-Q6; construction monthly Q1, Q2 (seven factors), Q3, Q4, Q5. The
## Index sheets also list industry Q10 and construction Q6 (months of
## production or work assured, QMS), which are not published for Austria
## and are left out.
##
## "COF", each sector's confidence indicator, is the main archive's
## INDU/SERV/RETA/BUIL (industrial_confidence, services_confidence,
## retail_confidence, construction_confidence) and is not fetched again,
## as with the consumer survey. Construction question 2's weather answer
## (F3S) stays construction_weather_constraint above.
ec_business_questions <- tibble::tribble(
  ~label,                                       ~archive,   ~sector, ~question, ~answer, ~frequency,
  "industry_production_past",                   "industry", "INDU",  "1",       "BS",    "M",
  "industry_order_books",                       "industry", "INDU",  "2",       "BS",    "M",
  "industry_export_order_books",                "industry", "INDU",  "3",       "BS",    "M",
  "industry_stocks_finished_products",          "industry", "INDU",  "4",       "BS",    "M",
  "industry_production_expectations",           "industry", "INDU",  "5",       "BS",    "M",
  "industry_selling_price_expectations",        "industry", "INDU",  "6",       "BS",    "M",
  "industry_employment_expectations",           "industry", "INDU",  "7",       "BS",    "M",
  "industry_limits_none",                       "industry", "INDU",  "8",       "F1S",   "Q",
  "industry_limits_demand",                     "industry", "INDU",  "8",       "F2S",   "Q",
  "industry_limits_labour",                     "industry", "INDU",  "8",       "F3S",   "Q",
  "industry_limits_material_equipment",         "industry", "INDU",  "8",       "F4S",   "Q",
  "industry_limits_other",                      "industry", "INDU",  "8",       "F5S",   "Q",
  "industry_limits_financial",                  "industry", "INDU",  "8",       "F6S",   "Q",
  "industry_production_capacity",               "industry", "INDU",  "9",       "BS",    "Q",
  "industry_new_orders_past",                   "industry", "INDU",  "11",      "BS",    "Q",
  "industry_capacity_utilization",              "industry", "INDU",  "13",      "QPS",   "Q",
  "industry_competitive_position_eu",           "industry", "INDU",  "15",      "BS",    "Q",
  "industry_competitive_position_outside_eu",   "industry", "INDU",  "16",      "BS",    "Q",
  "services_business_situation_past",           "services", "SERV",  "1",       "BS",    "M",
  "services_demand_past",                       "services", "SERV",  "2",       "BS",    "M",
  "services_demand_expected",                   "services", "SERV",  "3",       "BS",    "M",
  "services_employment_expectations",           "services", "SERV",  "5",       "BS",    "M",
  "services_price_expectations",                "services", "SERV",  "6",       "BS",    "M",
  "services_limits_none",                       "services", "SERV",  "7",       "F1S",   "Q",
  "services_limits_demand",                     "services", "SERV",  "7",       "F2S",   "Q",
  "services_limits_labour",                     "services", "SERV",  "7",       "F3S",   "Q",
  "services_limits_equipment_space",            "services", "SERV",  "7",       "F4S",   "Q",
  "services_limits_financial",                  "services", "SERV",  "7",       "F5S",   "Q",
  "services_limits_other",                      "services", "SERV",  "7",       "F6S",   "Q",
  "services_capacity_utilization",              "services", "SERV",  "8",       "QPS",   "Q",
  "retail_business_activity_past",              "retail",   "RETA",  "1",       "BS",    "M",
  "retail_stocks",                              "retail",   "RETA",  "2",       "BS",    "M",
  "retail_orders_expected",                     "retail",   "RETA",  "3",       "BS",    "M",
  "retail_business_activity_expected",          "retail",   "RETA",  "4",       "BS",    "M",
  "retail_employment_expectations",             "retail",   "RETA",  "5",       "BS",    "M",
  "retail_price_expectations",                  "retail",   "RETA",  "6",       "BS",    "M",
  "construction_activity_past",                 "building", "BUIL",  "1",       "BS",    "M",
  "construction_limits_none",                   "building", "BUIL",  "2",       "F1S",   "M",
  "construction_limits_demand",                 "building", "BUIL",  "2",       "F2S",   "M",
  "construction_limits_labour",                 "building", "BUIL",  "2",       "F4S",   "M",
  "construction_limits_material_equipment",     "building", "BUIL",  "2",       "F5S",   "M",
  "construction_limits_other",                  "building", "BUIL",  "2",       "F6S",   "M",
  "construction_limits_financial",              "building", "BUIL",  "2",       "F7S",   "M",
  "construction_order_books",                   "building", "BUIL",  "3",       "BS",    "M",
  "construction_employment_expectations",       "building", "BUIL",  "4",       "BS",    "M",
  "construction_price_expectations",            "building", "BUIL",  "5",       "BS",    "M"
)

#' Build a business-survey column name, e.g. "INDU.AT.TOT.8.F2S.Q"
ec_business_question_column <- function(ec_country2, sector, question, answer, frequency) {
  sprintf("%s.%s.TOT.%s.%s.%s", sector, ec_country2, question, answer, frequency)
}

#' The column one concept of `ec_business_questions` is read from
ec_business_question_key <- function(label, ec_country2) {
  row <- ec_business_questions[ec_business_questions$label == label, ]
  if (nrow(row) != 1) {
    stop(sprintf("Unknown EC business survey question '%s'", label), call. = FALSE)
  }
  ec_business_question_column(ec_country2, row$sector, row$question, row$answer, row$frequency)
}

#' Fetch one business-survey question for an EU country
#'
#' `label` is one of `ec_business_questions$label`. A monthly question is
#' averaged to the panel's frequency like every other survey series; a
#' quarterly one is only asked quarterly and so returns NULL, without a
#' warning, for a monthly panel. Returns NULL (with a warning) if the
#' country isn't an EU member, the archive can't be found within the
#' lookback window, or the country's column isn't in it -- the last a
#' real case: several countries' services and retail surveys start late
#' or are suspended (each workbook's INFO sheet).
fetch_ec_business_question <- function(country3, label,
                                        start_period = "1995-Q1",
                                        reference_date = Sys.Date(),
                                        landing_dir = ec_survey_landing_dir,
                                        frequency = "Q") {
  row <- ec_business_questions[ec_business_questions$label == label, ]
  if (nrow(row) != 1) {
    stop(sprintf("Unknown EC business survey question '%s' -- known: %s", label,
                 paste(ec_business_questions$label, collapse = ", ")), call. = FALSE)
  }
  if (identical(row$frequency, "Q") && identical(frequency, "M")) return(NULL)

  if (!country3 %in% eu_member_countries) {
    warning(sprintf("[%s] EC Business and Consumer Survey only covers EU member states -- '%s' is not one", label, country3))
    return(NULL)
  }
  ec_country2 <- lookup_ec_country2(country3)
  if (is.na(ec_country2)) return(NULL)

  found <- get_ec_survey_xlsx(reference_date, landing_dir = landing_dir, archive = row$archive)
  if (is.null(found)) {
    warning(sprintf("[%s] Could not find a published EC %s survey archive (cached or live) within the lookback window",
                    label, row$archive))
    return(NULL)
  }

  spec <- ec_survey_archive(row$archive)
  col_name <- ec_business_question_key(label, ec_country2)
  if (identical(row$frequency, "Q")) {
    out <- parse_ec_survey_quarterly_column(found$path, spec$quarterly_sheet, col_name, label)
  } else {
    out <- parse_ec_survey_column(found$path, spec$sheet, col_name, label)
    if (!is.null(out)) out <- aggregate_to(out, label, frequency)
  }
  if (is.null(out)) return(NULL)
  dplyr::filter(out, .data$date >= period_to_date(start_period))
}
