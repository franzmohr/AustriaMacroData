#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_country_panel.R -- CLI entrypoint
##
## Builds a FRED-QD-style quarterly macro panel for one country from
## OECD, FRED's OECD/BIS mirror, IMF (fallback), BIS and ECB, and
## optionally validates the result against the real published FRED-QD
## file (USA only, since that's the only ground truth available).
##
## Usage:
##   Rscript scripts/build_country_panel.R --country DEU --start-period 1995-Q1
##   Rscript scripts/build_country_panel.R --country USA --validate
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
for (f in list.files(file.path(project_root, "R"), full.names = TRUE, pattern = "\\.R$")) {
  source(f)
}

## ---- CLI options ---------------------------------------------------
option_list <- list(
  make_option("--country", type = "character", default = NULL,
              help = "ISO-3166 alpha-3 country code, e.g. DEU, USA, AUT [required]"),
  make_option("--start-period", type = "character", default = "1995-Q1", dest = "start_period",
              help = "First quarter to fetch, format YYYY-Qn [default %default]"),
  make_option("--fred-country2", type = "character", default = NULL, dest = "fred_country2",
              help = "FRED's 2-letter OECD-mirror country code, if not in the built-in table"),
  make_option("--validate", action = "store_true", default = FALSE,
              help = "Cross-check the OECD-sourced anchor series against the real FRED-QD file (USA only)"),
  make_option("--output-dir", type = "character", default = "output", dest = "output_dir",
              help = "Directory to write <country>_nipa.csv and <country>_coverage.json into [default %default]"),
  make_option("--fred-qd-vintage", type = "character", default = "2026-07", dest = "fred_qd_vintage",
              help = "FRED-QD monthly vintage to validate against, format YYYY-MM [default %default]")
)
opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$country)) {
  stop("--country is required, e.g. --country DEU", call. = FALSE)
}
country <- toupper(opt$country)
start_period <- opt$start_period
dir.create(opt$output_dir, showWarnings = FALSE, recursive = TRUE)

country2 <- if (!is.null(opt$fred_country2)) opt$fred_country2 else lookup_country2(country)

## ---- FRED-QD group taxonomy + ground-truth reference ----------------
## 24 concepts across all 14 FRED-QD groups (as of 2026-08-30; started at
## 18 concepts across 12 groups -- see R/fred_mirror.R and R/bis.R header
## comments for what was added and how each addition was verified).
##
## `fred_qd_mnemonic` is the actual FRED-QD series each concept is meant to
## approximate for the United States (NA where none exists -- `us_note`
## explains why). FRED-QD IS the ground truth for the US, so this is what
## verifies the FRED-QD source; it seeds the "USA" rows of
## docs/data_sources.csv (see step 8 below), which are fixed reference
## documentation and are NOT overwritten by a live --country USA run (that
## run's OECD/IMF/BIS/FRED-mirror keys are still visible in
## output/usa_coverage.json as an interesting cross-check, not a
## replacement for the ground truth).
concept_group_map <- tibble::tribble(
  ~label,                               ~fred_qd_group,                   ~fred_qd_mnemonic, ~us_note,
  "real_gdp",                           "Output and Income",              "GDPC1",           NA,
  "real_household_consumption",         "Output and Income",              "PCECC96",         NA,
  "real_govt_consumption",              "Output and Income",              "GCEC1",           NA,
  "real_gfcf_total",                    "Output and Income",              "FPIx",            NA,
  "real_exports",                       "Output and Income",              "EXPGSC1",         NA,
  "real_imports",                       "Output and Income",              "IMPGSC1",         NA,
  "real_household_disposable_income",   "Output and Income",              "DPIC96",          NA,
  "industrial_production",              "Industrial Production",          "INDPRO",          NA,
  "unemployment_rate",                  "Employment and Unemployment",    "UNRATE",          NA,
  "employment_rate",                    "Employment and Unemployment",    NA,                "No FRED-QD employment-rate series; nearest are CE16OV (level) and CIVPART (participation rate).",
  "house_price_real",                   "Housing",                        "USSTHPI",         NA,
  "retail_sales_volume",                "Inventories, Orders, and Sales", "RSAFSx",          NA,
  "cpi_index",                          "Prices",                         "CPIAUCSL",        NA,
  "unit_labor_cost",                    "Earnings and Productivity",      "ULCNFB",          "FRED-QD's ULCNFB is a nonfarm-business, hours-based unit-labor-cost INDEX; the OECD-mirror series used for every country (incl. the US) is an employment-based % CHANGE -- related concepts, different construction.",
  "long_term_rate",                     "Interest Rates",                 "GS10",            NA,
  "short_term_rate",                    "Interest Rates",                 "TB3MS",           NA,
  "mortgage_rate",                      "Interest Rates",                 "MORTGAGE30US",    "FRED-QD's MORTGAGE30US is a 30-year FIXED-rate average; the ECB series used for euro-area countries is a new-business AAR/NDER rate across all initial rate fixation periods (fixed and variable combined) -- related but not an identical construction.",
  "credit_to_private_nonfin_sector",    "Money and Credit",               NA,                "FRED-QD tracks credit by purpose/level (BUSLOANSx, TOTALSLx, REALLNx, ...), not one combined %GDP series like BIS's.",
  "euro_area_household_net_worth_growth", "Household Balance Sheets",     "TNWBSHNOx",       NA,
  "household_credit_to_gdp",            "Household Balance Sheets",       NA,                "No %GDP household-credit series in FRED-QD; FRED itself mirrors the same underlying BIS series for the US as HDTGPDUSQ163N.",
  "corporate_credit_to_gdp",            "Non-Household Balance Sheets",   NA,                "FRED-QD's TLBSNNCBx is a dollar-level series, not %GDP; no confirmed FRED %GDP analog for the US was found.",
  "fx_rate_to_usd",                     "Exchange Rates",                 NA,                "Not meaningful for the US itself -- this concept is a foreign currency's price in USD.",
  "real_effective_exchange_rate",       "Exchange Rates",                 "TWEXAFEGSMTHx",   "FRED-QD's series is a NOMINAL trade-weighted index against advanced foreign economies only; the OECD-mirror series used for other countries is REAL (price-adjusted) and broader -- related but not identical.",
  "consumer_confidence",                "Other",                          "UMCSENTx",        NA,
  "share_price_index",                  "Stock Markets",                  "S&P 500",         NA
)

