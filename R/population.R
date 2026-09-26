## ---------------------------------------------------------------
## population.R -- total resident population, quarterly
##
## FRED-QD carries no population series of its own, but every applied
## user of a macro panel wants one: it is the denominator that turns
## real_gdp, real_household_consumption or hours_worked into per-capita
## terms, and in a country whose population has grown by 16 percent
## since 1995 -- Austria's has, most of it through migration --
## per-capita and aggregate growth are not the same story.
##
## SOURCE HIERARCHY. Two routes, tried in this order, and NA for any
## country that neither covers:
##
## 1. Eurostat namq_10_pe ("Population and employment - quarterly
##    data"), NA_ITEM=POP_NC (total population, national concept),
##    UNIT=THS_PER (thousands of persons), S_ADJ=SCA. This is the
##    population figure of the quarterly national accounts themselves,
##    the same framework as this panel's real_gdp and hours_worked, so
##    a per-capita ratio of the two is internally consistent rather than
##    two sources glued together. VERIFIED live 2026-09-26 for AT (from
##    1995-Q1, 7,946 thousand, to 2026-Q2, 9,218 thousand) and DE (from
##    1991-Q1, to 2026-Q2). The key orders its dimensions
##    freq.unit.s_adj.na_item.geo -- the same order as namq_10_gdp, and
##    NOT the order namq_10_a10_e uses for hours worked in R/eurostat.R.
##    SCA rather than NSA only for consistency with the rest of the
##    national accounts in this panel: for Austria the two were confirmed
##    identical, since a population stock has no seasonal pattern worth
##    the name.
##
## 2. A country's own statistical office via FRED, from the short
##    explicit table `national_population` below -- deliberately not a
##    template, for the same reason as R/fred_mirror.R's
##    `national_cpi_index`: each office's series reaches FRED under its
##    own mnemonic and definition. The United States is the one entry:
##    POPTHM, the BEA's monthly total population including armed forces
##    overseas, averaged within the quarter.
##
## WHY NOT FURTHER BACK. Austria's quarterly series starts in 1995, and
## annual population (demo_pjan) reaches back to 1960. It is not
## interpolated onto the quarters in between: a quarterly figure
## invented from an annual one is indistinguishable from data once it is
## in a CSV (see scripts/build_monthly_panel.R's header, which declines
## the same thing for the same reason), and anyone who needs it can make
## it from the annual series knowing that they did.
##
## WHY NOT THE OECD MIRROR. FRED mirrors population for most countries
## only ANNUALLY (the World Bank's POPTOT{cc2}A647NWDB), which cannot
## fill a quarterly column without the interpolation declined above.
## ---------------------------------------------------------------

eurostat_population_dataflow <- "namq_10_pe"
eurostat_population_unit <- "THS_PER"   # thousands of persons
eurostat_population_na_item <- "POP_NC" # total population, national concept

national_population <- tibble::tribble(
  ~country3, ~fred_id,  ~note,
  "USA",     "POPTHM",  "BEA total population including armed forces overseas, thousands of persons, monthly from 1959-01."
)

#' Fetch quarterly total population for one EU country from Eurostat
#'
#' Returns a tibble with `date` and `label`, or NULL for a non-EU
#' country or a failed request.
fetch_eurostat_population <- function(country3, label = "population",
                                      s_adj = "SCA", start_period = "1960-Q1") {
  if (!country3 %in% eu_member_countries) return(NULL)

  geo <- lookup_ec_country2(country3)
  if (is.null(geo) || is.na(geo)) {
    warning(sprintf("[%s] No Eurostat geo code for %s", label, country3))
    return(NULL)
  }

  key <- paste("Q", eurostat_population_unit, s_adj,
               eurostat_population_na_item, geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_population_dataflow, key, start_period
  )

  txt <- tryCatch(fetch_text(url), error = function(e) {
    warning(sprintf("[%s] Eurostat population fetch errored: %s", label, conditionMessage(e)))
    NULL
  })
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat population fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat has no observations for key '%s'", label, key))
    return(NULL)
  }

  out <- parse_time_value_csv(txt, label)
  if (is.null(out)) return(NULL)

  out <- out %>%
    dplyr::mutate(date = period_to_date(.data$period)) %>%
    dplyr::select("date", dplyr::all_of(label)) %>%
    dplyr::filter(!is.na(.data[[label]])) %>%
    dplyr::arrange(.data$date)
  if (nrow(out) == 0) return(NULL)

  attr(out, "source_col") <- sprintf("%s:%s", eurostat_population_dataflow, key)
  out
}

#' Fetch a country's own population series from FRED, or NULL
#'
#' Only for countries listed in `national_population`; the source is
#' monthly and is averaged within the quarter.
fetch_national_population <- function(country3, label = "population",
                                      start_period = "1960-Q1") {
  row <- national_population[national_population$country3 == country3, ]
  if (nrow(row) != 1) return(NULL)

  df <- get_fred_series(row$fred_id[1])
  if (is.null(df)) {
    warning(sprintf("[%s] FRED fetch failed for %s", label, row$fred_id[1]))
    return(NULL)
  }

  names(df)[2] <- label
  out <- aggregate_to(df, label, "Q")
  out[[label]][is.nan(out[[label]])] <- NA_real_
  out <- out[!is.na(out[[label]]), ]
  out <- out[out$date >= period_to_date(start_period), ]

  if (nrow(out) == 0) {
    warning(sprintf("[%s] %s returned no usable observations", label, row$fred_id[1]))
    return(NULL)
  }

  attr(out, "source_col") <- row$fred_id[1]
  attr(out, "provider") <- "FRED"
  out
}

#' Fetch quarterly total population, in thousands of persons
#'
#' Tries Eurostat for EU members, then the `national_population` table.
#' The result carries `source_col` and `provider` attributes for the
#' builder's coverage report, or is NULL where neither route applies.
fetch_population <- function(country3, label = "population",
                             start_period = "1960-Q1") {
  out <- fetch_eurostat_population(country3, label = label,
                                   start_period = start_period)
  if (!is.null(out)) {
    attr(out, "provider") <- "EUROSTAT_POP"
    return(out)
  }
  fetch_national_population(country3, label = label, start_period = start_period)
}
