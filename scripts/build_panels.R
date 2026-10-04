#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_panels.R -- CLI entrypoint: one fetch, three panels
##
## Fetches every concept once, at the frequency its source publishes it
## (R/panel_monthly.R, R/panel_quarterly.R), and writes:
##
##   output/<cc>_monthly_panel.csv   FRED-MD style: the monthly concepts
##   output/<cc>_panel.csv           FRED-QD style: the quarterly concepts
##                                   plus the monthly ones aggregated to
##                                   quarters by their own rule -- summed
##                                   for flows, averaged otherwise
##   output/<cc>_mixed_panel.csv     EA-MD-QD style: every concept on one
##                                   monthly index, quarterly values in the
##                                   first month of their quarter
##   output/<cc>_metadata.csv        per concept: frequency, aggregation,
##                                   unit, seasonal adjustment, class,
##                                   FRED (1-7) and EA-MD-QD light/heavy
##                                   (0-5) transformation codes, source
##   output/<cc>_dummies_monthly.csv   policy-event dummies (R/dummies.R),
##   output/<cc>_dummies_quarterly.csv where the country has any
##   output/<cc>_coverage.json, <cc>_monthly_coverage.json
##   docs/data_sources.csv, docs/data_sources_monthly.csv,
##   docs/concept_dictionary.csv, docs/policy_events.csv
##
## Usage:
##   Rscript scripts/build_panels.R --country AUT
##   Rscript scripts/build_panels.R --country USA --validate
##
## WHY ONE BUILDER. Until 2026-10 a quarterly and a monthly builder each
## fetched every concept for itself, so the two panels "shared labels, not
## series": industrial production came from sts_inpr_q in one and
## sts_inpr_m in the other, the share price index from the ATX in one and
## an OECD mirror in the other, interest rates from different FRED mirror
## ids. Now a monthly concept has one source, and its quarters are made
## from its months. scripts/build_country_panel.R and
## scripts/build_monthly_panel.R still work; both run this script.
## ---------------------------------------------------------------

suppressPackageStartupMessages({
  library(httr); library(jsonlite); library(readr); library(dplyr)
  library(purrr); library(tidyr); library(stringr); library(tibble)
  library(optparse)
})

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m)) return(normalizePath(sub("^--file=", "", args[m[1]])))
  normalizePath(sys.frames()[[1]]$ofile)
}
project_root <- dirname(dirname(this_file()))
for (f in list.files(file.path(project_root, "R"), full.names = TRUE, pattern = "[.]R$")) {
  source(f)
}

option_list <- list(
  make_option("--country", type = "character", default = NULL,
              help = "ISO-3166 alpha-3 country code, e.g. AUT, DEU, USA [required]"),
  make_option("--start-period", type = "character", default = "1960-M01", dest = "start_period",
              help = "First period to fetch, YYYY-Mnn or YYYY-Qn [default %default]"),
  make_option("--fred-country2", type = "character", default = NULL, dest = "fred_country2",
              help = "FRED's 2-letter OECD-mirror country code, if not in the built-in table"),
  make_option("--validate", action = "store_true", default = FALSE,
              help = "Cross-check the national-accounts series against the real FRED-QD file (USA only)"),
  make_option("--output-dir", type = "character", default = "output", dest = "output_dir",
              help = "Directory to write the panels, metadata and coverage reports into [default %default]"),
  make_option("--fred-qd-vintage", type = "character", default = "2026-07", dest = "fred_qd_vintage",
              help = "FRED-QD monthly vintage to validate against, format YYYY-MM [default %default]")
)
opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$country)) stop("--country is required, e.g. --country AUT", call. = FALSE)
country <- toupper(opt$country)
start_m <- as_period(opt$start_period, "M")
start_q <- as_period(opt$start_period, "Q")
dir.create(opt$output_dir, showWarnings = FALSE, recursive = TRUE)
country2 <- if (!is.null(opt$fred_country2)) opt$fred_country2 else lookup_country2(country)
out_path <- function(suffix) file.path(opt$output_dir, paste0(tolower(country), suffix))

## The dictionary and the event table, exported for non-R tooling (see
## R/concept_dictionary.R and R/dummies.R). No API calls involved.
readr::write_csv(concept_dictionary, file.path(project_root, "docs", "concept_dictionary.csv"), na = "")
readr::write_csv(policy_events, file.path(project_root, "docs", "policy_events.csv"), na = "")

monthly_cols <- concept_dictionary$label[concept_dictionary$frequency == "M"]
quarterly_cols <- concept_dictionary$label[concept_dictionary$frequency == "Q"]
all_cols <- concept_dictionary$label
message("Building panels for ", country, " from ", start_m, ": ", length(monthly_cols),
        " concepts monthly at source, ", length(quarterly_cols), " quarterly.")

