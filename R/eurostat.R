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
## Harmonised Index of Consumer Prices (PRC_HICP_MINR), EU-specific
## override for `cpi_index` -- fresher than the frozen OECD-MEI-via-FRED
## CPI mirror in R/fred_mirror.R.
##
## STATUS: VERIFIED 2026-10-03 against Eurostat's SDMX 2.1 API, real 200
## responses with data through 2026-09 for AT and DE. Dimension order (4
## key segments before TIME_PERIOD) confirmed via a live structure query
## (dataflow/ESTAT/PRC_HICP_MINR/latest?references=descendants):
## FREQ.UNIT.COICOP18.GEO.
##
## WHAT WAS WRONG (found 2026-10-03): until then this module read
## prc_hicp_midx with UNIT="I05" (index 2005=100), and every HICP concept
## in every panel stopped at 2025-12 while the other monthly series ran to
## 2026-08/09. Eurostat moved the HICP to ECOICOP ver.2 and the 2025=100
## base in early 2026 and froze the old dataflow: its own dataflow list
## (dataflow/ESTAT/all) now labels it "HICP - monthly data (index)
## (1996-2025)", and both of its index units (I05, I15) end at 2025-12 for
## AT and DE. UNIT="I25" is rejected there as an invalid dimension value --
## the new base was never added to the old dataflow.
##
## HOW IT WAS FOUND: the same dataflow list shows the successor,
## PRC_HICP_MINR ("HICP - ECOICOP ver.2 - indices and rates of change,
## monthly data"). Its structure query gives a UNIT codelist of exactly
## I25, I15 and three rates of change, and a COICOP18 dimension in place
## of COICOP. Data queries, each a real 200 response for both AT and DE:
##   I25 (Index, 2025=100) -- 1996-01 through 2026-09 (2026-08 for CP01);
##   I15 (Index, 2015=100) -- also published, but one month behind I25.
## So I25 is used. Two traps for anyone extending this:
##   - All-items is COICOP18="TOTAL". The old "CP00" is not in the new
##     codelist and returns a SOAP Fault (HTTP 400) for both units.
##   - The latest month may be a flash estimate, OBS_FLAG "e" (2026-09
##     for TOTAL/TOT_X_NRG_FOOD/NRG/SERV; food has no flash). It is kept,
##     like the other flash-estimated monthly series, and is revised at
##     the next release.
##
## NO SPLICE NEEDED: the new dataflow carries the whole history at the new
## base, back to the same first month the old one had (1996-01; 1999-12
## for AT core and services), so there is no earlier old-base history to
## rescale onto it with splice_prefer(). Compared month by month over
## 1996-2025, the I25 series is the I05 series rebased: the ratio is
## constant to 3-4 digits for headline, core, energy and services. Food
## (CP01) differs by up to 0.3 percentage points in a monthly rate,
## because ECOICOP ver.2 classifies some food items differently. Eurostat
## flags the history before 2017 "d" (definition differs, a back-cast to
## the new classification) and 2017-01 "b" (break in series).
##
## COICOP: "TOTAL" = All-items HICP -- the closest match to FRED-QD's
## CPIAUCSL (overall CPI, not a COICOP sub-category breakdown).
##
## Frequency: monthly, aggregated to quarterly by simple mean (same
## `monthly_to_quarterly()` used for consumer_confidence in
## R/ec_survey.R and defined in R/fred_mirror.R).
##
## MOTIVATION: FRED's OECD-MEI mirror (`CPALTT01{cc2}Q657N`, used for
## every country including the US) was confirmed live 2026-08-30 to be
## frozen at 2023-Q4 for Austria. Not available for non-EU countries
## (e.g. the US), which keep their national index; R/panel_monthly.R
## tries this FIRST for EU members, the same override pattern as
## consumer_confidence and share_price_index.
##
## SUB-CATEGORIES: `fetch_eurostat_hicp()`'s `coicop` parameter pulls the
## standard breakdown of headline inflation -- core (excl. energy/food),
## food, energy, and services. The codes are unchanged in COICOP18 and
## were re-confirmed live 2026-10-03 against PRC_HICP_MINR/I25 for AT and
## DE: TOT_X_NRG_FOOD, CP01, NRG, SERV (see `eurostat_hicp_subcategories`
## below). Core inflation (TOT_X_NRG_FOOD) is the closest match to
## FRED-QD's CPILFESL. Food and energy have no direct FRED-QD mnemonic
## (FRED-QD's own list has no standalone CPI-food or CPI-energy series);
## services maps to CUSR0000SAS.
## ---------------------------------------------------------------

