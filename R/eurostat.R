## ---------------------------------------------------------------
## eurostat.R -- Eurostat Quarterly National Accounts (namq_10_gdp),
## preferred anchor NIPA source for EU member states
##
## STATUS: VERIFIED 2026-08-30 against ec.europa.eu/eurostat's own SDMX
## 2.1 API (real 200 responses with current 2026-Q2 data for AT and DE).
##
## Dataflow: ESTAT:namq_10_gdp ("GDP and main components (output,
## expenditure and income) - quarterly data"). Confirmed key dimension
## order (5 segments before TIME_PERIOD): FREQ.UNIT.S_ADJ.NA_ITEM.GEO.
## UNIT = "CLV20_MEUR" (chain-linked volumes, 2020 reference year,
## million euro) for a LEVEL series comparable to OECD QNA's "LR" -- two
## older reference years (CLV10_MEUR, CLV15_MEUR) also return real data,
## but 2020 is Eurostat's current standard. S_ADJ = "SCA" (seasonally and
## calendar adjusted).
##
## NA_ITEM codes confirmed VALID FOR THIS DATAFLOW (the shared NA_ITEM
## codelist has thousands of codes from every Eurostat national-accounts
## dataset; most are NOT valid here -- confirmed by testing each one, not
## by trusting codelist membership: e.g. "B6G" IS in the shared codelist
## but returns "INVALID_QUERY_DIMENSION_VALUE" for namq_10_gdp):
##   B1GQ     - GDP                                       -> real_gdp
##   P31_S14  - Household (NOT NPISH) final consumption   -> real_household_consumption
##              (narrower than, and a closer match to FRED-QD's household-only
##              PCECC96 than, OECD QNA's sector S1M, which includes NPISH --
##              see the `concept_notes` override in build_country_panel.R)
##   P3_S13   - General government consumption expenditure -> real_govt_consumption
##   P51G     - Gross fixed capital formation               -> real_gfcf_total
##   P6       - Exports of goods and services                 -> real_exports
##   P7       - Imports of goods and services                 -> real_imports
## No quarterly household disposable income code validates against this
## dataflow (B6G and its variants are whole-economy / per-capita / growth-
## rate only) -- the same genuine gap already documented in R/oecd.R, not
## solved by switching sources; real_household_disposable_income is never
## attempted here and always falls through to OECD/IMF.
##
## GEO uses the same 2-letter codes as everywhere else in this project
## EXCEPT Greece ("EL", not "GR") -- reuses R/country_codes.R's
## `lookup_ec_country2()`, already built for this exact EU convention
## (confirmed by R/ec_survey.R).
##
## Response format: `format=SDMX-CSV` gives TIME_PERIOD/OBS_VALUE columns
## with the same names as OECD's, so this module reuses R/utils.R's
## `parse_time_value_csv()` rather than a new parser. A structurally
## invalid key (e.g. an NA_ITEM not valid for this dataflow) comes back
## as a SOAP `<S:Fault>` body, not a clean 404 -- checked for explicitly.
##
## PREFERENCE: scripts/build_country_panel.R tries Eurostat FIRST for EU
## member states (R/country_codes.R's `eu_member_countries`), falling
## back to OECD QNA (then IMF QNEA) for whatever Eurostat didn't resolve.
## Eurostat is the EU's own primary-source statistical agency and, per
## the household-consumption case above, sometimes has a closer
## conceptual match to FRED-QD than OECD's cross-country-harmonized
## sectors -- not simply "the same data, closer to home."
## ---------------------------------------------------------------

eurostat_dataflow <- "namq_10_gdp"
eurostat_unit <- "CLV20_MEUR"

eurostat_anchor_concepts <- tibble::tribble(
  ~label,                          ~na_item,
  "real_gdp",                      "B1GQ",
  "real_household_consumption",    "P31_S14",
  "real_govt_consumption",         "P3_S13",
  "real_gfcf_total",               "P51G",
  "real_exports",                  "P6",
  "real_imports",                  "P7"
)

#' Fetch one Eurostat quarterly national-accounts series
fetch_eurostat_series <- function(geo, na_item, label, s_adj = "SCA",
                                   unit = eurostat_unit, start_period = "1995-Q1") {
  tryCatch(
    fetch_eurostat_series_impl(geo, na_item, label, s_adj, unit, start_period),
    error = function(e) {
      warning(sprintf("[%s] Eurostat fetch errored unexpectedly: %s", label, conditionMessage(e)))
      NULL
    }
  )
}

