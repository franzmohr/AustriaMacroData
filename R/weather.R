## ---------------------------------------------------------------
## weather.R -- heating and cooling degree days, a population-weighted
## national weather aggregate, for the `heating_degree_days` and
## `cooling_degree_days` concepts (FRED-QD group "Other")
##
## WHY A WEATHER SERIES AT ALL: FRED-QD has no weather variable, but
## degree days are the standard quantitative weather input in applied
## macro -- they drive residential and industrial energy demand, gas
## consumption, construction activity and the energy trade balance, and
## they are exogenous to the economy and essentially never revised,
## which is an unusually good property for anything entering a factor
## model or VAR alongside the heavily-revised national-accounts series
## in the rest of this panel.
##
## DEFINITION: exactly Eurostat's own, so that the cross-check below is
## a like-for-like comparison rather than an approximate one. With Tm the
## daily mean 2-metre air temperature,
##   HDD = sum over days of (18 C - Tm), counted only on days where Tm <= 15 C
##   CDD = sum over days of (Tm - 21 C), counted only on days where Tm >= 24 C
## Note the deliberate asymmetry between the REFERENCE temperature (18 /
## 21) and the THRESHOLD temperature (15 / 24) -- this is Eurostat's
## definition, not the simpler single-base-temperature convention used
## in much of the US literature (base 65 F), and getting it wrong
## produces a series that still correlates well but sits at a visibly
## different level.
##
## TWO SOURCES, IN THIS ORDER:
##
## 1. Eurostat `nrg_chdd_m` -- the official, properly population-weighted
##    national figure (Eurostat aggregates gridded data up through NUTS3
##    with population weights). STATUS: VERIFIED live 2026-09-07 for AT
##    and DE: monthly, back to 1980-01, dimension order FREQ.UNIT.
##    INDIC_NRG.GEO (e.g. "M.NR.HDD.AT"). Its fatal drawback for a
##    monthly-updated panel is TIMELINESS: the response's own LAST UPDATE
##    stamp read 08/05/26 with observations ending 2025-12 -- a roughly
##    nine-month publication lag, i.e. this dataflow is refreshed about
##    once a year. It is therefore preferred where it exists but cannot
##    carry the recent quarters on its own.
##
## 2. ERA5 reanalysis via the Open-Meteo archive API -- daily mean
##    temperature for a point, computed here into degree days over a
##    population-weighted set of representative cities. STATUS: VERIFIED
##    live 2026-09-07: no API key, HTTP 200 for a single request covering
##    1960-01-01 to 2026-08-31 (24,350 daily values), and data current
##    through 2026-08-31 on 2026-09-07 -- a roughly five-day lag, versus
##    Eurostat's nine months. ERA5 itself starts 1940-01-01, comfortably
##    before this project's 1960-Q1 default start.
##
## The two are SPLICED, not chosen between: Eurostat's value is used for
## every month it publishes, and Open-Meteo fills both the pre-1980
## history and the recent tail Eurostat has not caught up with. Because
## a city-weighted average is not the same statistic as Eurostat's
## NUTS3-population-weighted one, the Open-Meteo series is first
## LEVEL-CALIBRATED to Eurostat over the overlapping months (ratio of
## sums, see `degree_day_calibration()`), so the spliced column has one
## consistent level throughout instead of a step at the handoff. This is
## the same failure mode `splice_prefer()` in R/utils.R exists to
## prevent; a dedicated calibration is used here rather than that
## function because `splice_prefer()` takes its scale factor from a
## SINGLE overlap period, which is meaningless for a series whose value
## is legitimately 0.00 for several months of every year (a quarter's
## CDD in Austria).
##
## HOW GOOD IS THE OPEN-METEO CONSTRUCTION? Measured, not assumed, over
## the full 552-month Eurostat overlap (1980-01 to 2025-12), 2026-09-07:
##   Austria HDD  corr 0.996, level ratio (own/Eurostat) 0.82
##   Austria CDD  corr 0.975, level ratio 2.94
##   Germany HDD  corr 0.999, level ratio 0.98
##   Germany CDD  corr 0.970, level ratio 1.42
## The correlations confirm the construction is right; the level ratios
## are exactly why calibration is not optional. They also show WHERE the
## city-weighting is weak: Austria's HDD sits 18% below Eurostat's
## because a handful of lowland cities under-represent a country whose
## population also lives in cold Alpine valleys, and both countries'
## CDD levels run high because cities are the warmest points in their
## own regions. `--validate`-style reassurance is not available for this
## concept, so `fetch_degree_days()` reports the measured correlation and
## calibration factor into the coverage report for every run.
##
## CITY COVERAGE IS DELIBERATELY NARROW: `weather_city_weights` below
## covers only AUT, DEU and USA -- the three countries
## scripts/update_monthly.R actually builds. Adding a country means
## adding rows to that one table, and the Eurostat cross-check reports
## immediately whether the chosen cities are good enough. Rather than
## ship a guessed single-capital-city weighting for every other country
## (which would silently produce a poor national average for large or
## climatically diverse ones), an EU country absent from the table falls
## back to Eurostat alone -- a correct series with a stale tail -- and a
## non-EU country absent from it resolves to NA, reported as such in the
## coverage report.
##
## RATE LIMITS ARE THE REAL CONSTRAINT HERE, and were confirmed the hard
## way: Open-Meteo's free archive endpoint weights a request by locations
## times days, so a multi-decade request is expensive and a multi-city
## multi-decade one very much so. Live 2026-09-07, eight cities x 46
## years in a single request returned HTTP 429, and so did the sixth of
## six single-city 1960-2026 requests issued three seconds apart. Three
## things follow, all of them load-bearing rather than defensive:
##
##   1. Cities are fetched ONE PER REQUEST, not via the API's
##      multi-coordinate form -- gentler on the weighting, and it makes a
##      failure attributable to one city rather than losing the country.
##   2. A failed request is RETRIED with a growing pause
##      (`max_attempts`/`retry_pause_seconds`), since a 429 is a
##      per-minute limit that clears on its own.
##   3. The computed monthly degree days are cached PER CITY in
##      `data/landing/` (gitignored, like the rest of that directory),
##      keyed by city and date range. Per-city rather than per-country
##      caching is what makes a rate-limited run recoverable: a USA build
##      is fifteen separate requests, and if the twelfth is refused, a
##      re-run later fetches only the three that are still missing
##      instead of starting over and spending the same budget again.
##
## The default pauses are therefore deliberately unhurried (five seconds
## between cities, retries at 30/60/90 seconds) rather than tuned for
## speed. A monthly CI run rebuilds AUT, DEU and USA on a fresh runner
## with an empty cache -- 29 requests, each covering six decades -- so
## the budget matters more there than the wall-clock time does. If the
## limit is hit anyway, nothing is silently wrong: an EU country falls
## back to Eurostat alone and the United States reports the concept as
## unresolved, both of them saying so in the coverage report.
## ---------------------------------------------------------------