## =====================================================================
## 1. Fetch, once per concept
## =====================================================================
monthly_fetch <- fetch_monthly_concepts(country, start_m, country2)
quarterly_fetch <- fetch_quarterly_native_concepts(country, start_q, country2)
concept_source <- c(monthly_fetch$concept_source, quarterly_fetch$concept_source)

## =====================================================================
## 2. The three panels
##
##    Every file has the same columns in the same order for every
##    country, resolved or not, so that changing --country returns a
##    like-for-like file; and every file is sorted by date, since a
##    full_join appends the periods its left side lacks.
## =====================================================================
with_schema <- function(panel, cols) {
  for (col in setdiff(cols, names(panel))) panel[[col]] <- NA_real_
  dplyr::arrange(dplyr::select(panel, "date", dplyr::all_of(cols)), .data$date)
}

## A month in which nothing at all was observed is not a month of the
## panel -- without this the file would begin wherever the longest series
## begins and carry rows of nothing but NA wherever none overlap.
monthly_panel <- with_schema(monthly_fetch$panel, monthly_cols) %>%
  dplyr::filter(.data$date >= period_to_date(start_m))
monthly_panel <- monthly_panel[rowSums(!is.na(monthly_panel[, monthly_cols, drop = FALSE])) > 0, ]

quarterly_panel <- dplyr::full_join(
  quarterly_fetch$panel,
  to_quarterly(monthly_panel, monthly_cols),
  by = "date"
) %>% with_schema(all_cols)

mixed_panel <- to_mixed(monthly_panel, quarterly_fetch$panel, all_cols)

write_panel <- function(panel, suffix, cols, unit) {
  path <- out_path(suffix)
  readr::write_csv(panel, path)
  n_resolved <- sum(cols %in% names(concept_source))
  message("Saved ", nrow(panel), " ", unit, " x ", length(cols), " canonical concepts (",
          n_resolved, " resolved, ", length(cols) - n_resolved, " NA) to '", path, "'")
}
write_panel(monthly_panel, "_monthly_panel.csv", monthly_cols, "months")
write_panel(quarterly_panel, "_panel.csv", all_cols, "quarters")
write_panel(mixed_panel, "_mixed_panel.csv", all_cols, "months")

metadata <- series_metadata(mixed_panel, concept_source)
readr::write_csv(metadata, out_path("_metadata.csv"), na = "")
message("Saved series metadata to '", out_path("_metadata.csv"), "'")

## =====================================================================
## 3. Policy-event dummies, over the mixed panel's months
## =====================================================================
dummies_m <- make_monthly_dummies(country, min(mixed_panel$date), max(mixed_panel$date))
if (is.null(dummies_m)) {
  message("No policy events recorded for ", country, " in R/dummies.R -- no dummy files written.")
} else {
  readr::write_csv(dummies_m, out_path("_dummies_monthly.csv"))
  readr::write_csv(make_quarterly_dummies(dummies_m), out_path("_dummies_quarterly.csv"))
  message("Saved ", ncol(dummies_m) - 1, " policy-event dummies to '",
          out_path("_dummies_monthly.csv"), "' and '", out_path("_dummies_quarterly.csv"), "'")
}