## ---- Cross-country caveats -------------------------------------------
## For each concept, how the international source used for every
## NON-US country differs conceptually from the US/FRED-QD definition
## above -- this is the same note for every country using that source
## (the methodology doesn't vary by country, only the country code does),
## and becomes the `comment` column in docs/data_sources.csv for every
## non-USA row. Concepts not listed here have no material conceptual
## difference beyond ordinary cross-country methodology variation.
concept_notes <- tibble::tribble(
  ~label,                                 ~note,
  "real_household_consumption",           "Source-dependent: for EU members (Eurostat NA_ITEM=P31_S14) this is household-only consumption, a close match to FRED-QD's household-only PCE; where OECD QNA is used instead (sector S1M), it is total-economy final consumption expenditure INCLUDING NPISHs, broader than FRED-QD's definition.",
  "real_govt_consumption",                "SNA/ESA transaction P3, sector S13 (general government) is government consumption expenditure only, whether sourced from OECD or Eurostat; FRED-QD's GCEC1 also includes government gross investment.",
  "real_gfcf_total",                      "SNA/ESA transaction P51G (gross fixed capital formation) is for ALL sectors (incl. government), whether sourced from OECD or Eurostat; FRED-QD's FPIx is private-sector fixed investment only.",
  "real_household_disposable_income",     "OECD's quarterly household disposable income (DF_QNA_INC_SAV) is published for only 11 countries (AUS, BRA, CAN, CHL, EST, GRC, HUN, LTU, LUX, LVA, ZAF); absent for most others, confirmed absent for DEU/AUT/USA/FRA/GBR.",
  "employment_rate",                      "Employment-to-population ratio, ages 15-64 (OECD MEI); included as a standard cross-country labour-market indicator even though FRED-QD has no direct equivalent (see us_note).",
  "retail_sales_volume",                  "OECD MEI retail sales volume is not published for the USA itself via this mirror -- a genuine coverage gap for that one country, not a wrong code.",
  "unit_labor_cost",                      "OECD MEI unit labour cost (employment-based, % change), confirmed live for AT/DE/FR/GB/US.",
  "credit_to_private_nonfin_sector",      "BIS reports this as a stock, % of GDP (private non-financial sector = households + nonfinancial corporations combined).",
  "euro_area_household_net_worth_growth", "ECB QSA_PUB publishes household net worth only for the euro-area AGGREGATE (REF_AREA=I8) -- every euro-area country gets this same figure; it is not country-specific.",
  "household_credit_to_gdp",              "BIS credit to households & NPISHs, % of GDP -- country-specific (unlike the ECB net-worth aggregate above).",
  "corporate_credit_to_gdp",              "BIS credit to nonfinancial corporations, % of GDP -- country-specific.",
  "fx_rate_to_usd",                       "OECD MEI bilateral exchange rate, national currency per USD.",
  "mortgage_rate",                        "ECB MFI Interest Rate Statistics (MIR): new-business loans to households for house purchase, all initial rate fixation periods combined -- genuinely country-specific (unlike euro_area_household_net_worth_growth above), available for euro-area members only.",
  "real_effective_exchange_rate",         "OECD real (price-adjusted) effective exchange rate index -- see us_note for how this differs from FRED-QD's nominal series.",
  "consumer_confidence",                  "EU member states: sourced from the European Commission's own Business and Consumer Survey (a live, monthly, seasonally adjusted balance statistic, e.g. \"AT.CONS\"), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/ec_survey.R. Falls back to the FRED mirror if the EC archive is unavailable for a given run.",
  "share_price_index",                    "Austria: sourced from the ATX (Austrian Traded Index) via Yahoo Finance (ticker \"^ATX\"), Austria's own actual benchmark index, NOT the generic OECD MEI 'all shares' proxy used for other countries -- see R/yahoo_finance.R. Falls back to the FRED mirror if the Yahoo Finance fetch is unavailable for a given run."
)