fetch_eurostat_series_impl <- function(geo, na_item, label, s_adj, unit, start_period) {
  key <- paste("Q", unit, s_adj, na_item, geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_dataflow, key, start_period
  )

  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat has no observations for key '%s' (country/concept not covered by this dataflow)", label, key))
    return(NULL)
  }

  parse_time_value_csv(txt, label)
}

#' Fetch whichever anchor NIPA concepts Eurostat has for one EU country
#'
#' `labels`, if given, restricts which concepts are attempted (mirrors
#' R/oecd.R's `fetch_oecd_anchors(..., labels =)`). Returns a tibble with
#' one `period` column plus one column per concept that returned data
#' (household disposable income is never included -- see header comment),
#' or NULL if the country isn't an EU member or nothing resolved.
fetch_eurostat_anchors <- function(country3, start_period = "1995-Q1", labels = NULL) {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  concepts <- eurostat_anchor_concepts
  if (!is.null(labels)) concepts <- concepts[concepts$label %in% labels, ]
  if (nrow(concepts) == 0) return(NULL)

  results <- purrr::pmap(
    list(concepts$na_item, concepts$label),
    function(na_item, label) fetch_eurostat_series(geo, na_item, label, start_period = start_period)
  )
  names(results) <- concepts$label
  results <- purrr::compact(results)

  if (length(results) == 0) return(NULL)
  purrr::reduce(results, dplyr::full_join, by = "period") %>% dplyr::arrange(period)
}

## ---------------------------------------------------------------
## Harmonised Index of Consumer Prices (prc_hicp_midx), EU-specific
## override for `cpi_index` -- fresher than the frozen OECD-MEI-via-FRED
## CPI mirror in R/fred_mirror.R.
##
## STATUS: VERIFIED 2026-08-30 against Eurostat's SDMX 2.1 API, real 200
## response with current data for AT. Dimension order (4 key segments
## before TIME_PERIOD) confirmed via a live structure query
## (datastructure/ESTAT/prc_hicp_midx): FREQ.UNIT.COICOP.GEO.
##
## UNIT: the shared Eurostat UNIT codelist has 700+ entries, but only a
## handful validate for THIS dataflow -- the same "shared codelist,
## narrow per-dataflow subset" trap already documented above for
## NA_ITEM. Querying with UNIT left as a wildcard (confirmed live) shows
## the values that actually return data are index-base-year variants
## (I05, I96, I15, ...), NOT the "HICP2015"/"HICP2025"-named codes that
## look like the obvious choice from the codelist's own labels (those
## return HTTP 400 INVALID_QUERY_DIMENSION_VALUE). "I05" (Index,
## 2005=100) is used here, confirmed to return a complete, gap-free
## series back to well before this project's earliest anchor concepts.
##
## COICOP: "CP00" = All-items HICP -- the closest match to FRED-QD's
## CPIAUCSL (overall CPI, not a COICOP sub-category breakdown).
##
## Frequency: monthly, aggregated to quarterly by simple mean (same
## `monthly_to_quarterly()` used for consumer_confidence in
## R/ec_survey.R and defined in R/fred_mirror.R).
##
## MOTIVATION: FRED's OECD-MEI mirror (`CPALTT01{cc2}Q657N`, used for
## every country including the US) was confirmed live 2026-08-30 to be
## frozen at 2023-Q4 for Austria -- this Eurostat series extends to
## 2025-Q4 for the same country, a ~2-year improvement for EU member
## states. Not available for non-EU countries (e.g. the US), which keep
## the FRED-mirror value; scripts/build_country_panel.R tries this
## FIRST for EU members and falls back to the FRED mirror on failure,
## the same override pattern as consumer_confidence and share_price_index.
##
## EXTENDED 2026-08-30: `fetch_eurostat_hicp()` gained a `coicop`
## parameter so the same verified dataflow/key can also pull the
## standard sub-category breakdown of headline inflation -- core
## (excl. energy/food), food, energy, and services -- confirmed live for
## AT and DE with the same UNIT="I05": TOT_X_NRG_FOOD, CP01, NRG, SERV
## respectively (see `eurostat_hicp_subcategories` below). These give
## the Prices group its first sub-index breakdown; core inflation
## (TOT_X_NRG_FOOD) is the closest match to FRED-QD's CPILFESL. Food and
## energy have no direct FRED-QD mnemonic (FRED-QD's own list has no
## standalone CPI-food or CPI-energy series); services maps to
## CUSR0000SAS.
## ---------------------------------------------------------------

