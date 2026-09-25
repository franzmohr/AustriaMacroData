## ---------------------------------------------------------------
## eurostat_sts.R -- Eurostat's short-term statistics
##
## Industrial production, retail trade and the unemployment rate, at
## whichever frequency the panel being built needs.
##
## WHY THESE THREE ARE NOT TAKEN FROM THE OECD MEI MIRROR. Because that
## mirror is FROZEN for them. Confirmed live 2026-09-25 against real 200
## responses, Austrian series:
##
##   AUTPROINDMISMEI   ends 2023-10      AUTPROINDQISMEI   ends 2024-Q1
##   AUTSARTMISMEI     ends 2024-03      AUTSARTQISMEI     ends 2024-Q1
##   CPALTT01ATM657N   ends 2024-02      CSCICP03ATM665S   ends 2024-01
##
## R/fred_mirror.R's header already recorded this for the quarterly
## cpi_index and consumer_confidence, which is why those two were
## overridden long before this file existed. Industrial production and
## retail sales have the same problem and had no override, so both
## panels were carrying series that stopped roughly two and a half years
## before every other concept in them -- which silently truncates any
## model estimated on the panel, since a VAR can only use the sample its
## shortest series allows.
##
## Eurostat publishes all three, monthly and quarterly, and current.
## Dimension orders confirmed against live queries rather than assumed,
## since they differ between dataflows in this very family (see
## R/eurostat.R's header on namq_10_gdp versus namq_10_a10_e):
##
##   sts_inpr_m / sts_inpr_q   freq.indic_bt.nace_r2.s_adj.unit.geo
##   sts_trtu_m / sts_trtu_q   freq.indic_bt.nace_r2.s_adj.unit.geo
##   une_rt_m                  freq.s_adj.age.unit.sex.geo
##
## The unemployment rate is MONTHLY ONLY here: une_rt_q exists as a
## dataflow but the key above returns a SOAP fault for it (confirmed
## live), and the quarterly panel does not need it -- its OECD MEI
## mirror, unlike the two above, is still being updated.
##
## UNIT. The short-term statistics are published as an index on
## 2021 = 100 ("I21"), and the mirrors they replace are on other bases,
## so the mirror's earlier history is rescaled at the overlap rather
## than concatenated. The two panels' index levels remain incomparable
## with each other; their growth rates are what travel.
##
## NACE. Industrial production is "B-D", mining through utilities and
## excluding construction, which is the standard "total industry"
## aggregate and what the OECD MEI mirror measures. Retail is "G47",
## retail trade excluding motor vehicles, and the indicator is VOL_SLS,
## the VOLUME of sales -- not NETTUR, which is turnover in current
## prices and would put a price index into a quantity column.
## ---------------------------------------------------------------

eurostat_sts_base <- "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data"

#' Fetch one Eurostat short-term-statistics series by a fully formed key
#'
#' Shared by the three fetchers below rather than written out three
#' times, because what differs between them is a key and a label.
#'
#' Eurostat writes a monthly period as "2024-01" and a quarterly one as
#' "2024-Q1". Only the second is what `period_to_date()` reads, so the
#' two are converted separately here rather than through one call that
#' would return NA for half the rows it was given.
fetch_eurostat_sts_key <- function(dataflow, key, label, start_period, frequency) {
  check_frequency(frequency)
  start <- if (identical(frequency, "M")) {
    format(period_to_date(start_period), "%Y-%m")
  } else {
    as_period(start_period, "Q")
  }
  url <- sprintf("%s/%s/%s?format=SDMX-CSV&startPeriod=%s",
                 eurostat_sts_base, dataflow, key, start)

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

  dates <- if (identical(frequency, "M")) {
    as.Date(paste0(parsed$period, "-01"))
  } else {
    period_to_date(parsed$period)
  }

  out <- parsed
  out$date <- dates
  out <- out[!is.na(out$date), c("date", label)]
  out <- out[order(out$date), ]

  if (nrow(out) == 0) {
    warning(sprintf("[%s] Eurostat returned no usable observations for '%s'", label, key))
    return(NULL)
  }

  attr(out, "source_col") <- paste0(dataflow, ":", key)
  tibble::as_tibble(out)
}

#' The dataflow and key-leading frequency segment for one frequency
sts_dataflow <- function(stem, frequency) {
  paste0(stem, if (identical(frequency, "M")) "_m" else "_q")
}

#' Industrial production, total industry (Eurostat sts_inpr_m / sts_inpr_q)
fetch_eurostat_industrial_production <- function(country3,
                                                 label = "industrial_production",
                                                 start_period = "1995-M01",
                                                 frequency = "M") {
  check_frequency(frequency)
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste(frequency, "PRD", "B-D", "SCA", "I21", geo, sep = ".")
  fetch_eurostat_sts_key(sts_dataflow("sts_inpr", frequency), key, label,
                         start_period, frequency)
}

#' Retail trade volume of sales (Eurostat sts_trtu_m / sts_trtu_q)
fetch_eurostat_retail_sales <- function(country3, label = "retail_sales_volume",
                                        start_period = "1995-M01",
                                        frequency = "M") {
  check_frequency(frequency)
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste(frequency, "VOL_SLS", "G47", "SCA", "I21", geo, sep = ".")
  fetch_eurostat_sts_key(sts_dataflow("sts_trtu", frequency), key, label,
                         start_period, frequency)
}

#' Unemployment rate, total, seasonally adjusted (Eurostat une_rt_m)
#'
#' PC_ACT is the rate as a percentage of the active population, the same
#' concept as the OECD MEI harmonised rate the quarterly panel mirrors --
#' for Austria the two agree to the last decimal over all 379 months they
#' share, which is a good sign that FRED is mirroring this very series.
#'
#' Monthly only, deliberately: see the module header.
fetch_eurostat_unemployment <- function(country3, label = "unemployment_rate",
                                        start_period = "1995-M01",
                                        frequency = "M") {
  check_frequency(frequency)
  if (!identical(frequency, "M")) {
    stop("Eurostat's une_rt_m is published monthly only; the quarterly panel ",
         "takes the unemployment rate from its OECD MEI mirror, which is current.",
         call. = FALSE)
  }
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("M", "SA", "TOTAL", "PC_ACT", "T", geo, sep = ".")
  fetch_eurostat_sts_key("une_rt_m", key, label, start_period, "M")
}