## =====================================================================
## 4. Coverage reports and plausibility checks, one per published
##    frequency. The checks' one frequency-sensitive rule is the "level"
##    category's 90% period-on-period jump check; month-on-month changes
##    are smaller than quarter-on-quarter ones, so it is if anything more
##    lenient on the monthly panel and still catches a units error.
## =====================================================================
provider_display_names <- c(
  EUROSTAT = "Eurostat (namq_10_gdp)",
  OECD_QNA = "OECD QNA", IMF_QNEA = "IMF QNEA", BIS_WSTC = "BIS WS_TC",
  ECB_QSA_PUB = "ECB QSA_PUB (euro-area aggregate, not country-specific)",
  ECB_MIR = "ECB MFI Interest Rate Statistics (MIR)",
  ECB_BSI = "ECB MFI Balance Sheet Items (BSI)",
  ECB_CISS = "ECB Composite Indicator of Systemic Stress (CISS)",
  FRED_MIRROR = "OECD MEI / BIS / World Uncertainty Index (via FRED mirror)",
  EC_BCS = "European Commission Business and Consumer Survey",
  EUROSTAT_HICP = "Eurostat (prc_hicp_minr, HICP 2025=100)",
  EUROSTAT_ULC = "Eurostat (namq_10_lp_ulc, hours-based ULC)",
  EUROSTAT_GOV = "Eurostat (gov_10q_ggnfa, government finance statistics)",
  EUROSTAT_STS = "Eurostat short-term statistics (sts_inpr_m / sts_trtu_m / une_rt_m)",
  OENB = "OeNB data service (Oesterreichische Nationalbank)",
  BUNDESBANK = "Deutsche Bundesbank (term structure of listed Federal securities)",
  YAHOO_FINANCE = "Yahoo Finance",
  GPR = "Geopolitical Risk Index (Caldara-Iacoviello)",
  EUROSTAT_CHDD = "Eurostat (nrg_chdd_m, degree days)",
  EUROSTAT_NA = "Eurostat (namq_10_a10_e, national accounts by activity)",
  EUROSTAT_POP = "Eurostat (namq_10_pe, national accounts population)",
  FRED = "FRED (series published by FRED itself, not an OECD/BIS mirror)",
  OPEN_METEO = "ERA5 reanalysis (via the Open-Meteo archive API)"
)
## In the quarterly report a monthly concept's source says how its
## quarters were made, since that is not visible in the CSV.
format_source <- function(lbl, quarterly) {
  src <- concept_source[[lbl]]
  if (is.null(src)) return(NA_character_)
  out <- sprintf("%s [%s]", provider_display_names[[src$provider]] %||% src$provider, src$key)
  if (quarterly && lbl %in% monthly_cols) {
    rule <- concept_dictionary$aggregation[concept_dictionary$label == lbl]
    out <- paste0(out, if (identical(rule, "sum")) " -- quarterly total of complete months" else
      " -- quarterly average of its months")
  }
  out
}
coverage_rows <- function(cols, quarterly) {
  concept_dictionary %>%
    dplyr::filter(.data$label %in% cols) %>%
    dplyr::transmute(
      fred_qd_group, label,
      resolved = .data$label %in% names(concept_source),
      source = purrr::map_chr(.data$label, ~ format_source(.x, quarterly))
    )
}
checks <- function(panel, cols, what) {
  results <- run_plausibility_checks(panel, cols)
  counts <- table(vapply(results, function(x) x$status, character(1)))
  message("Plausibility checks (", what, "): ", sum(counts[c("PASS")], na.rm = TRUE), " PASS, ",
          sum(counts[c("FLAG")], na.rm = TRUE), " FLAG, ",
          sum(counts[c("NO_DATA", "TOO_SHORT")], na.rm = TRUE), " NO_DATA/TOO_SHORT")
  for (f in Filter(function(x) x$status == "FLAG", results)) message("  FLAG [", f$label, "]: ", f$detail)
  results
}

## Groups deliberately left unresolved -- see README for why.
skipped_groups <- tibble::tribble(
  ~fred_qd_group,               ~reason,
  "Inventories, Orders, and Sales (full)", "Only a retail-sales-volume proxy is included (see coverage); re-checked 2026-08-30 for a manufacturers' new-orders/inventories cross-country equivalent and found none -- US-specific Census Bureau concept, deliberately not attempted."
)

