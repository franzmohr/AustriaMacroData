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

#' Household disposable income -- STATUS: VERIFIED ABSENT for most countries
##
## Checked live via OECD's SDMX `availableconstraint` endpoint: quarterly
## gross disposable income (transaction B6G) in dataflow DF_QNA_INC_SAV is
## published for only 11 countries (AUS, BRA, CAN, CHL, EST, GRC, HUN, LTU,
## LUX, LVA, ZAF) and NOT for USA, DEU, FRA, GBR or AUT -- confirmed via
## zero-observation responses, not a guess. Also, COUNTERPART_SECTOR must be
## "S1" (not blank) in this dataflow, and PRICE_BASE only has "L"/"V" codes
## (not "LR"). Included as a best-effort attempt; expect NULL for most
## countries, which is correct behavior, not a bug.
oecd_disposable_income_dims <- list(
  dataflow = "OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA_INC_SAV",
  sector = "S1", counterpart_sector = "S1", transaction = "B6G",
  price_base = "V", table_id = "T0107"
)

build_oecd_qna_key <- function(country, sector, counterpart_sector, transaction,
                                price_base = "LR", table_id = "T0102",
                                adjustment = "Y") {
  ## INSTR_ASSET/ACTIVITY/EXPENDITURE left blank (wildcard) -- this exact
  ## pattern is what was verified end-to-end: it's what the CLI actually
  ## used to pull real 200-with-data responses for all 6 anchors for both
  ## DEU and USA (see output/*_panel.csv). OECD's API treats an empty key
  ## segment as equivalent to the explicit "_Z" (not applicable) code for
  ## these dimensions.
  dims <- c(FREQ = "Q", ADJUSTMENT = adjustment, REF_AREA = country, SECTOR = sector,
            COUNTERPART_SECTOR = counterpart_sector, TRANSACTION = transaction,
            INSTR_ASSET = "", ACTIVITY = "", EXPENDITURE = "", UNIT_MEASURE = "XDC",
            PRICE_BASE = price_base, TRANSFORMATION = "", TABLE_IDENTIFIER = table_id)
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
    disp <- with(oecd_disposable_income_dims,
      fetch_oecd_series(country, sector, counterpart_sector, transaction,
                         "real_household_disposable_income",
                         dataflow = dataflow, price_base = price_base,
                         table_id = table_id, start_period = start_period)
    )
    if (!is.null(disp)) results[["real_household_disposable_income"]] <- disp
  }

  if (length(results) == 0) return(NULL)
  purrr::reduce(results, dplyr::full_join, by = "period") %>% dplyr::arrange(period)
}