open_meteo_archive_url <- "https://archive-api.open-meteo.com/v1/archive"

## ERA5's own start; a requested start before this is clamped rather than
## sent, since the API rejects out-of-range start dates outright.
open_meteo_earliest_date <- as.Date("1940-01-01")

weather_landing_dir <- "data/landing"

## Eurostat's degree-day definition (see header). Reference and threshold
## temperatures are deliberately different numbers -- this is not a typo.
hdd_reference_temp <- 18
hdd_threshold_temp <- 15
cdd_reference_temp <- 21
cdd_threshold_temp <- 24

eurostat_chdd_dataflow <- "nrg_chdd_m"

degree_day_indicators <- tibble::tribble(
  ~label,                ~indic_nrg, ~om_col,
  "heating_degree_days", "HDD",      "hdd",
  "cooling_degree_days", "CDD",      "cdd"
)

## Minimum overlapping months before a calibration factor is trusted; a
## shorter overlap is left uncalibrated (factor NA) and reported as such
## rather than rescaling a national series on a handful of months.
min_calibration_months <- 24

## Representative cities and their weights, per country.
##
## `weight` is an APPROXIMATE population in thousands -- metropolitan
## population for the USA (where city-proper figures would badly
## over-weight the Sun Belt relative to where Americans actually live)
## and city population for AUT and DEU. These are rounded, deliberately
## imprecise numbers: they exist to give a defensible SPATIAL weighting,
## not to be a demographic statistic, and only their ratios matter.
## Whether a given country's set is good enough is answered empirically
## by the Eurostat cross-check in `fetch_degree_days()`, not by the
## precision of these figures.
##
## Coordinates are city centres to two decimals; ERA5's native grid is
## 0.25 degrees, so additional precision would be discarded by the API
## anyway (confirmed live: requesting 48.21/16.37 returns 48.19/16.38,
## the containing grid cell's centre).
weather_city_weights <- tibble::tribble(
  ~country3, ~city,           ~lat,    ~lon,     ~weight,
  "AUT",     "Vienna",         48.21,   16.37,    1900,
  "AUT",     "Graz",           47.07,   15.44,     290,
  "AUT",     "Linz",           48.31,   14.29,     210,
  "AUT",     "Salzburg",       47.81,   13.04,     155,
  "AUT",     "Innsbruck",      47.27,   11.39,     130,
  "AUT",     "Klagenfurt",     46.62,   14.31,     100,

  "DEU",     "Berlin",         52.52,   13.40,    3700,
  "DEU",     "Hamburg",        53.55,    9.99,    1850,
  "DEU",     "Munich",         48.14,   11.58,    1490,
  "DEU",     "Cologne",        50.94,    6.96,    1080,
  "DEU",     "Frankfurt",      50.11,    8.68,     760,
  "DEU",     "Stuttgart",      48.78,    9.18,     630,
  "DEU",     "Duesseldorf",    51.23,    6.78,     620,
  "DEU",     "Leipzig",        51.34,   12.37,     600,

  "USA",     "New York",       40.71,  -74.01,   20000,
  "USA",     "Los Angeles",    34.05, -118.24,   13000,
  "USA",     "Chicago",        41.88,  -87.63,    9500,
  "USA",     "Dallas",         32.78,  -96.80,    7600,
  "USA",     "Houston",        29.76,  -95.37,    7100,
  "USA",     "Washington",     38.91,  -77.04,    6300,
  "USA",     "Philadelphia",   39.95,  -75.17,    6200,
  "USA",     "Miami",          25.76,  -80.19,    6100,
  "USA",     "Atlanta",        33.75,  -84.39,    6100,
  "USA",     "Boston",         42.36,  -71.06,    4900,
  "USA",     "Phoenix",        33.45, -112.07,    4900,
  "USA",     "San Francisco",  37.77, -122.42,    4700,
  "USA",     "Seattle",        47.61, -122.33,    4000,
  "USA",     "Minneapolis",    44.98,  -93.27,    3700,
  "USA",     "Denver",         39.74, -104.99,    2960
)