## Groups deliberately left unresolved -- see README for why. (Earnings
## and Productivity and Non-Household Balance Sheets are no longer here:
## both now have one live-verified representative concept, see above.)
skipped_groups <- tibble::tribble(
  ~fred_qd_group,               ~reason,
  "Inventories, Orders, and Sales (full)", "Only a retail-sales-volume proxy is included (see coverage); re-checked 2026-08-30 for a manufacturers' new-orders/inventories cross-country equivalent and found none -- US-specific Census Bureau concept, deliberately not attempted."
)

## =====================================================================
## 1. Anchor NIPA concepts: Eurostat first for EU members, then OECD QNA
##    for whatever's still missing, then IMF QNEA fallback for whatever's
##    missing after that
## =====================================================================
all_anchor_labels <- c(oecd_anchor_concepts$label, "real_household_disposable_income")

## `concept_source[[label]]` is a list(provider=, key=, note=) rather than a
## plain string -- `provider`+`key` are what get written into
## docs/data_sources.csv (step 8 below), so that CSV documents the EXACT
## identifier used, not just a human-readable provider name.
concept_source <- list()
anchor_merged <- NULL

if (country %in% eu_member_countries) {
  message("Country is an EU member -- trying Eurostat first for anchor NIPA concepts...")
  eurostat_result <- fetch_eurostat_anchors(country, start_period = start_period)
  if (!is.null(eurostat_result)) {
    anchor_merged <- eurostat_result
    for (lbl in setdiff(names(eurostat_result), "period")) {
      na_item <- eurostat_anchor_concepts$na_item[eurostat_anchor_concepts$label == lbl]
      concept_source[[lbl]] <- list(provider = "EUROSTAT", key = paste0("namq_10_gdp:", na_item))
    }
  }
}

still_missing <- setdiff(all_anchor_labels, names(concept_source))
message("Fetching anchor NIPA concepts for ", country, " from OECD QNA (",
        length(still_missing), " of ", length(all_anchor_labels), " not yet resolved)...")
oecd_result <- fetch_oecd_anchors(country, start_period = start_period, labels = still_missing)

oecd_anchor_key <- function(label) {
  row <- oecd_anchor_concepts[oecd_anchor_concepts$label == label, ]
  if (nrow(row) == 1) return(paste0(row$sector, ".", row$transaction))
  paste0(oecd_disposable_income_dims$sector, ".", oecd_disposable_income_dims$transaction, " (DF_QNA_INC_SAV)")
}
if (!is.null(oecd_result)) {
  for (lbl in setdiff(names(oecd_result), "period")) {
    anchor_merged <- if (is.null(anchor_merged)) oecd_result %>% dplyr::select(period, dplyr::all_of(lbl))
                      else dplyr::full_join(anchor_merged, oecd_result %>% dplyr::select(period, dplyr::all_of(lbl)), by = "period")
    concept_source[[lbl]] <- list(provider = "OECD_QNA", key = oecd_anchor_key(lbl))
  }
}

