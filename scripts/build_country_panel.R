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
##   Rscript scripts/build_country_panel.R --country DEU --start-period 1960-Q1
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
  make_option("--start-period", type = "character", default = "1960-Q1", dest = "start_period",
              help = "First quarter to fetch, format YYYY-Qn [default %default -- OECD QNA has Austrian real GDP back to 1960-Q1; concepts with no data this far back are simply NA before their own start, per the canonical-schema design]"),
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
  "industrial_confidence",              "Industrial Production",          NA,                "No FRED-QD equivalent; the EC's Industrial Confidence Indicator (since 1985) is a standard input to the OECD's Composite Leading Indicators for many countries, with documented leading-indicator value for industrial production/GDP turning points.",
  "unemployment_rate",                  "Employment and Unemployment",    "UNRATE",          NA,
  "employment_rate",                    "Employment and Unemployment",    NA,                "No FRED-QD employment-rate series; nearest are CE16OV (level) and CIVPART (participation rate).",
  "employment_expectations",            "Employment and Unemployment",    NA,                "No FRED-QD equivalent; DG ECFIN's own purpose-built leading indicator for employment turning points (introduced 2013 specifically because the surveys' employment sub-components lead employment growth).",
  "house_price_real",                   "Housing",                        "USSTHPI",         NA,
  "construction_confidence",            "Housing",                        NA,                "No FRED-QD equivalent; a standard EC sentiment sub-index for the construction sector, companion to house_price_real.",
  "retail_sales_volume",                "Inventories, Orders, and Sales", "RSAFSx",          NA,
  "retail_confidence",                  "Inventories, Orders, and Sales", NA,                "No FRED-QD equivalent; a standard EC sentiment sub-index for the retail sector, companion to retail_sales_volume.",
  "cpi_index",                          "Prices",                         "CPIAUCSL",        NA,
  "core_cpi_index",                     "Prices",                         "CPILFESL",        NA,
  "food_price_index",                   "Prices",                         NA,                "No standalone CPI-food mnemonic in FRED-QD's 245-series list (the closest entries are PCE-side, e.g. DFXARG3Q086SBEA); included as a standard EU/ECB headline-inflation breakdown component.",
  "energy_price_index",                 "Prices",                         NA,                "No standalone CPI-energy mnemonic in FRED-QD's 245-series list (the closest entries are producer-price WPU0531/WPU0561 or the global OILPRICEx benchmark, none implemented here); included as a standard EU/ECB headline-inflation breakdown component.",
  "services_price_index",               "Prices",                         "CUSR0000SAS",     NA,
  "unit_labor_cost",                    "Earnings and Productivity",      "ULCNFB",          "FRED-QD's ULCNFB is a nonfarm-business, hours-based unit-labor-cost INDEX; the OECD-mirror series used for every country (incl. the US) is an employment-based % CHANGE -- related concepts, different construction.",
  "long_term_rate",                     "Interest Rates",                 "GS10",            NA,
  "short_term_rate",                    "Interest Rates",                 "TB3MS",           NA,
  "mortgage_rate",                      "Interest Rates",                 "MORTGAGE30US",    "FRED-QD's MORTGAGE30US is a 30-year FIXED-rate average; the ECB series used for euro-area countries is a new-business AAR/NDER rate across all initial rate fixation periods (fixed and variable combined) -- related but not an identical construction.",
  "credit_to_private_nonfin_sector",    "Money and Credit",               NA,                "FRED-QD tracks credit by purpose/level (BUSLOANSx, TOTALSLx, REALLNx, ...), not one combined %GDP series like BIS's.",
  "household_mortgage_loans",           "Money and Credit",               "REALLNx",         "FRED-QD's REALLNx is REAL (Core-PCE-deflated) dollars; the ECB BSI series used for euro-area countries is a NOMINAL euro-denominated stock of outstanding MFI loans to households for house purchase -- related but not an identical construction, and not deflated here.",
  "euro_area_household_net_worth_growth", "Household Balance Sheets",     "TNWBSHNOx",       NA,
  "household_credit_to_gdp",            "Household Balance Sheets",       NA,                "No %GDP household-credit series in FRED-QD; FRED itself mirrors the same underlying BIS series for the US as HDTGPDUSQ163N.",
  "corporate_credit_to_gdp",            "Non-Household Balance Sheets",   NA,                "FRED-QD's TLBSNNCBx is a dollar-level series, not %GDP; no confirmed FRED %GDP analog for the US was found.",
  "government_debt_to_gdp",             "Non-Household Balance Sheets",   "GFDEGDQ188S",     "FRED-QD's GFDEGDQ188S is US FEDERAL debt only (excludes state/local government); the BIS series used for every country (incl. the US) is credit to the WHOLE general-government sector (all levels combined) -- related but broader-scoped concepts, not identical.",
  "fx_rate_to_usd",                     "Exchange Rates",                 NA,                "Not meaningful for the US itself -- this concept is a foreign currency's price in USD.",
  "real_effective_exchange_rate",       "Exchange Rates",                 "TWEXAFEGSMTHx",   "FRED-QD's series is a NOMINAL trade-weighted index against advanced foreign economies only; the OECD-mirror series used for other countries is REAL (price-adjusted) and broader -- related but not identical.",
  "consumer_confidence",                "Other",                          "UMCSENTx",        NA,
  "economic_sentiment_indicator",       "Other",                          NA,                "No FRED-QD equivalent; DG ECFIN's own flagship composite indicator (weighted average of industry/services/consumer/retail/construction survey balances), explicitly constructed and empirically validated to track and lead euro-area GDP growth.",
  "services_confidence",                "Other",                          NA,                "No FRED-QD equivalent; a standard EC sentiment sub-index for the services sector.",
  "geopolitical_risk",                  "Other",                          NA,                "No FRED-QD equivalent; the Caldara-Iacoviello (2022) Geopolitical Risk index, the standard academic/policy measure -- country-specific for the 44 countries the source covers (confirmed: includes DEU/USA, excludes AUT), global index used otherwise (see R/gpr.R).",
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
  "credit_to_private_nonfin_sector",      "BIS reports this as a stock, % of GDP (private non-financial sector = households + nonfinancial corporations combined).",
  "euro_area_household_net_worth_growth", "ECB QSA_PUB publishes household net worth only for the euro-area AGGREGATE (REF_AREA=I8) -- every euro-area country gets this same figure; it is not country-specific.",
  "household_credit_to_gdp",              "BIS credit to households & NPISHs, % of GDP -- country-specific (unlike the ECB net-worth aggregate above).",
  "corporate_credit_to_gdp",              "BIS credit to nonfinancial corporations, % of GDP -- country-specific.",
  "government_debt_to_gdp",               "BIS credit to general government (all levels: federal/state/local combined), % of GDP -- BIS's own credit-statistics methodology treats this as a close proxy for gross government debt; genuinely country-specific and, unlike the euro-area-only mortgage_rate/consumer_confidence overrides, available for non-EU countries too (confirmed live for AT/DE/US).",
  "fx_rate_to_usd",                       "OECD MEI bilateral exchange rate, national currency per USD.",
  "mortgage_rate",                        "ECB MFI Interest Rate Statistics (MIR): new-business loans to households for house purchase, all initial rate fixation periods combined -- genuinely country-specific (unlike euro_area_household_net_worth_growth above), available for euro-area members only.",
  "real_effective_exchange_rate",         "OECD real (price-adjusted) effective exchange rate index -- see us_note for how this differs from FRED-QD's nominal series.",
  "consumer_confidence",                  "EU member states: sourced from the European Commission's own Business and Consumer Survey (a live, monthly, seasonally adjusted balance statistic, e.g. \"AT.CONS\"), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/ec_survey.R. Falls back to the FRED mirror if the EC archive is unavailable for a given run.",
  "cpi_index",                             "EU member states: sourced from Eurostat's Harmonised Index of Consumer Prices (HICP, all-items, prc_hicp_midx), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/eurostat.R. Confirmed live 2026-08-30 to extend to 2025-Q4 for Austria, versus the FRED mirror's confirmed freeze at 2023-Q4 -- a roughly 2-year improvement. HICP's basket/methodology differs somewhat from the US CPI-U basket underlying FRED-QD's CPIAUCSL, but is the standard EU consumer-price measure. Falls back to the FRED mirror if the Eurostat series is unavailable for a given run.",
  "unit_labor_cost",                      "Where Eurostat publishes an index-level series for it (confirmed for Austria: namq_10_lp_ulc, NA_ITEM=NULC_HW, UNIT=I10, hours-based like FRED-QD's ULCNFB), this replaces the default OECD-mirror proxy (OECD MEI unit labour cost, employment-based, % change, confirmed live for AT/DE/FR/GB/US) -- see R/eurostat.R. Not every EU country publishes this index-level series (confirmed absent for Germany, which keeps the OECD-mirror value).",
  "share_price_index",                    "Austria: sourced from the ATX (Austrian Traded Index) via Yahoo Finance (ticker \"^ATX\"), Austria's own actual benchmark index, NOT the generic OECD MEI 'all shares' proxy used for other countries -- see R/yahoo_finance.R. Falls back to the FRED mirror if the Yahoo Finance fetch is unavailable for a given run.",
  "core_cpi_index",                       "Eurostat HICP excluding energy, food, alcohol and tobacco (COICOP=TOT_X_NRG_FOOD) -- the standard ECB/Eurostat \"core inflation\" measure. EU member states only; no FRED-mirror fallback exists for this concept.",
  "food_price_index",                     "Eurostat HICP, food and non-alcoholic beverages (COICOP=CP01). EU member states only; no FRED-mirror fallback exists for this concept.",
  "energy_price_index",                   "Eurostat HICP, energy (COICOP=NRG). EU member states only; no FRED-mirror fallback exists for this concept.",
  "services_price_index",                 "Eurostat HICP, services (overall index excluding goods) (COICOP=SERV). EU member states only; no FRED-mirror fallback exists for this concept.",
  "household_mortgage_loans",             "ECB MFI Balance Sheet Items (BSI): outstanding amounts (stocks, millions of EUR) of loans to households for house purchase, domestic counterpart -- genuinely country-specific (unlike euro_area_household_net_worth_growth), available for euro-area members only. Same purpose category as mortgage_rate, but a different ECB dataflow with an entirely different dimension structure -- see R/ecb.R.",
  "industrial_confidence",                "EU member states only: European Commission Business and Consumer Survey, Industrial Confidence Indicator (\"AT.INDU\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "employment_expectations",              "EU member states only: European Commission Business and Consumer Survey, Employment Expectations Indicator (\"AT.EEI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "construction_confidence",              "EU member states only: European Commission Business and Consumer Survey, Construction Confidence Indicator (\"AT.BUIL\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "retail_confidence",                    "EU member states only: European Commission Business and Consumer Survey, Retail Trade Confidence Indicator (\"AT.RETA\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "economic_sentiment_indicator",         "EU member states only: European Commission Business and Consumer Survey, Economic Sentiment Indicator (\"AT.ESI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "services_confidence",                  "EU member states only: European Commission Business and Consumer Survey, Services Confidence Indicator (\"AT.SERV\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
  "geopolitical_risk",                    "Caldara and Iacoviello's (2022) Geopolitical Risk index, from matteoiacoviello.com's own published data file -- see R/gpr.R. Genuinely country-specific for the 44 countries the source constructs one for (confirmed: Germany, the United States); the global index is used for every other country (confirmed: Austria), not a country-specific gap in this project's own sourcing."
)

## Groups deliberately left unresolved -- see README for why. (Earnings
## and Productivity and Non-Household Balance Sheets are no longer here:
## both now have one live-verified representative concept, see above.)
skipped_groups <- tibble::tribble(
  ~fred_qd_group,               ~reason,
  "Inventories, Orders, and Sales (full)", "Only a retail-sales-volume proxy is included (see coverage); re-checked 2026-08-30 for a manufacturers' new-orders/inventories cross-country equivalent and found none -- US-specific Census Bureau concept, deliberately not attempted."
)

## =====================================================================
## 1. Anchor NIPA concepts: Eurostat preferred for EU members, EXTENDED
##    with OECD QNA's longer history, then IMF QNEA fallback for whatever
##    neither has any data for at all
## =====================================================================
all_anchor_labels <- c(oecd_anchor_concepts$label, "real_household_disposable_income")

## `concept_source[[label]]` is a list(provider=, key=, note=) rather than a
## plain string -- `provider`+`key` are what get written into
## docs/data_sources.csv (step 8 below), so that CSV documents the EXACT
## identifier used, not just a human-readable provider name.
concept_source <- list()

## EXTENDED 2026-08-30: OECD QNA is now fetched for ALL anchor concepts,
## not only ones Eurostat failed to resolve at all, and merged with
## Eurostat's result via merge_prefer() (R/utils.R) -- preferring
## Eurostat's value at each period (it is the closer conceptual match for
## household consumption, see Section 2.2 of the technical report) but
## filling in any period Eurostat has nothing for. Treating OECD as a pure
## "Eurostat returned nothing at all" fallback would silently forfeit
## decades of history for any concept Eurostat covers even partially --
## confirmed live 2026-08-30 that OECD QNA has Austrian real GDP back to
## 1960-Q1, 35 years before Eurostat's 1995-Q1 floor for the same concept.
## This does mean OECD is queried on every EU-country run now, not only
## ones where Eurostat comes up empty -- an intentional trade against
## OECD's rate limit (see README Known issues), made explicit here rather
## than silently reverted.
eurostat_result <- NULL
if (country %in% eu_member_countries) {
  message("Country is an EU member -- trying Eurostat for anchor NIPA concepts...")
  eurostat_result <- fetch_eurostat_anchors(country, start_period = start_period)
}

message("Fetching anchor NIPA concepts for ", country, " from OECD QNA...")
oecd_result <- fetch_oecd_anchors(country, start_period = start_period)

anchor_merged <- merge_prefer(eurostat_result, oecd_result)

oecd_anchor_key <- function(label) {
  row <- oecd_anchor_concepts[oecd_anchor_concepts$label == label, ]
  if (nrow(row) == 1) return(paste0(row$sector, ".", row$transaction))
  paste0(oecd_disposable_income_dims$sector, ".", oecd_disposable_income_dims$transaction, " (DF_QNA_INC_SAV)")
}

for (lbl in all_anchor_labels) {
  from_eurostat <- has_data(eurostat_result, lbl)
  from_oecd <- has_data(oecd_result, lbl)
  if (from_eurostat && from_oecd) {
    na_item <- eurostat_anchor_concepts$na_item[eurostat_anchor_concepts$label == lbl]
    concept_source[[lbl]] <- list(
      provider = "EUROSTAT",
      key = sprintf("namq_10_gdp:%s (extended pre-1995 with OECD_QNA:%s)", na_item, oecd_anchor_key(lbl))
    )
  } else if (from_eurostat) {
    na_item <- eurostat_anchor_concepts$na_item[eurostat_anchor_concepts$label == lbl]
    concept_source[[lbl]] <- list(provider = "EUROSTAT", key = paste0("namq_10_gdp:", na_item))
  } else if (from_oecd) {
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
## 2. BIS credit -- private non-financial sector, households,
##    nonfinancial corporations, and general government (same dataflow,
##    four TC_BORROWERS codes)
## =====================================================================
## EXTENDED 2026-08-30: added TC_BORROWERS="G" (general government),
## confirmed live for AT/DE/US, giving government_debt_to_gdp a
## genuinely cross-country (not EU-only) source via the same
## already-verified dataflow used for the other three sectors -- see
## R/bis.R's header comment for the confirmed CL_TC_BORROWERS codelist.
bis_credit_concepts <- tibble::tribble(
  ~label,                             ~tc_borrowers,
  "credit_to_private_nonfin_sector",  "P",
  "household_credit_to_gdp",          "H",
  "corporate_credit_to_gdp",          "N",
  "government_debt_to_gdp",           "G"
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
## 2b. Geopolitical risk (Caldara-Iacoviello) -- unconditional, like BIS
##     credit above: works for every country, country-specific for the
##     44 the source covers, global index otherwise (see R/gpr.R)
## =====================================================================
gpr <- fetch_geopolitical_risk(country, start_period = start_period)
if (!is.null(gpr)) {
  panel <- dplyr::full_join(panel, gpr, by = "date")
  concept_source[["geopolitical_risk"]] <- list(provider = "GPR", key = attr(gpr, "source_col"))
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

mortgage_loans <- fetch_ecb_household_mortgage_loans(country, start_period = start_period)
if (!is.null(mortgage_loans)) {
  panel <- dplyr::full_join(panel, mortgage_loans, by = "date")
  concept_source[["household_mortgage_loans"]] <- list(provider = "ECB_BSI", key = "A22T.A.1.U6.2250.Z01.E")
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

## =====================================================================
## 4e. EU-specific override: consumer price index from Eurostat's
##     Harmonised Index of Consumer Prices (fresher than the frozen
##     OECD-MEI-via-FRED source above -- see R/eurostat.R)
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- trying Eurostat HICP for cpi_index...")
  hicp <- fetch_eurostat_hicp(country, start_period = start_period)
  if (!is.null(hicp)) {
    panel <- panel %>% dplyr::select(-dplyr::any_of("cpi_index")) %>%
      dplyr::full_join(hicp, by = "date")
    concept_source[["cpi_index"]] <- list(
      provider = "EUROSTAT_HICP",
      key = sprintf("prc_hicp_midx:M.%s.%s.%s", eurostat_hicp_unit, eurostat_hicp_coicop, lookup_ec_country2(country))
    )
  } else {
    message("Eurostat HICP unavailable for ", country, " this run -- keeping the FRED-mirror cpi_index value, if any.")
  }
}

## =====================================================================
## 4f. EU-specific override: unit labor cost from Eurostat's labour
##     productivity and unit-labour-cost dataflow, where it publishes an
##     index-level series (a closer match to FRED-QD's ULCNFB than the
##     employment-based OECD-mirror proxy above) -- see R/eurostat.R
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- trying Eurostat labour productivity/ULC for unit_labor_cost...")
  ulc <- fetch_eurostat_ulc(country, start_period = start_period)
  if (!is.null(ulc)) {
    panel <- panel %>% dplyr::select(-dplyr::any_of("unit_labor_cost")) %>%
      dplyr::full_join(ulc, by = "date")
    concept_source[["unit_labor_cost"]] <- list(
      provider = "EUROSTAT_ULC",
      key = sprintf("namq_10_lp_ulc:Q.%s.SCA.%s.%s", eurostat_ulc_unit, eurostat_ulc_na_item, lookup_ec_country2(country))
    )
  } else {
    message("Eurostat ULC unavailable for ", country, " this run -- keeping the FRED-mirror unit_labor_cost value, if any.")
  }
}

## =====================================================================
## 4g. EU-specific: HICP sub-category breakdown (core, food, energy,
##     services) -- these are new concepts with no FRED-mirror fallback
##     at all, unlike the overrides above, so they simply resolve to NA
##     for non-EU countries via the canonical-schema step below.
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- fetching Eurostat HICP sub-categories...")
  for (i in seq_len(nrow(eurostat_hicp_subcategories))) {
    lbl <- eurostat_hicp_subcategories$label[i]
    coicop <- eurostat_hicp_subcategories$coicop[i]
    sub_hicp <- fetch_eurostat_hicp(country, label = lbl, start_period = start_period, coicop = coicop)
    if (!is.null(sub_hicp)) {
      panel <- dplyr::full_join(panel, sub_hicp, by = "date")
      concept_source[[lbl]] <- list(
        provider = "EUROSTAT_HICP",
        key = sprintf("prc_hicp_midx:M.%s.%s.%s", eurostat_hicp_unit, coicop, lookup_ec_country2(country))
      )
    }
  }
}

## =====================================================================
## 4h. EU-specific: further EC Business and Consumer Survey indicators
##     (economic sentiment, industrial/services/retail/construction
##     confidence, employment expectations) -- same archive already
##     fetched for consumer_confidence, new concepts with no FRED-mirror
##     fallback at all, so they simply resolve to NA for non-EU countries.
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- fetching further EC Business and Consumer Survey indicators...")
  for (i in seq_len(nrow(ec_survey_indicators))) {
    lbl <- ec_survey_indicators$label[i]
    indicator <- ec_survey_indicators$indicator[i]
    sub_survey <- fetch_ec_survey_indicator(country, label = lbl, indicator = indicator, start_period = start_period)
    if (!is.null(sub_survey)) {
      panel <- dplyr::full_join(panel, sub_survey, by = "date")
      concept_source[[lbl]] <- list(provider = "EC_BCS", key = paste0(lookup_ec_country2(country), ".", indicator))
    }
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
  ECB_BSI = "ECB MFI Balance Sheet Items (BSI)",
  FRED_MIRROR = "OECD MEI / BIS (via FRED mirror)",
  EC_BCS = "European Commission Business and Consumer Survey",
  EUROSTAT_HICP = "Eurostat (prc_hicp_midx, HICP)",
  EUROSTAT_ULC = "Eurostat (namq_10_lp_ulc, hours-based ULC)",
  YAHOO_FINANCE = "Yahoo Finance",
  GPR = "Geopolitical Risk Index (Caldara-Iacoviello)"
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

## =====================================================================
## 6b. Plausibility checks -- a country-agnostic "does this look right"
##     signal for every resolved concept, since --validate (Step 7) only
##     works for the United States (see R/plausibility_checks.R header).
##     Runs for every country, including USA, so a researcher adding a
##     brand-new EU country gets the exact same automated first-pass
##     check this project's own reference countries do.
## =====================================================================
plausibility_results <- run_plausibility_checks(panel, canonical_cols)
plausibility_counts <- table(vapply(plausibility_results, function(x) x$status, character(1)))
message(
  "Plausibility checks: ", sum(plausibility_counts[c("PASS")], na.rm = TRUE), " PASS, ",
  sum(plausibility_counts[c("FLAG")], na.rm = TRUE), " FLAG, ",
  sum(plausibility_counts[c("NO_DATA", "TOO_SHORT")], na.rm = TRUE), " NO_DATA/TOO_SHORT"
)
flagged <- Filter(function(x) x$status == "FLAG", plausibility_results)
if (length(flagged) > 0) {
  for (f in flagged) message("  FLAG [", f$label, "]: ", f$detail)
}

coverage <- list(
  country = country,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  start_period = start_period,
  resolved = coverage_rows %>% dplyr::filter(.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label, source) %>% purrr::transpose(),
  skipped = coverage_rows %>% dplyr::filter(!.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  groups_not_attempted = skipped_groups %>% purrr::transpose(),
  plausibility_checks = plausibility_results
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