#' Number of days in the calendar month a (first-of-month) Date falls in
#'
#' Vectorised, and written without `seq.Date()` (which takes only a
#' scalar `from`) so it can be used inside a `dplyr::filter()` over a
#' whole column. Adding 31 days always lands in the FOLLOWING month for
#' any month start, including February in a leap year.
days_in_month <- function(month_start) {
  next_month_start <- as.Date(format(month_start + 31, "%Y-%m-01"))
  as.integer(format(next_month_start - 1, "%d"))
}

#' Build an Open-Meteo archive URL for one point and date range
open_meteo_url <- function(lat, lon, start_date, end_date) {
  sprintf(
    "%s?latitude=%.4f&longitude=%.4f&start_date=%s&end_date=%s&daily=temperature_2m_mean&timezone=UTC",
    open_meteo_archive_url, lat, lon,
    format(start_date, "%Y-%m-%d"), format(end_date, "%Y-%m-%d")
  )
}

#' Parse an Open-Meteo archive response into a daily date/temperature tibble
#'
#' Returns NULL (with a warning) on unparseable JSON, on the API's own
#' `{"error": true, "reason": ...}` envelope (which it returns with a 4xx
#' status for e.g. an out-of-range start date), or on a response carrying
#' no `daily` block at all. Days the reanalysis has no value for come
#' back as JSON nulls and are dropped here, which is what lets the
#' complete-month rule in `degree_days_monthly()` discard a partial
#' trailing month rather than under-counting it.
parse_open_meteo_daily <- function(txt, label) {
  parsed <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) {
    warning(sprintf("[%s] Could not parse the Open-Meteo response as JSON", label))
    return(NULL)
  }
  if (isTRUE(parsed$error)) {
    warning(sprintf("[%s] Open-Meteo returned an error: %s", label, parsed$reason %||% "(no reason given)"))
    return(NULL)
  }
  if (is.null(parsed$daily) || is.null(parsed$daily$time)) {
    warning(sprintf("[%s] Open-Meteo response has no 'daily' block", label))
    return(NULL)
  }

  out <- tibble::tibble(
    date  = suppressWarnings(as.Date(parsed$daily$time)),
    tmean = suppressWarnings(as.numeric(parsed$daily$temperature_2m_mean))
  ) %>%
    dplyr::filter(!is.na(.data$date), !is.na(.data$tmean))

  if (nrow(out) == 0) {
    warning(sprintf("[%s] Open-Meteo returned no usable daily temperatures", label))
    return(NULL)
  }
  out
}

