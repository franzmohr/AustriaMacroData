## ---------------------------------------------------------------
## eurostat_monthly.R -- the monthly-only Eurostat routes
##
## Three concepts that the quarterly panel takes from FRED's OECD MEI
## mirror cannot be taken from there monthly, because those mirrors are
## FROZEN. Confirmed live 2026-09-25 against real 200 responses: Austrian
## AUTPROINDMISMEI stops in 2023-10, CPALTT01ATM657N in 2024-02,
## AUTSARTMISMEI in 2024-03 and CSCICP03ATM665S in 2024-01 -- the same
## stale-mirror problem R/fred_mirror.R's header already records for the
## quarterly cpi_index and consumer_confidence, which is why those two
## are overridden there as well.
##
## (The quarterly mirrors are frozen too -- AUTPROINDQISMEI ends in
## 2024-Q1 -- so the quarterly panel's industrial_production and
## retail_sales_volume are equally stale. That is worth fixing and is not
## fixed here: this file is about the monthly panel, and widening it to
## the quarterly one would change series the quarterly panel has been
## publishing, which is a decision rather than a bug fix.)
##
## Eurostat's own short-term statistics carry all three, monthly and
## current. Dimension orders confirmed against live queries rather than
## assumed, since they differ between dataflows in this very family (see
## R/eurostat.R's header on namq_10_gdp versus namq_10_a10_e):
##
##   sts_inpr_m   freq.indic_bt.nace_r2.s_adj.unit.geo
##   sts_trtu_m   freq.indic_bt.nace_r2.s_adj.unit.geo
##   une_rt_m     freq.s_adj.age.unit.sex.geo
##
## UNIT. The short-term statistics are published as an index on
## 2021 = 100 ("I21"). The quarterly panel's mirrored industrial
## production is on a different base again, so neither panel's index is
## comparable with the other's by level -- only by growth rate. That is
## true of every rebased index and is noted here because the two panels
## share a concept label, which invites the assumption that they share a
## series. They do not.
##
## NACE. Industrial production is "B-D", mining through utilities and
## excluding construction, which is the standard "total industry"
## aggregate and what the OECD MEI mirror measures. Retail is "G47",
## retail trade excluding motor vehicles, and the indicator is VOL_SLS,
## the VOLUME of sales -- not NETTUR, which is turnover in current
## prices and would put a price index into a quantity column.
## ---------------------------------------------------------------

eurostat_sts_base <- "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data"

#' Fetch one monthly Eurostat series by a fully formed key
#'
#' Shared by the three fetchers below rather than written out three
#' times, because what differs between them is a key and a label.
fetch_eurostat_monthly_key <- function(dataflow, key, label, start_period) {
  start_month <- format(period_to_date(start_period), "%Y-%m")
  url <- sprintf("%s/%s/%s?format=SDMX-CSV&startPeriod=%s",
                 eurostat_sts_base, dataflow, key, start_month)

  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat has no observations for key '%s' in %s",
                    label, key, dataflow))
    return(NULL)
  }

  parsed <- parse_time_value_csv(txt, label)
  if (is.null(parsed)) return(NULL)

  out <- parsed %>%
    dplyr::mutate(date = as.Date(paste0(.data$period, "-01"))) %>%
    dplyr::select("date", dplyr::all_of(label)) %>%
    dplyr::arrange(.data$date)

  attr(out, "source_col") <- paste0(dataflow, ":", key)
  out
}

eurostat_inpr_dataflow <- "sts_inpr_m"
eurostat_trtu_dataflow <- "sts_trtu_m"
eurostat_une_dataflow <- "une_rt_m"

#' Monthly industrial production, total industry (Eurostat sts_inpr_m)
fetch_eurostat_industrial_production <- function(country3,
                                                 label = "industrial_production",
                                                 start_period = "1995-M01") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("M", "PRD", "B-D", "SCA", "I21", geo, sep = ".")
  fetch_eurostat_monthly_key(eurostat_inpr_dataflow, key, label, start_period)
}

#' Monthly retail trade volume of sales (Eurostat sts_trtu_m)
fetch_eurostat_retail_sales <- function(country3, label = "retail_sales_volume",
                                        start_period = "1995-M01") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("M", "VOL_SLS", "G47", "SCA", "I21", geo, sep = ".")
  fetch_eurostat_monthly_key(eurostat_trtu_dataflow, key, label, start_period)
}

#' Monthly unemployment rate, total, seasonally adjusted (Eurostat une_rt_m)
#'
#' PC_ACT is the rate as a percentage of the active population, which is
#' the same concept as the OECD MEI harmonised rate the quarterly panel
#' mirrors, so the two agree closely where they overlap.
fetch_eurostat_unemployment <- function(country3, label = "unemployment_rate",
                                        start_period = "1995-M01") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("M", "SA", "TOTAL", "PC_ACT", "T", geo, sep = ".")
  fetch_eurostat_monthly_key(eurostat_une_dataflow, key, label, start_period)
}
