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