#' Aggregate daily mean temperatures into monthly heating/cooling degree
#' days, using Eurostat's definition (see this file's header)
#'
#' COMPLETE MONTHS ONLY: degree days are a SUM, so a month missing days
#' is not a noisier estimate of that month's value -- it is a smaller
#' number, silently. Any month whose day count falls short of its
#' calendar length is dropped, which is what makes calling this on a
#' range ending mid-month safe.
degree_days_monthly <- function(daily) {
  daily %>%
    dplyr::mutate(
      month = as.Date(format(.data$date, "%Y-%m-01")),
      hdd = ifelse(.data$tmean <= hdd_threshold_temp, hdd_reference_temp - .data$tmean, 0),
      cdd = ifelse(.data$tmean >= cdd_threshold_temp, .data$tmean - cdd_reference_temp, 0)
    ) %>%
    dplyr::group_by(.data$month) %>%
    dplyr::summarise(
      n_days = dplyr::n(),
      hdd = sum(.data$hdd),
      cdd = sum(.data$cdd),
      .groups = "drop"
    ) %>%
    dplyr::filter(.data$n_days == days_in_month(.data$month)) %>%
    dplyr::transmute(date = .data$month, hdd = .data$hdd, cdd = .data$cdd)
}

#' Fetch and reduce one city's daily temperatures to monthly degree days
#'
#' Retries a failed request up to `max_attempts` times with a growing
#' pause, because the failure this is overwhelmingly likely to hit is a
#' transient HTTP 429 from a per-minute rate limit (see this file's
#' header). `fetch_text()` flattens every failure to NULL, so a 404 or a
#' genuine outage is retried too -- wasteful but harmless at these
#' attempt counts, and much cheaper than losing a whole country's
#' concept to one refused request.
fetch_city_degree_days <- function(lat, lon, start_date, end_date, label = "degree_days",
                                    max_attempts = 4, retry_pause_seconds = 30) {
  url <- open_meteo_url(lat, lon, start_date, end_date)
  for (attempt in seq_len(max_attempts)) {
    txt <- suppressWarnings(fetch_text(url, timeout_seconds = 120))
    if (!is.null(txt)) {
      daily <- suppressWarnings(parse_open_meteo_daily(txt, label))
      if (!is.null(daily)) return(degree_days_monthly(daily))
    }
    if (attempt < max_attempts && retry_pause_seconds > 0) {
      Sys.sleep(retry_pause_seconds * attempt)
    }
  }
  warning(sprintf("[%s] Open-Meteo fetch failed after %d attempt(s) -- URL: %s",
                  label, max_attempts, url))
  NULL
}

#' Local cache path for one city's computed monthly degree days
#'
#' Per CITY, not per country: see this file's header for why a
#' rate-limited run has to be able to resume.
degree_days_landing_path <- function(country3, city, start_date, end_date,
                                      landing_dir = weather_landing_dir) {
  slug <- tolower(gsub("[^A-Za-z0-9]+", "_", city))
  file.path(landing_dir, sprintf(
    "degree_days_%s_%s_%s_%s.csv", tolower(country3), slug,
    format(start_date, "%Y%m"), format(end_date, "%Y%m")
  ))
}