missing_anchors <- setdiff(all_anchor_labels, names(concept_source))

if (length(missing_anchors) > 0) {
  message("OECD/Eurostat had no data for: ", paste(missing_anchors, collapse = ", "), " -- trying IMF QNEA fallback...")
  imf_fallback <- fetch_imf_fallbacks(country, missing_anchors, start_period = start_period)
  for (lbl in names(imf_fallback)) {
    anchor_merged <- if (is.null(anchor_merged)) imf_fallback[[lbl]] else dplyr::full_join(anchor_merged, imf_fallback[[lbl]], by = "period")
    imf_indicator <- imf_indicator_map$imf_indicator[imf_indicator_map$label == lbl]
    concept_source[[lbl]] <- list(provider = "IMF_QNEA", key = imf_indicator)
  }
  if (length(imf_fallback) > 0) anchor_merged <- dplyr::arrange(anchor_merged, period)
}

if (is.null(anchor_merged)) stop("No anchor series resolved from Eurostat, OECD or IMF -- check the country code.", call. = FALSE)
anchor_merged <- dplyr::arrange(anchor_merged, period)

panel <- anchor_merged %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-period)

## =====================================================================
## 2. BIS credit -- private non-financial sector, households, and
##    nonfinancial corporations (same dataflow, three TC_BORROWERS codes)
## =====================================================================
bis_credit_concepts <- tibble::tribble(
  ~label,                             ~tc_borrowers,
  "credit_to_private_nonfin_sector",  "P",
  "household_credit_to_gdp",          "H",
  "corporate_credit_to_gdp",          "N"
)
if (!is.na(country2)) {
  message("Fetching Money and Credit from BIS for ", country2, "...")
  for (i in seq_len(nrow(bis_credit_concepts))) {
    lbl <- bis_credit_concepts$label[i]
    tcb <- bis_credit_concepts$tc_borrowers[i]
    credit <- fetch_bis_credit(country2, tc_borrowers = tcb, label = lbl, start_period = start_period)
    if (!is.null(credit)) {
      credit <- credit %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-period)
      panel <- dplyr::full_join(panel, credit, by = "date")
      concept_source[[lbl]] <- list(provider = "BIS_WSTC", key = tcb)
    }
  }
} else {
  message("Skipping BIS credit: no FRED 2-letter code known for ", country, " (pass --fred-country2)")
}

## =====================================================================
## 3. ECB household net worth (euro-area aggregate only)
## =====================================================================
networth <- fetch_ecb_household_networth(country, start_period = start_period)
if (!is.null(networth)) {
  networth <- networth %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-period)
  panel <- dplyr::full_join(panel, networth, by = "date")
  concept_source[["euro_area_household_net_worth_growth"]] <- list(provider = "ECB_QSA_PUB", key = "I8")
}

mortgage <- fetch_ecb_mortgage_rate(country, start_period = start_period)
if (!is.null(mortgage)) {
  panel <- dplyr::full_join(panel, mortgage, by = "date")
  concept_source[["mortgage_rate"]] <- list(provider = "ECB_MIR", key = "A2C.R.A.2250.EUR.N")
}

## =====================================================================
## 4. FRED/OECD-MEI/BIS mirror groups
## =====================================================================
if (!is.na(country2)) {
  message("Fetching additional FRED-QD-style groups for ", country2, " via FRED's OECD/BIS mirrors...")
  other <- fetch_other_groups(country2, country)
  for (lbl in names(other)) {
    panel <- dplyr::full_join(panel, other[[lbl]], by = "date")
    id_template <- other_groups$id_template[other_groups$label == lbl]
    resolved_mnemonic <- stringr::str_replace(id_template, stringr::fixed("{cc2}"), country2)
    resolved_mnemonic <- stringr::str_replace(resolved_mnemonic, stringr::fixed("{cc3}"), country)
    concept_source[[lbl]] <- list(provider = "FRED_MIRROR", key = resolved_mnemonic)
  }
} else {
  message("Skipping FRED-mirror groups: no FRED 2-letter code known for ", country, " (pass --fred-country2)")
}

