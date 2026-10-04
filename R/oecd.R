## ---------------------------------------------------------------
## oecd.R -- OECD Quarterly National Accounts (QNA), SDMX REST API
##
## STATUS: VERIFIED 2026-08-30. Dimension order and every code below
## were confirmed live against sdmx.oecd.org (dataflow structure
## queries + real data pulls for DEU and USA), not guessed. See
## README.md for the verification trail.
##
## Dataflow: OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA (agency OECD.SDD.NAD)
## Confirmed key dimension order (13 segments before TIME_PERIOD):
##   FREQ.ADJUSTMENT.REF_AREA.SECTOR.COUNTERPART_SECTOR.TRANSACTION.
##   INSTR_ASSET.ACTIVITY.EXPENDITURE.UNIT_MEASURE.PRICE_BASE.
##   TRANSFORMATION.TABLE_IDENTIFIER
## This differs from build_country_nipa_dataset.R's original guess
## (DSD_NAMAIN10@DF_TABLE1_EXPENDITURE, 12 segments, wrong dimension
## names/order) -- that dataflow turned out to be real but structured
## differently; DF_QNA is the one this project's own earlier scripts
## (scripts/01-OECD-Codes.R) had already hand-verified for Austria, so
## it's reused and extended here rather than the untested guess.
## ---------------------------------------------------------------

oecd_qna_dims <- c("FREQ", "ADJUSTMENT", "REF_AREA", "SECTOR", "COUNTERPART_SECTOR",
                    "TRANSACTION", "INSTR_ASSET", "ACTIVITY", "EXPENDITURE",
                    "UNIT_MEASURE", "PRICE_BASE", "TRANSFORMATION", "TABLE_IDENTIFIER")

#' The 7 FRED-QD "anchor" NIPA concepts and their verified OECD QNA codes
#'
#' All six rows except household disposable income were fetched with HTTP 200
#' and real observations for both DEU and USA on 2026-08-30 (see README).
#' `price_base` is "LR" (chain-linked volume) for every real/volume concept.
oecd_anchor_concepts <- tibble::tribble(
  ~label,                              ~sector, ~counterpart_sector, ~transaction, ~price_base, ~table_id,
  "real_gdp",                          "S1",    "",                  "B1GQ",       "LR",        "T0102",
  "real_household_consumption",        "S1M",   "",                  "P3",         "LR",        "T0102",
  "real_govt_consumption",             "S13",   "",                  "P3",         "LR",        "T0102",
  "real_gfcf_total",                   "",      "",                  "P51G",       "LR",        "T0102",
  "real_exports",                      "S1",    "",                  "P6",         "LR",        "T0102",
  "real_imports",                      "S1",    "",                  "P7",         "LR",        "T0102"
)

#' Household disposable income, from the OECD quarterly sector accounts
##
## Until 2026-10 this concept was requested from DF_QNA_INC_SAV, which
## carries the total economy (S1) only and no household sector, so it was
## NA for the USA and most other countries. The quarterly sector accounts,
## DSD_NASEC1@DF_QSA, do have it: gross disposable income (B6G) of
## households and NPISH (S1M), resources side ("C"), current prices,
## seasonally adjusted, table T0801. Verified live 2026-10-04 for the USA
## from 1947-Q1 to 2026-Q2. It is published at current prices only, so
## it is deflated by the implicit deflator of household and NPISH final
## consumption from DF_QNA (S1M P3, current prices over chain-linked
## volume, both at the same annualised rate, which cancels) -- the
## construction of FRED-QD's DPIC96, and of the Eurostat series EU
## members take this concept from (R/eurostat.R
## fetch_eurostat_disposable_income()). B6G itself is a quarterly level,
## as Eurostat's is, not an annual rate.
oecd_qsa_dims <- c("FREQ", "ADJUSTMENT", "REF_AREA", "SECTOR", "COUNTERPART_SECTOR",
                   "ACCOUNTING_ENTRY", "TRANSACTION", "INSTR_ASSET", "EXPENDITURE",
                   "UNIT_MEASURE", "VALUATION", "PRICE_BASE", "TRANSFORMATION",
                   "TABLE_IDENTIFIER")

build_oecd_disposable_income_key <- function(country) {
  dims <- c(FREQ = "Q", ADJUSTMENT = "Y", REF_AREA = country, SECTOR = "S1M",
            COUNTERPART_SECTOR = "S1", ACCOUNTING_ENTRY = "C", TRANSACTION = "B6G",
            INSTR_ASSET = "", EXPENDITURE = "", UNIT_MEASURE = "XDC", VALUATION = "S",
            PRICE_BASE = "V", TRANSFORMATION = "N", TABLE_IDENTIFIER = "T0801")
  build_sdmx_key(dims[oecd_qsa_dims])
}

#' Fetch real household disposable income for one country from the OECD
#' quarterly sector accounts, deflated by the household consumption
#' deflator; NULL (with a warning) where any of the three parts is missing
fetch_oecd_disposable_income <- function(country, start_period = "1995-Q1") {
  label <- "real_household_disposable_income"
  nominal <- fetch_oecd_series_impl_url(
    paste0("https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NASEC1@DF_QSA,/",
           build_oecd_disposable_income_key(country),
           "?format=csvfilewithlabels&startPeriod=", start_period),
    "disposable_income_nominal", build_oecd_disposable_income_key(country)
  )
  if (is.null(nominal)) return(NULL)
  ## The deflator's two parts, both at the annualised rate ("LA"), the
  ## only one DF_QNA publishes the volume at.
  consumption <- function(price_base, name) {
    key <- build_oecd_qna_key(country, "S1M", "", "P3", price_base = price_base,
                              transformation = "LA")
    fetch_oecd_series_impl_url(
      paste0("https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA,/", key,
             "?format=csvfilewithlabels&startPeriod=", start_period),
      name, key
    )
  }
  cp <- consumption("V", "consumption_current")
  if (is.null(cp)) return(NULL)
  vol <- consumption("LR", "consumption_volume")
  if (is.null(vol)) return(NULL)
  out <- dplyr::inner_join(nominal, cp, by = "period") %>%
    dplyr::inner_join(vol, by = "period") %>%
    dplyr::transmute(
      period = .data$period,
      !!label := .data$disposable_income_nominal /
        (.data$consumption_current / .data$consumption_volume)
    ) %>%
    dplyr::filter(is.finite(.data[[label]])) %>%
    dplyr::arrange(.data$period)
  if (nrow(out) == 0) {
    warning(sprintf("[%s] OECD disposable income and the consumption deflator do not overlap for %s", label, country))
    return(NULL)
  }
  out
}