#' Population-weighted monthly degree days for one country, from ERA5 via
#' Open-Meteo
#'
#' Returns a monthly `date` + `heating_degree_days` + `cooling_degree_days`
#' tibble, or NULL (with a warning) if the country has no rows in
#' `weather_city_weights`, or if ANY of its cities fails to fetch.
#'
#' Failing the whole country on one bad city is deliberate: dropping the
#' city and renormalising would quietly return a DIFFERENT, undocumented
#' weighting under the same concept label -- the sort of silent
#' substitution this project's plausibility checks exist to catch. A hard
#' NULL instead lets `fetch_degree_days()` fall back to Eurostat (for EU
#' countries) or report the concept as unresolved.
fetch_open_meteo_degree_days <- function(country3, start_date, end_date,
                                          landing_dir = weather_landing_dir,
                                          pause_seconds = 5,
                                          max_attempts = 4,
                                          retry_pause_seconds = 30) {
  cities <- weather_city_weights[weather_city_weights$country3 == country3, ]
  if (nrow(cities) == 0) {
    warning(sprintf(
      "[degree_days] No representative cities defined for '%s' -- add rows to `weather_city_weights` in R/weather.R to enable the Open-Meteo source for it",
      country3
    ))
    return(NULL)
  }

  per_city <- vector("list", nrow(cities))
  fetched_any <- FALSE
  for (i in seq_len(nrow(cities))) {
    label <- sprintf("degree_days/%s/%s", country3, cities$city[i])
    cache_path <- degree_days_landing_path(country3, cities$city[i], start_date, end_date, landing_dir)

    monthly <- NULL
    if (file.exists(cache_path)) {
      monthly <- tryCatch(readr::read_csv(cache_path, show_col_types = FALSE),
                          error = function(e) NULL)
      if (!is.null(monthly) && nrow(monthly) == 0) monthly <- NULL
    }
    if (is.null(monthly)) {
      ## Pause BEFORE each network request rather than after, so a run
      ## that reads most of its cities from cache doesn't wait between
      ## them, and the first real request still follows any earlier one.
      if (fetched_any && pause_seconds > 0) Sys.sleep(pause_seconds)
      monthly <- fetch_city_degree_days(cities$lat[i], cities$lon[i], start_date, end_date,
                                        label, max_attempts = max_attempts,
                                        retry_pause_seconds = retry_pause_seconds)
      fetched_any <- TRUE
      if (!is.null(monthly)) {
        dir.create(landing_dir, showWarnings = FALSE, recursive = TRUE)
        readr::write_csv(monthly, cache_path)
      }
    }

    if (is.null(monthly)) {
      warning(sprintf(
        "[degree_days] '%s' failed for %s -- returning no Open-Meteo data for the whole country rather than silently reweighting the remaining cities. Cities already fetched are cached, so a re-run will only retry the missing ones.",
        cities$city[i], country3
      ))
      return(NULL)
    }
    per_city[[i]] <- dplyr::mutate(monthly, weight = cities$weight[i])
  }

  n_cities <- nrow(cities)
  out <- dplyr::bind_rows(per_city) %>%
    dplyr::group_by(.data$date) %>%
    ## Keep only months every city reported completely, so the weights
    ## are the same in every month of the resulting series.
    dplyr::filter(dplyr::n() == n_cities) %>%
    dplyr::summarise(
      heating_degree_days = sum(.data$hdd * .data$weight) / sum(.data$weight),
      cooling_degree_days = sum(.data$cdd * .data$weight) / sum(.data$weight),
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$date)

  if (nrow(out) == 0) {
    warning(sprintf("[degree_days] No complete months returned for %s", country3))
    return(NULL)
  }
  out
}

#' Fetch Eurostat's own monthly heating and cooling degree days
#'
#' Returns a monthly `date` + `heating_degree_days` + `cooling_degree_days`
#' tibble, or NULL if the country isn't an EU member or neither indicator
#' resolved. `nrg_chdd_m` also covers EFTA countries and the UK, but this
#' is gated on `eu_member_countries` for consistency with every other
#' Eurostat-sourced concept in this project.
fetch_eurostat_degree_days <- function(country3, start_period = "1980-Q1") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  start_month <- format(period_to_date(start_period), "%Y-%m")
  merged <- NULL
  for (i in seq_len(nrow(degree_day_indicators))) {
    label <- degree_day_indicators$label[i]
    key <- paste("M", "NR", degree_day_indicators$indic_nrg[i], geo, sep = ".")
    url <- sprintf(
      "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
      eurostat_chdd_dataflow, key, start_month
    )

    txt <- fetch_text(url)
    if (is.null(txt)) {
      warning(sprintf("[%s] Eurostat degree-days fetch failed -- URL: %s", label, url))
      next
    }
    if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
      warning(sprintf("[%s] Eurostat degree days has no observations for key '%s'", label, key))
      next
    }

    monthly <- parse_time_value_csv(txt, label)
    if (is.null(monthly)) next

    monthly <- monthly %>%
      dplyr::mutate(date = as.Date(paste0(.data$period, "-01"))) %>%
      dplyr::select(-"period")
    merged <- if (is.null(merged)) monthly else dplyr::full_join(merged, monthly, by = "date")
  }

  if (is.null(merged)) return(NULL)
  ## `parse_time_value_csv()` puts the value column first and `date` is
  ## derived from `period` afterwards, so without this the tibble comes
  ## back as (heating_degree_days, date, cooling_degree_days).
  merged %>%
    dplyr::select("date", dplyr::everything()) %>%
    dplyr::arrange(.data$date)
}