## =====================================================================
## 4c. EU-specific override: consumer confidence from the European
##     Commission's own Business and Consumer Survey (fresher than the
##     frozen OECD-MEI-via-FRED source above -- see R/ec_survey.R)
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- trying the EC Business and Consumer Survey for consumer_confidence...")
  ec_cc <- fetch_ec_consumer_confidence(country, start_period = start_period)
  if (!is.null(ec_cc)) {
    panel <- panel %>% dplyr::select(-dplyr::any_of("consumer_confidence")) %>%
      dplyr::full_join(ec_cc, by = "date")
    concept_source[["consumer_confidence"]] <- list(provider = "EC_BCS", key = paste0(lookup_ec_country2(country), ".CONS"))
  } else {
    message("EC survey unavailable for ", country, " this run -- keeping the FRED-mirror consumer_confidence value, if any.")
  }
}

## =====================================================================
## 4d. Austria-specific override: ATX index (via Yahoo Finance) in place
##     of the generic OECD "all shares" proxy for share_price_index
## =====================================================================
if (country == "AUT") {
  message("Country is Austria -- trying the ATX index (Yahoo Finance) for share_price_index...")
  atx <- fetch_atx_quarterly(start_period = start_period)
  if (!is.null(atx)) {
    panel <- panel %>% dplyr::select(-dplyr::any_of("share_price_index")) %>%
      dplyr::full_join(atx, by = "date")
    concept_source[["share_price_index"]] <- list(provider = "YAHOO_FINANCE", key = "^ATX")
  } else {
    message("ATX fetch unavailable this run -- keeping the FRED-mirror share_price_index value, if any.")
  }
}

panel <- dplyr::arrange(panel, date)

## =====================================================================
## 4b. Enforce a canonical column schema
## =====================================================================
## The whole point of pulling from OECD/IMF/BIS/ECB/FRED behind a single
## FRED-QD-style concept label is that a user should be able to change
## only --country and get a like-for-like file back. That only holds if
## every <country>_nipa.csv has the same columns, in the same order,
## regardless of which concepts happened to resolve for that country --
## so concepts that did not resolve are still included here, filled with
## NA, rather than silently missing from the file. (Which concepts are
## NA and why is exactly what the coverage report below is for.)
canonical_cols <- concept_group_map$label
for (col in setdiff(canonical_cols, names(panel))) {
  panel[[col]] <- NA_real_
}
panel <- dplyr::select(panel, date, dplyr::all_of(canonical_cols))

## =====================================================================
## 5. Write output CSV
## =====================================================================
csv_path <- file.path(opt$output_dir, paste0(tolower(country), "_nipa.csv"))
readr::write_csv(panel, csv_path)
n_resolved <- sum(canonical_cols %in% names(concept_source))
message(
  "Saved ", nrow(panel), " periods x ", length(canonical_cols),
  " canonical concepts (", n_resolved, " resolved, ",
  length(canonical_cols) - n_resolved, " NA) to '", csv_path, "'"
)

## =====================================================================
## 6. Coverage report
## =====================================================================
`%||%` <- function(a, b) if (is.null(a)) b else a
provider_display_names <- c(
  EUROSTAT = "Eurostat (namq_10_gdp)",
  OECD_QNA = "OECD QNA", IMF_QNEA = "IMF QNEA", BIS_WSTC = "BIS WS_TC",
  ECB_QSA_PUB = "ECB QSA_PUB (euro-area aggregate, not country-specific)",
  ECB_MIR = "ECB MFI Interest Rate Statistics (MIR)",
  FRED_MIRROR = "OECD MEI / BIS (via FRED mirror)",
  EC_BCS = "European Commission Business and Consumer Survey",
  YAHOO_FINANCE = "Yahoo Finance"
)
format_source <- function(src) {
  if (is.null(src)) return(NA_character_)
  sprintf("%s [%s]", provider_display_names[[src$provider]] %||% src$provider, src$key)
}
coverage_rows <- concept_group_map %>%
  dplyr::mutate(
    resolved = .data$label %in% names(concept_source),
    source = purrr::map_chr(.data$label, ~ format_source(concept_source[[.x]]))
  )