build_oecd_qna_key <- function(country, sector, counterpart_sector, transaction,
                                price_base = "LR", table_id = "T0102",
                                adjustment = "Y", transformation = "") {
  ## INSTR_ASSET/ACTIVITY/EXPENDITURE left blank (wildcard) -- this exact
  ## pattern is what was verified end-to-end: it's what the CLI actually
  ## used to pull real 200-with-data responses for all 6 anchors for both
  ## DEU and USA (see output/*_panel.csv). OECD's API treats an empty key
  ## segment as equivalent to the explicit "_Z" (not applicable) code for
  ## these dimensions.
  dims <- c(FREQ = "Q", ADJUSTMENT = adjustment, REF_AREA = country, SECTOR = sector,
            COUNTERPART_SECTOR = counterpart_sector, TRANSACTION = transaction,
            INSTR_ASSET = "", ACTIVITY = "", EXPENDITURE = "", UNIT_MEASURE = "XDC",
            PRICE_BASE = price_base, TRANSFORMATION = transformation, TABLE_IDENTIFIER = table_id)
  build_sdmx_key(dims[oecd_qna_dims])
}

#' Fetch one OECD QNA series
fetch_oecd_series <- function(country, sector, counterpart_sector, transaction, label,
                               dataflow = "OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA",
                               price_base = "LR", table_id = "T0102",
                               start_period = "1995-Q1") {
  tryCatch(
    fetch_oecd_series_impl(country, sector, counterpart_sector, transaction, label,
                            dataflow, price_base, table_id, start_period),
    error = function(e) {
      warning(sprintf("[%s] OECD fetch errored unexpectedly: %s", label, conditionMessage(e)))
      NULL
    }
  )
}

fetch_oecd_series_impl <- function(country, sector, counterpart_sector, transaction, label,
                                    dataflow, price_base, table_id, start_period) {
  key <- build_oecd_qna_key(country, sector, counterpart_sector, transaction,
                             price_base = price_base, table_id = table_id)
  url <- paste0(
    "https://sdmx.oecd.org/public/rest/data/", dataflow, ",/", key,
    "?format=csvfilewithlabels&startPeriod=", start_period
  )
  fetch_oecd_series_impl_url(url, label, key)
}

fetch_oecd_series_impl_url <- function(url, label, key) {
  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] OECD fetch failed -- URL: %s", label, url))
    return(NULL)
  }

  if (stringr::str_detect(txt, stringr::regex("NoResultsFound|NoRecordsFound", ignore_case = TRUE))) {
    warning(sprintf("[%s] OECD has no observations for key '%s' (country not covered for this concept)", label, key))
    return(NULL)
  }
  if (stringr::str_detect(txt, stringr::regex("exceeded the number of requests", ignore_case = TRUE))) {
    warning(sprintf("[%s] OECD API rate limit hit (HTTP 429) -- wait before retrying, see https://data-explorer.oecd.org", label))
    return(NULL)
  }

  parse_time_value_csv(txt, label)
}

#' Fetch anchor NIPA concepts for one country from OECD QNA
#'
#' Returns a tibble with one `period` column plus one column per concept
#' that returned data. Concepts with no OECD coverage for this country are
#' silently dropped (with a warning already issued by fetch_oecd_series) --
#' the IMF fallback in R/imf.R is the next step for those.
#'
#' `labels`, if given, restricts which concepts are fetched at all (rather
#' than fetching all 7 and discarding some) -- used by
#' scripts/build_country_panel.R so that EU countries, which try Eurostat
#' first (R/eurostat.R), only ask OECD for whatever Eurostat didn't
#' resolve, instead of re-requesting concepts already in hand (OECD's data
#' endpoint rate-limits under moderate volume -- see README -- so not
#' making a redundant request matters in practice, not just in principle).
fetch_oecd_anchors <- function(country, start_period = "1995-Q1", labels = NULL) {
  concepts <- oecd_anchor_concepts
  if (!is.null(labels)) concepts <- concepts[concepts$label %in% labels, ]

  results <- purrr::pmap(
    list(concepts$sector, concepts$counterpart_sector,
         concepts$transaction, concepts$label),
    function(sector, counterpart_sector, transaction, label) {
      fetch_oecd_series(country, sector, counterpart_sector, transaction, label,
                         start_period = start_period)
    }
  )
  names(results) <- concepts$label
  results <- purrr::compact(results)

  if (is.null(labels) || "real_household_disposable_income" %in% labels) {
    disp <- tryCatch(
      fetch_oecd_disposable_income(country, start_period = start_period),
      error = function(e) {
        warning(sprintf("[real_household_disposable_income] OECD fetch errored unexpectedly: %s",
                        conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(disp)) results[["real_household_disposable_income"]] <- disp
  }

  if (length(results) == 0) return(NULL)
  purrr::reduce(results, dplyr::full_join, by = "period") %>% dplyr::arrange(period)
}