eurostat_hicp_dataflow <- "prc_hicp_midx"
eurostat_hicp_unit <- "I05"
eurostat_hicp_coicop <- "CP00"

eurostat_hicp_subcategories <- tibble::tribble(
  ~label,                 ~coicop,
  "core_cpi_index",       "TOT_X_NRG_FOOD",
  "food_price_index",     "CP01",
  "energy_price_index",   "NRG",
  "services_price_index", "SERV"
)

#' Fetch one Eurostat HICP series (any COICOP category, quarterly-averaged)
#' for one EU country, or NULL if the country isn't an EU member or
#' nothing resolved
fetch_eurostat_hicp <- function(country3, label = "cpi_index",
                                 start_period = "1995-Q1",
                                 unit = eurostat_hicp_unit,
                                 coicop = eurostat_hicp_coicop) {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  start_month <- format(period_to_date(start_period), "%Y-%m")
  key <- paste("M", unit, coicop, geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_hicp_dataflow, key, start_month
  )

  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat HICP fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat HICP has no observations for key '%s'", label, key))
    return(NULL)
  }

  monthly <- parse_time_value_csv(txt, label)
  if (is.null(monthly)) return(NULL)

  monthly <- monthly %>%
    dplyr::mutate(date = as.Date(paste0(.data$period, "-01"))) %>%
    dplyr::select(-period)
  monthly_to_quarterly(monthly, label)
}

## ---------------------------------------------------------------
## Labour productivity and unit labour costs (namq_10_lp_ulc),
## EU-specific override for `unit_labor_cost` -- a closer conceptual
## match to FRED-QD's ULCNFB than the OECD-MEI-via-FRED proxy in
## R/fred_mirror.R.
##
## STATUS: VERIFIED 2026-08-30 against Eurostat's SDMX 2.1 API, real 200
## responses for AT and DE. Dimension order (5 key segments before
## TIME_PERIOD) confirmed via a live structure query
## (datastructure/ESTAT/namq_10_lp_ulc): FREQ.UNIT.S_ADJ.NA_ITEM.GEO.
##
## NA_ITEM: "NULC_HW" = Nominal unit labour cost based on HOURS WORKED --
## the same hours-based construction as FRED-QD's ULCNFB (see
## `concept_group_map`'s `us_note` for unit_labor_cost), unlike the
## existing OECD-mirror proxy (`ULQEUL01{cc2}Q657S`), which is
## EMPLOYMENT-based.
##
## UNIT: confirmed live that the shared UNIT codelist's INDEX-level codes
## (e.g. "I10", index 2010=100) are only published for SOME countries --
## Austria has a complete, gap-free I10/SCA/NULC_HW series back to
## 1995-Q1, current through 2026-Q1, but the identical key for Germany
## returns a structurally valid, zero-row response (only PCH_PRE/PCH_SM,
## percentage-change variants, are published for DE at this NA_ITEM).
## This module tries "I10" only, keyed to the confirmed-for-Austria case,
## rather than guessing a per-country unit -- countries where I10 isn't
## published simply return NULL (via `parse_time_value_csv()`'s zero-row
## check) and scripts/build_country_panel.R falls back to the FRED-mirror
## proxy for them, the same "try, else fall back" pattern as the other
## EU-specific overrides in this file.
##
## Frequency: already quarterly (unlike HICP above), so no
## `monthly_to_quarterly()` aggregation step is needed.
## ---------------------------------------------------------------

eurostat_ulc_dataflow <- "namq_10_lp_ulc"
eurostat_ulc_unit <- "I10"
eurostat_ulc_na_item <- "NULC_HW"

#' Fetch the Eurostat hours-based nominal unit labour cost index for one
#' EU country, or NULL if the country isn't an EU member, or Eurostat
#' doesn't publish this NA_ITEM/UNIT combination for it
fetch_eurostat_ulc <- function(country3, label = "unit_labor_cost",
                                start_period = "1995-Q1",
                                unit = eurostat_ulc_unit) {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("Q", unit, "SCA", eurostat_ulc_na_item, geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_ulc_dataflow, key, start_period
  )

  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat ULC fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat ULC has no observations for key '%s'", label, key))
    return(NULL)
  }

  quarterly <- parse_time_value_csv(txt, label)
  if (is.null(quarterly)) return(NULL)

  quarterly %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-period)
}