eurostat_hicp_dataflow <- "prc_hicp_minr"
eurostat_hicp_unit <- "I25"
eurostat_hicp_coicop <- "TOTAL"

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
                                 coicop = eurostat_hicp_coicop,
                                 frequency = "Q") {
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
  aggregate_to(monthly, label, frequency)
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

## ---------------------------------------------------------------
## Quarterly government finance statistics (gov_10q_ggnfa), for the
## concept `government_primary_balance_to_gdp` -- the flow companion to
## the `government_debt_to_gdp` stock from R/bis.R.
##
## STATUS: VERIFIED 2026-09-14 against Eurostat's SDMX 2.1 API, a real 200
## response for AT with data from 2001-Q1 through 2026-Q1. Dimension order
## (6 key segments before TIME_PERIOD), confirmed from the response's own
## header row: FREQ.UNIT.S_ADJ.SECTOR.NA_ITEM.GEO. UNIT = "PC_GDP"
## (percentage of GDP), SECTOR = "S13" (general government).
##
## The primary balance is not published as an NA_ITEM of its own, so it is
## built as net lending/borrowing (B9) plus interest payable (D41PAY), the
## balance before interest. Two traps, both confirmed live:
##   - the interest NA_ITEM is "D41PAY"; plain "D41" is not valid for this
##     dataflow and comes back as a SOAP Fault rather than an empty response;
##   - S_ADJ = "SCA" is published for B9 but returns zero rows for D41PAY,
##     so both components are taken NOT seasonally adjusted ("NSA"). An
##     adjusted B9 plus an unadjusted D41PAY would be neither.
## Both components come from ONE request ("B9+D41PAY", SDMX's OR operator),
## and a quarter is kept only if both are present.
##
## The ratio is to the same quarter's GDP, so a quarterly value has the
## magnitude of an annual ratio but a seasonal pattern; a four-quarter
## average is the usual way to read it.
## ---------------------------------------------------------------

eurostat_gov_dataflow <- "gov_10q_ggnfa"

#' Fetch the general-government primary balance (% of GDP, not seasonally
#' adjusted) for one EU country, or NULL if the country isn't an EU member
#' or Eurostat doesn't publish both components for it
fetch_eurostat_primary_balance <- function(country3, label = "government_primary_balance_to_gdp",
                                            start_period = "1995-Q1") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.na(geo)) return(NULL)

  key <- paste("Q", "PC_GDP", "NSA", "S13", "B9+D41PAY", geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_gov_dataflow, key, start_period
  )

  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat government finance fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat government finance has no observations for key '%s'", label, key))
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (!all(c("na_item", "TIME_PERIOD", "OBS_VALUE") %in% names(df))) {
    warning(sprintf("[%s] Eurostat government finance: unexpected response shape, inspect manually", label))
    return(NULL)
  }

  components <- df %>%
    dplyr::transmute(period = .data$TIME_PERIOD, na_item = .data$na_item,
                     value = as.numeric(.data$OBS_VALUE)) %>%
    dplyr::distinct(period, na_item, .keep_all = TRUE) %>%
    tidyr::pivot_wider(names_from = "na_item", values_from = "value")
  if (!all(c("B9", "D41PAY") %in% names(components))) {
    warning(sprintf("[%s] Eurostat did not return both B9 and D41PAY for key '%s' -- the primary balance needs both", label, key))
    return(NULL)
  }

  ## Eurostat publishes both components to one decimal, so their sum is
  ## rounded back to one decimal rather than carrying floating-point noise.
  out <- components %>%
    dplyr::filter(!is.na(.data$B9), !is.na(.data$D41PAY)) %>%
    dplyr::transmute(date = period_to_date(.data$period),
                     !!label := round(.data$B9 + .data$D41PAY, 1)) %>%
    dplyr::arrange(.data$date)
  if (nrow(out) == 0) {
    warning(sprintf("[%s] Eurostat has no quarter with both B9 and D41PAY for key '%s'", label, key))
    return(NULL)
  }
  out
}

