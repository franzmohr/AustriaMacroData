## ---------------------------------------------------------------
## employment.R -- persons employed, quarterly
##
## The headcount of the national accounts: everyone with a job, employees
## and self-employed together. The panel's labour-market block otherwise
## has a rate (unemployment_rate, employment_rate) and an input
## (hours_worked) but no level of employment, which is what employment
## growth, labour productivity per person and an Okun's law regression
## need.
##
## SOURCE HIERARCHY. Two routes, tried in this order, and NA for any
## country that neither covers:
##
## 1. Eurostat namq_10_pe, NA_ITEM=EMP_DC (total employment, domestic
##    concept: jobs located in the country, whoever holds them),
##    UNIT=THS_PER, S_ADJ=SCA -- the dataflow R/population.R reads
##    population from, so the fetch is shared with it
##    (fetch_eurostat_namq_10_pe()) and the key has the same dimension
##    order. Domestic rather than national concept (EMP_NC, residents
##    wherever they work) because that is the concept of this panel's
##    real_gdp and hours_worked, so output per person and hours per person
##    are ratios within one framework. VERIFIED live 2026-10-08 for AT
##    (from 1995-Q1, 3,574 thousand, to 2026-Q2, 4,727 thousand) and DE
##    (from 1991-Q1, 39,188 thousand, to 2026-Q2, 45,696 thousand). SCA
##    rather than NSA, unlike population: employment has a seasonal
##    pattern (Austria's NSA 1995-Q1 is 3,513 thousand against 3,574 SCA).
##
## 2. A country's own statistical office via FRED, from the explicit
##    table `national_employment` below, for the reason R/population.R
##    gives for `national_population`. The United States is the one entry:
##    PAYEMS, the BLS establishment survey's total nonfarm payroll
##    employment, monthly from 1939, averaged within the quarter. It is
##    FRED-QD's own series and counts jobs where they are, as EMP_DC does,
##    but it excludes the self-employed and farm workers, so its level is
##    below a national-accounts headcount. VERIFIED live 2026-10-08
##    (2026-09: 159,044 thousand).
##
## WHY NOT FURTHER BACK. As for population: Austria's quarterly series
## starts in 1995, and the annual series before it is not interpolated
## onto quarters.
## ---------------------------------------------------------------

eurostat_employment_na_item <- "EMP_DC" # total employment, domestic concept

national_employment <- tibble::tribble(
  ~country3, ~fred_id,  ~note,
  "USA",     "PAYEMS",  "BLS total nonfarm payroll employment, thousands of persons, monthly from 1939-01."
)

#' Fetch quarterly persons employed for one EU country from Eurostat
#'
#' Returns a tibble with `date` and `label`, or NULL for a non-EU
#' country or a failed request.
fetch_eurostat_employment <- function(country3, label = "employment",
                                      s_adj = "SCA", start_period = "1960-Q1") {
  fetch_eurostat_namq_10_pe(country3, label = label,
                            na_item = eurostat_employment_na_item,
                            what = "employment", s_adj = s_adj,
                            start_period = start_period)
}

#' Fetch a country's own employment series from FRED, or NULL
#'
#' Only for countries listed in `national_employment`; the source is
#' monthly and is averaged within the quarter.
fetch_national_employment <- function(country3, label = "employment",
                                      start_period = "1960-Q1") {
  row <- national_employment[national_employment$country3 == country3, ]
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

#' Fetch quarterly persons employed, in thousands of persons
#'
#' Tries Eurostat for EU members, then the `national_employment` table.
#' The result carries `source_col` and `provider` attributes for the
#' builder's coverage report, or is NULL where neither route applies.
fetch_employment <- function(country3, label = "employment",
                             start_period = "1960-Q1") {
  out <- fetch_eurostat_employment(country3, label = label,
                                   start_period = start_period)
  if (!is.null(out)) {
    attr(out, "provider") <- "EUROSTAT_EMP"
    return(out)
  }
  fetch_national_employment(country3, label = label, start_period = start_period)
}