#' Measure how well the Open-Meteo construction reproduces Eurostat's own
#' series, and by what constant factor it is off
#'
#' Returns `list(scale, correlation, n_overlap)`. `scale` is the ratio of
#' SUMS over the overlapping months (not a mean of ratios, which a series
#' containing legitimate zeros -- every Austrian winter's CDD -- would
#' make undefined), and is NA when the overlap is shorter than
#' `min_calibration_months` or the Open-Meteo total is not positive, in
#' which case the caller leaves the series uncalibrated and says so.
degree_day_calibration <- function(om_values, es_values) {
  ok <- is.finite(om_values) & is.finite(es_values)
  n_overlap <- sum(ok)
  if (n_overlap < min_calibration_months || sum(om_values[ok]) <= 0) {
    return(list(scale = NA_real_, correlation = NA_real_, n_overlap = n_overlap))
  }
  list(
    scale = sum(es_values[ok]) / sum(om_values[ok]),
    correlation = suppressWarnings(stats::cor(om_values[ok], es_values[ok])),
    n_overlap = n_overlap
  )
}

#' Aggregate monthly columns into quarterly TOTALS, keeping complete
#' quarters only
#'
#' Degree days are an extensive quantity: a quarter's value is the sum of
#' its months, not their mean, which is why this exists alongside
#' `monthly_to_quarterly()` (R/fred_mirror.R) rather than as an `agg =
#' sum` option on it. The completeness rule is the other half of that
#' difference -- averaging two of three months is an estimate, but
#' SUMMING two of three months is simply a third too small, so an
#' incomplete quarter is dropped rather than reported.
monthly_to_quarterly_total <- function(df, cols) {
  df %>%
    dplyr::mutate(
      quarter_start = as.Date(sprintf(
        "%s-%02d-01", format(.data$date, "%Y"),
        (as.integer(format(.data$date, "%m")) - 1) %/% 3 * 3 + 1
      ))
    ) %>%
    dplyr::group_by(.data$quarter_start) %>%
    dplyr::summarise(
      n_months = dplyr::n(),
      dplyr::across(dplyr::all_of(cols), sum),
      .groups = "drop"
    ) %>%
    dplyr::filter(.data$n_months == 3) %>%
    dplyr::select(date = "quarter_start", dplyr::all_of(cols)) %>%
    dplyr::arrange(.data$date)
}