coverage <- list(
  country = country,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  start_period = start_period,
  resolved = coverage_rows %>% dplyr::filter(.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label, source) %>% purrr::transpose(),
  skipped = coverage_rows %>% dplyr::filter(!.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  groups_not_attempted = skipped_groups %>% purrr::transpose()
)

coverage_path <- file.path(opt$output_dir, paste0(tolower(country), "_coverage.json"))
jsonlite::write_json(coverage, coverage_path, auto_unbox = TRUE, pretty = TRUE)
message("Saved coverage report to '", coverage_path, "'")

## =====================================================================
## 7. Optional: validate against the real FRED-QD file (USA only)
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
      results <- validate_against_fred_qd(anchor_merged, fred_qd_actual)
      cat("\n--- FRED-QD validation (USA), correlation of quarterly growth rates ---\n")
      for (i in seq_len(nrow(results))) {
        r <- results[i, ]
        corr_str <- if (is.na(r$correlation)) "  n/a  " else sprintf("%+.3f", r$correlation)
        cat(sprintf("  [%s] %-35s (%-8s) corr=%s\n", r$status, r$our_label, r$fred_qd_mnemonic, corr_str))
      }
      n_pass <- sum(results$status == "PASS")
      n_fail <- sum(results$status == "FAIL")
      n_nodata <- sum(results$status == "NO_DATA")
      cat(sprintf("\n%d PASS, %d FAIL, %d NO_DATA (threshold: correlation >= 0.9)\n", n_pass, n_fail, n_nodata))
    }
  }
}

## =====================================================================
## 8. Update the data-sources registry (docs/data_sources.csv)
## =====================================================================
## Long format, one row per (country, variable): country, variable,
## provider, key, comment. This is the single documentation surface for
## "what source backs this number, and how does it conceptually differ
## from the US/FRED-QD definition" -- replacing scattered prose comments
## across R/oecd.R, R/fred_mirror.R, R/bis.R, R/ecb.R with one table a
## researcher can open directly, no code-reading required.
##
## The "USA" rows are special: they always hold the actual FRED-QD
## mnemonic per concept (from concept_group_map above, `us_note` as the
## comment), because FRED-QD IS the ground truth being approximated --
## they are NOT overwritten by a live `--country USA` run through the
## international sources (that run's OECD/IMF/BIS/FRED-mirror keys are
## still visible in output/usa_coverage.json as an interesting
## cross-check, not a replacement for the ground truth).
data_sources_path <- file.path(project_root, "docs", "data_sources.csv")

usa_rows <- concept_group_map %>%
  dplyr::transmute(
    country = "USA",
    variable = .data$label,
    provider = ifelse(is.na(.data$fred_qd_mnemonic), "NONE", "FRED_QD"),
    key = .data$fred_qd_mnemonic,
    comment = .data$us_note
  )

new_rows <- NULL
if (country != "USA") {
  new_rows <- concept_group_map %>%
    dplyr::transmute(
      country = .env$country,
      variable = .data$label,
      provider = purrr::map_chr(.data$label, ~ concept_source[[.x]]$provider %||% NA_character_),
      key = purrr::map_chr(.data$label, ~ concept_source[[.x]]$key %||% NA_character_),
      comment = concept_notes$note[match(.data$label, concept_notes$label)]
    ) %>%
    dplyr::mutate(
      comment = ifelse(
        is.na(.data$provider),
        paste0("Not resolved for ", .env$country, ". ", dplyr::coalesce(.data$comment, "")),
        .data$comment
      )
    )
}

existing <- if (file.exists(data_sources_path)) {
  readr::read_csv(data_sources_path, col_types = readr::cols(.default = "c"))
} else {
  tibble::tibble(country = character(), variable = character(), provider = character(),
                  key = character(), comment = character())
}
existing <- existing %>% dplyr::filter(!(.data$country %in% c("USA", .env$country)))

## Reprojecting onto concept_group_map$label every run means the registry
## can't silently drift out of sync with it: a newly added concept shows
## up as new rows once each country is re-run, and a removed one simply
## stops appearing (existing rows for it are dropped by the semi_join).
registry <- dplyr::bind_rows(existing, usa_rows, new_rows) %>%
  dplyr::semi_join(concept_group_map, by = c("variable" = "label")) %>%
  dplyr::arrange(.data$country != "USA", .data$country,
                  match(.data$variable, concept_group_map$label))

dir.create(dirname(data_sources_path), showWarnings = FALSE, recursive = TRUE)
readr::write_csv(registry, data_sources_path, na = "")
message(
  "Updated data-sources registry: '", data_sources_path, "' (",
  nrow(registry), " rows across ", dplyr::n_distinct(registry$country), " countries)"
)