## ---------------------------------------------------------------
## Total hours worked
##
## FRED-QD carries total hours in the nonfarm business sector (HOANBS)
## and hours per worker alongside it, and hours are the labour input
## every production-function or labour-market exercise wants: employment
## counts heads, and heads move less than hours do over a cycle because
## the adjustment runs through the intensive margin first.
##
## Eurostat's namq_10_a10_e publishes hours on the same quarterly
## national-accounts basis as the output anchors in this file, so the
## ratio of real_gdp to hours_worked is a coherent labour-productivity
## measure rather than two sources glued together. `EMP_DC` is the
## domestic-concept total -- employees and self-employed -- against
## `SAL_DC`, which counts employees only; the total is the closer match
## to FRED-QD's concept and the one a production function wants.
##
## DIMENSION ORDER. This dataflow orders its key
## freq.unit.nace_r2.s_adj.na_item.geo, which is NOT the order
## `fetch_eurostat_series_impl()` above builds for namq_10_gdp
## (freq.unit.s_adj.na_item.geo). That is why this has its own URL
## construction rather than reusing that helper: swapping the two middle
## dimensions returns HTTP 400, not an empty result, so it fails loudly
## -- but only at runtime.
## ---------------------------------------------------------------

eurostat_hours_dataflow <- "namq_10_a10_e"
eurostat_hours_unit <- "THS_HW"      # thousands of hours worked
eurostat_hours_na_item <- "EMP_DC"   # total employment, domestic concept
eurostat_hours_nace <- "TOTAL"

#' Fetch quarterly total hours worked for one EU country
#'
#' Returns a tibble with `date` and `label`, or NULL for a non-EU country
#' or a failed request. There is no FRED-mirror fallback: FRED's OECD
#' mirror carries hours per worker for a handful of countries and total
#' hours for none of them, so outside the EU this concept resolves to NA.
fetch_eurostat_hours <- function(country3, label = "hours_worked",
                                 s_adj = "SCA", start_period = "1995-Q1") {
  if (!country3 %in% eu_member_countries) return(NULL)

  geo <- lookup_ec_country2(country3)
  if (is.null(geo) || is.na(geo)) {
    warning(sprintf("[%s] No Eurostat geo code for %s", label, country3))
    return(NULL)
  }

  key <- paste("Q", eurostat_hours_unit, eurostat_hours_nace, s_adj,
               eurostat_hours_na_item, geo, sep = ".")
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/%s/%s?format=SDMX-CSV&startPeriod=%s",
    eurostat_hours_dataflow, key, start_period
  )

  txt <- tryCatch(fetch_text(url), error = function(e) {
    warning(sprintf("[%s] Eurostat hours fetch errored: %s", label, conditionMessage(e)))
    NULL
  })
  if (is.null(txt)) {
    warning(sprintf("[%s] Eurostat hours fetch failed -- URL: %s", label, url))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("S:Fault|faultstring", ignore_case = TRUE))) {
    warning(sprintf("[%s] Eurostat has no observations for key '%s'", label, key))
    return(NULL)
  }

  out <- parse_time_value_csv(txt, label)
  if (is.null(out)) return(NULL)

  # parse_time_value_csv() returns `period` plus one column already named
  # after the concept, so only the period needs turning into a date.
  out <- out %>%
    dplyr::mutate(date = period_to_date(.data$period)) %>%
    dplyr::select("date", dplyr::all_of(label)) %>%
    dplyr::arrange(.data$date)

  attr(out, "source_col") <- sprintf("%s:%s", eurostat_hours_dataflow, key)
  out
}