q_rows <- coverage_rows(all_cols, quarterly = TRUE)
jsonlite::write_json(list(
  country = country,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  start_period = start_q,
  resolved = q_rows %>% dplyr::filter(.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label, source) %>% purrr::transpose(),
  skipped = q_rows %>% dplyr::filter(!.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  groups_not_attempted = skipped_groups %>% purrr::transpose(),
  plausibility_checks = checks(quarterly_panel, all_cols, "quarterly")
), out_path("_coverage.json"), auto_unbox = TRUE, pretty = TRUE)

m_rows <- coverage_rows(monthly_cols, quarterly = FALSE)
jsonlite::write_json(list(
  country = country,
  frequency = "monthly",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  start_period = start_m,
  concepts_published_monthly = length(monthly_cols),
  concepts_quarterly_only = length(quarterly_cols),
  resolved = m_rows %>% dplyr::filter(.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label, source) %>% purrr::transpose(),
  skipped = m_rows %>% dplyr::filter(!.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  quarterly_only = concept_dictionary %>% dplyr::filter(.data$frequency == "Q") %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  plausibility_checks = checks(monthly_panel, monthly_cols, "monthly")
), out_path("_monthly_coverage.json"), auto_unbox = TRUE, pretty = TRUE)
message("Saved coverage reports to '", out_path("_coverage.json"), "' and '",
        out_path("_monthly_coverage.json"), "'")

## =====================================================================
## 5. Optional: validate against the real FRED-QD file (USA only). The
##    national accounts are quarterly at source, so this checks exactly
##    what it checked before the panels were split.
## =====================================================================
if (opt$validate) {
  if (country != "USA") {
    message("--validate requested but --country is not USA; FRED-QD only covers the US, so there is no ground truth to check against. Skipping.")
  } else {
    fred_qd_url <- paste0(
      "https://www.stlouisfed.org/-/media/project/frbstl/stlouisfed/research/fred-md/quarterly/",
      opt$fred_qd_vintage, "-qd.csv"
    )
    message("Downloading actual FRED-QD (", opt$fred_qd_vintage, " vintage) for validation...")
    fred_qd_actual <- fetch_actual_fred_qd(fred_qd_url)
    if (is.null(fred_qd_actual)) {
      message("Could not download FRED-QD for validation -- try a different --fred-qd-vintage (format YYYY-MM).")
    } else {
      results <- validate_against_fred_qd(quarterly_fetch$anchors, fred_qd_actual)
      cat("\n--- FRED-QD validation (USA), correlation of quarterly growth rates ---\n")
      for (i in seq_len(nrow(results))) {
        r <- results[i, ]
        corr_str <- if (is.na(r$correlation)) "  n/a  " else sprintf("%+.3f", r$correlation)
        cat(sprintf("  [%s] %-35s (%-8s) corr=%s\n", r$status, r$our_label, r$fred_qd_mnemonic, corr_str))
      }
      cat(sprintf("\n%d PASS, %d FAIL, %d NO_DATA (threshold: correlation >= 0.9)\n",
                  sum(results$status == "PASS"), sum(results$status == "FAIL"),
                  sum(results$status == "NO_DATA")))
    }
  }
}

## =====================================================================
## 6. The data-sources registries
##
##    docs/data_sources.csv: one row per (country, concept), the "USA"
##    rows always FRED-QD's own mnemonics (the ground truth being
##    approximated), never overwritten by a live --country USA run.
##    docs/data_sources_monthly.csv: the monthly concepts' sources. Since
##    the panels share one fetch, a monthly concept has the same source in
##    both; the quarterly registry's comment says how its quarters are made.
## =====================================================================
data_sources_path <- file.path(project_root, "docs", "data_sources.csv")
concept_notes <- concept_dictionary %>%
  dplyr::filter(!is.na(.data$cross_country_note)) %>%
  dplyr::transmute(label, note = .data$cross_country_note)
usa_rows <- concept_dictionary %>%
  dplyr::transmute(
    country = "USA", variable = .data$label,
    provider = ifelse(is.na(.data$fred_qd_mnemonic), "NONE", "FRED_QD"),
    key = .data$fred_qd_mnemonic, comment = .data$us_note
  )
new_rows <- NULL
if (country != "USA") {
  new_rows <- concept_dictionary %>%
    dplyr::transmute(
      country = .env$country,
      variable = .data$label,
      provider = purrr::map_chr(.data$label, ~ concept_source[[.x]]$provider %||% NA_character_),
      key = purrr::map_chr(.data$label, ~ concept_source[[.x]]$key %||% NA_character_),
      comment = concept_notes$note[match(.data$label, concept_notes$label)]
    ) %>%
    dplyr::mutate(comment = ifelse(
      is.na(.data$provider),
      paste0("Not resolved for ", .env$country, ". ", dplyr::coalesce(.data$comment, "")),
      .data$comment
    ))
}
existing <- if (file.exists(data_sources_path)) {
  readr::read_csv(data_sources_path, col_types = readr::cols(.default = "c"))
} else {
  tibble::tibble(country = character(), variable = character(), provider = character(),
                 key = character(), comment = character())
}
registry <- dplyr::bind_rows(
  dplyr::filter(existing, !(.data$country %in% c("USA", .env$country))),
  usa_rows, new_rows
) %>%
  dplyr::semi_join(concept_dictionary, by = c("variable" = "label")) %>%
  dplyr::arrange(.data$country != "USA", .data$country,
                 match(.data$variable, concept_dictionary$label))
readr::write_csv(registry, data_sources_path, na = "")

registry_m_path <- file.path(project_root, "docs", "data_sources_monthly.csv")
rows_m <- m_rows %>%
  dplyr::filter(.data$resolved) %>%
  dplyr::transmute(
    country = !!country, variable = .data$label,
    provider = purrr::map_chr(.data$label, ~ concept_source[[.x]]$provider),
    key = purrr::map_chr(.data$label, ~ concept_source[[.x]]$key)
  )
existing_m <- if (file.exists(registry_m_path)) {
  readr::read_csv(registry_m_path, col_types = readr::cols(.default = "c")) %>%
    dplyr::filter(.data$country != !!country)
} else {
  rows_m[0, ]
}
readr::write_csv(dplyr::arrange(dplyr::bind_rows(existing_m, rows_m), .data$country, .data$variable),
                 registry_m_path)
message("Updated the data-sources registries: '", data_sources_path, "' and '", registry_m_path, "'")