#' Fetch quarterly heating and cooling degree days for one country
#'
#' Splices Eurostat's official monthly series (preferred wherever it
#' publishes) with a level-calibrated Open-Meteo/ERA5 series covering the
#' pre-1980 history and the recent quarters Eurostat lags behind on, then
#' totals complete quarters. See this file's header for why both sources
#' are needed and why the calibration is not optional.
#'
#' Returns a `date` + `heating_degree_days` + `cooling_degree_days`
#' tibble with a "sources" attribute -- a named list of
#' `list(provider =, key =)` per concept label, ready for
#' scripts/build_country_panel.R's `concept_source` and the coverage
#' report -- or NULL if neither source resolved.
fetch_degree_days <- function(country3, start_period = "1960-Q1",
                               reference_date = Sys.Date(),
                               landing_dir = weather_landing_dir,
                               pause_seconds = 5,
                               max_attempts = 4,
                               retry_pause_seconds = 30) {
  start_date <- max(period_to_date(start_period), open_meteo_earliest_date)
  ## Last day of the month BEFORE the current one: the current month is
  ## always partial, and ERA5's own few-day lag means even the previous
  ## month can be, which `degree_days_monthly()`'s completeness rule
  ## then drops on its own.
  end_date <- as.Date(format(reference_date, "%Y-%m-01")) - 1

  es <- fetch_eurostat_degree_days(country3, start_period = start_period)
  om <- fetch_open_meteo_degree_days(country3, start_date, end_date,
                                      landing_dir = landing_dir,
                                      pause_seconds = pause_seconds,
                                      max_attempts = max_attempts,
                                      retry_pause_seconds = retry_pause_seconds)

  if (is.null(es) && is.null(om)) return(NULL)

  labels <- degree_day_indicators$label
  n_cities <- sum(weather_city_weights$country3 == country3)
  sources <- list()

  if (is.null(om)) {
    ## Two different reasons land here and they mean different things to
    ## whoever reads the coverage report: a country with no city set is a
    ## permanent, fixable gap in `weather_city_weights`, whereas a
    ## country that HAS one is a transient failure of this particular run
    ## (a rate limit, an outage) that a re-run may well fix. Reporting
    ## the first message for the second case would send a reader off to
    ## edit a table that is already correct -- observed live 2026-09-07,
    ## when a rate-limited Austrian run said exactly that.
    om_gap <- if (n_cities == 0) {
      "no Open-Meteo city set exists for this country"
    } else {
      sprintf("the Open-Meteo fetch failed for all/some of this country's %d cities on this run", n_cities)
    }
    monthly <- es
    for (lbl in labels) {
      if (!has_data(es, lbl)) next
      sources[[lbl]] <- list(
        provider = "EUROSTAT_CHDD",
        key = sprintf("nrg_chdd_m:M.NR.%s.%s (official series only -- %s, so the most recent quarters Eurostat has not published yet are absent)",
                      degree_day_indicators$indic_nrg[degree_day_indicators$label == lbl],
                      lookup_ec_country2(country3), om_gap)
      )
    }
  } else if (is.null(es)) {
    monthly <- om
    for (lbl in labels) {
      sources[[lbl]] <- list(
        provider = "OPEN_METEO",
        key = sprintf("ERA5, %d-city population-weighted (%s); UNCALIBRATED -- Eurostat nrg_chdd_m publishes no cross-check for this country",
                      n_cities, country3)
      )
    }
  } else {
    aligned <- dplyr::full_join(
      dplyr::rename_with(om, ~ paste0(.x, "_om"), dplyr::all_of(labels)),
      ## `any_of`, not `all_of`: one of the two Eurostat indicators can
      ## fail on its own (each is a separate request), and the loop below
      ## already handles a missing "_es" column by using Open-Meteo
      ## uncalibrated for that concept.
      dplyr::rename_with(es, ~ paste0(.x, "_es"), dplyr::any_of(labels)),
      by = "date"
    ) %>% dplyr::arrange(.data$date)

    monthly <- tibble::tibble(date = aligned$date)
    for (lbl in labels) {
      om_col <- paste0(lbl, "_om")
      es_col <- paste0(lbl, "_es")
      if (!es_col %in% names(aligned)) {
        monthly[[lbl]] <- aligned[[om_col]]
        sources[[lbl]] <- list(
          provider = "OPEN_METEO",
          key = sprintf("ERA5, %d-city population-weighted (%s); UNCALIBRATED -- Eurostat published no %s series for this country",
                        n_cities, country3, lbl)
        )
        next
      }

      cal <- degree_day_calibration(aligned[[om_col]], aligned[[es_col]])
      scaled_om <- if (is.na(cal$scale)) aligned[[om_col]] else aligned[[om_col]] * cal$scale
      monthly[[lbl]] <- dplyr::coalesce(aligned[[es_col]], scaled_om)
      sources[[lbl]] <- list(
        provider = "OPEN_METEO",
        key = if (is.na(cal$scale)) {
          sprintf("ERA5, %d-city population-weighted, spliced with Eurostat nrg_chdd_m; UNCALIBRATED (only %d overlapping months, below the %d-month minimum)",
                  n_cities, cal$n_overlap, min_calibration_months)
        } else {
          sprintf("ERA5, %d-city population-weighted, spliced with Eurostat nrg_chdd_m and level-calibrated to it (x%.3f, corr %.3f over %d months)",
                  n_cities, cal$scale, cal$correlation, cal$n_overlap)
        }
      )
    }
  }

  present <- intersect(labels, names(monthly))
  present <- present[vapply(present, function(l) any(!is.na(monthly[[l]])), logical(1))]
  if (length(present) == 0) return(NULL)

  quarterly <- monthly_to_quarterly_total(monthly[, c("date", present)], present) %>%
    dplyr::filter(.data$date >= period_to_date(start_period))
  if (nrow(quarterly) == 0) return(NULL)

  attr(quarterly, "sources") <- sources[present]
  quarterly
}
