## ---------------------------------------------------------------
## concept_dictionary.R -- the single authored source of metadata for
## every one of this project's 38 FRED-QD-style concepts
##
## MOTIVATION: before this file existed, the same concept-level facts
## (which FRED-QD group a concept belongs to, its FRED-QD mnemonic, its
## plausibility-check category) were hand-copied into four separate
## tables that could silently drift apart:
##   - `concept_group_map` in scripts/build_country_panel.R
##   - `concept_notes` in scripts/build_country_panel.R
##   - `fred_qd_validation_map` in R/fred_qd_validation.R
##   - `plausibility_categories` in R/plausibility_checks.R
## They already HAD drifted: `concept_group_map` documented
## `real_gfcf_total`'s FRED-QD reference as FPIx (private FIXED
## investment only, matching this project's own concept_notes
## explanation), while `fred_qd_validation_map` independently validated
## the same concept against GPDIC1 (total private domestic investment,
## a materially different, broader series) -- found live 2026-08-31 when
## `--validate` unexpectedly FAILed real_gfcf_total at corr=0.660. Two
## tables, one fact, one of them wrong: exactly the failure mode a
## single source of truth prevents.
##
## This file is now that single source. `scripts/build_country_panel.R`,
## `R/fred_qd_validation.R` and `R/plausibility_checks.R` all derive
## their working tables from `concept_dictionary` below rather than
## hand-maintaining their own copies -- see each file's own top for the
## one-line `dplyr::transmute()`/`dplyr::filter()` that does the
## derivation. Adding a 39th concept, or correcting a mnemonic, now only
## ever means editing ONE row in ONE table.
##
## Columns:
##   label                  Canonical concept name, used everywhere else
##                          in this project (panel column names, source
##                          registry `variable`, plausibility-check
##                          labels) -- the primary key of this table.
##   fred_qd_group           One of FRED-QD's 14 original category names.
##   fred_qd_mnemonic         The real FRED-QD series this concept
##                          approximates for the United States, or NA if
##                          FRED-QD has no equivalent series at all (see
##                          `us_note` for why).
##   us_note                 NA if `fred_qd_mnemonic` needs no
##                          qualification; otherwise explains either (a)
##                          why no FRED-QD mnemonic exists for this
##                          concept, or (b) how the named mnemonic's own
##                          construction differs from what this project
##                          actually measures for the US (e.g.
##                          unit_labor_cost's FRED-QD reference ULCNFB is
##                          an index level, but the OECD-mirror source
##                          used for every country including the US is a
##                          % change) -- becomes the USA rows' `comment`
##                          in docs/data_sources.csv.
##   cross_country_note       NA if the non-US source is a direct
##                          conceptual match; otherwise explains how the
##                          international source used for every OTHER
##                          country differs from the US/FRED-QD
##                          definition above (e.g. OECD sector S1M vs.
##                          FRED-QD's household-only PCE) -- becomes
##                          every non-USA row's `comment` in
##                          docs/data_sources.csv.
##   plausibility_category    One of "percent", "balance", "growth",
##                          "level" or "level_event_driven" -- see
##                          R/plausibility_checks.R's header for what
##                          each category checks. Every row here is
##                          explicit (including "level", the strictest
##                          default) rather than left NA, so this table
##                          reads as a complete specification, not one
##                          that depends on a hidden fallback -- a
##                          concept added to `R/plausibility_checks.R`'s
##                          checks but NOT yet added as a row here still
##                          falls back to "level" (see
##                          `plausibility_category()`), which only
##                          matters for a concept this table doesn't
##                          know about yet.
## ---------------------------------------------------------------

concept_dictionary <- tibble::tribble(
  ~label,                                  ~fred_qd_group,                   ~fred_qd_mnemonic, ~us_note, ~cross_country_note, ~plausibility_category,
  "real_gdp",                              "Output and Income",              "GDPC1",           NA,
    NA,
    "level",
  "real_household_consumption",            "Output and Income",              "PCECC96",         NA,
    "Source-dependent: for EU members (Eurostat NA_ITEM=P31_S14) this is household-only consumption, a close match to FRED-QD's household-only PCE; where OECD QNA is used instead (sector S1M), it is total-economy final consumption expenditure INCLUDING NPISHs, broader than FRED-QD's definition.",
    "level",
  "real_govt_consumption",                 "Output and Income",              "GCEC1",           NA,
    "SNA/ESA transaction P3, sector S13 (general government) is government consumption expenditure only, whether sourced from OECD or Eurostat; FRED-QD's GCEC1 also includes government gross investment.",
    "level",
  "real_gfcf_total",                       "Output and Income",              "FPIx",            NA,
    "SNA/ESA transaction P51G (gross fixed capital formation) is for ALL sectors (incl. government), whether sourced from OECD or Eurostat; FRED-QD's FPIx is private-sector fixed investment only.",
    "level",
  "real_exports",                          "Output and Income",              "EXPGSC1",         NA,
    NA,
    "level",
  "real_imports",                          "Output and Income",              "IMPGSC1",         NA,
    NA,
    "level",
  "real_household_disposable_income",      "Output and Income",              "DPIC96",          NA,
    "OECD's quarterly household disposable income (DF_QNA_INC_SAV) is published for only 11 countries (AUS, BRA, CAN, CHL, EST, GRC, HUN, LTU, LUX, LVA, ZAF); absent for most others, confirmed absent for DEU/AUT/USA/FRA/GBR.",
    "level",
  "industrial_production",                 "Industrial Production",          "INDPRO",          NA,
    NA,
    "level",
  "industrial_confidence",                 "Industrial Production",          NA,
    "No FRED-QD equivalent; the EC's Industrial Confidence Indicator (since 1985) is a standard input to the OECD's Composite Leading Indicators for many countries, with documented leading-indicator value for industrial production/GDP turning points.",
    "EU member states only: European Commission Business and Consumer Survey, Industrial Confidence Indicator (\"AT.INDU\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "unemployment_rate",                     "Employment and Unemployment",    "UNRATE",          NA,
    NA,
    "percent",
  "employment_rate",                       "Employment and Unemployment",    NA,
    "No FRED-QD employment-rate series; nearest are CE16OV (level) and CIVPART (participation rate).",
    "Employment-to-population ratio, ages 15-64 (OECD MEI); included as a standard cross-country labour-market indicator even though FRED-QD has no direct equivalent (see us_note).",
    "percent",
  "employment_expectations",               "Employment and Unemployment",    NA,
    "No FRED-QD equivalent; DG ECFIN's own purpose-built leading indicator for employment turning points (introduced 2013 specifically because the surveys' employment sub-components lead employment growth).",
    "EU member states only: European Commission Business and Consumer Survey, Employment Expectations Indicator (\"AT.EEI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "house_price_real",                      "Housing",                        "USSTHPI",         NA,
    NA,
    "level",
  "construction_confidence",               "Housing",                        NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the construction sector, companion to house_price_real.",
    "EU member states only: European Commission Business and Consumer Survey, Construction Confidence Indicator (\"AT.BUIL\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "retail_sales_volume",                   "Inventories, Orders, and Sales", "RSAFSx",          NA,
    "OECD MEI retail sales volume is not published for the USA itself via this mirror -- a genuine coverage gap for that one country, not a wrong code.",
    "level",
  "retail_confidence",                     "Inventories, Orders, and Sales", NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the retail sector, companion to retail_sales_volume.",
    "EU member states only: European Commission Business and Consumer Survey, Retail Trade Confidence Indicator (\"AT.RETA\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "cpi_index",                             "Prices",                         "CPIAUCSL",        NA,
    "EU member states: sourced from Eurostat's Harmonised Index of Consumer Prices (HICP, all-items, prc_hicp_midx), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/eurostat.R. Confirmed live 2026-08-30 to extend to 2025-Q4 for Austria, versus the FRED mirror's confirmed freeze at 2023-Q4 -- a roughly 2-year improvement. HICP's basket/methodology differs somewhat from the US CPI-U basket underlying FRED-QD's CPIAUCSL, but is the standard EU consumer-price measure. Falls back to the FRED mirror if the Eurostat series is unavailable for a given run.",
    "balance",
  "core_cpi_index",                        "Prices",                         "CPILFESL",        NA,
    "Eurostat HICP excluding energy, food, alcohol and tobacco (COICOP=TOT_X_NRG_FOOD) -- the standard ECB/Eurostat \"core inflation\" measure. EU member states only; no FRED-mirror fallback exists for this concept.",
    "level",
  "food_price_index",                      "Prices",                         NA,
    "No standalone CPI-food mnemonic in FRED-QD's 245-series list (the closest entries are PCE-side, e.g. DFXARG3Q086SBEA); included as a standard EU/ECB headline-inflation breakdown component.",
    "Eurostat HICP, food and non-alcoholic beverages (COICOP=CP01). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level",
  "energy_price_index",                    "Prices",                         NA,
    "No standalone CPI-energy mnemonic in FRED-QD's 245-series list (the closest entries are producer-price WPU0531/WPU0561 or the global OILPRICEx benchmark, none implemented here); included as a standard EU/ECB headline-inflation breakdown component.",
    "Eurostat HICP, energy (COICOP=NRG). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level",
  "services_price_index",                  "Prices",                         "CUSR0000SAS",     NA,
    "Eurostat HICP, services (overall index excluding goods) (COICOP=SERV). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level",
  "unit_labor_cost",                       "Earnings and Productivity",      "ULCNFB",
    "FRED-QD's ULCNFB is a nonfarm-business, hours-based unit-labor-cost INDEX; the OECD-mirror series used for every country (incl. the US) is an employment-based % CHANGE -- related concepts, different construction.",
    "Where Eurostat publishes an index-level series for it (confirmed for Austria: namq_10_lp_ulc, NA_ITEM=NULC_HW, UNIT=I10, hours-based like FRED-QD's ULCNFB), this replaces the default OECD-mirror proxy (OECD MEI unit labour cost, employment-based, % change, confirmed live for AT/DE/FR/GB/US) -- see R/eurostat.R. Not every EU country publishes this index-level series (confirmed absent for Germany, which keeps the OECD-mirror value).",
    "balance",
  "long_term_rate",                        "Interest Rates",                 "GS10",            NA,
    NA,
    "percent",
  "short_term_rate",                       "Interest Rates",                 "TB3MS",           NA,
    NA,
    "percent",
  "mortgage_rate",                         "Interest Rates",                 "MORTGAGE30US",
    "FRED-QD's MORTGAGE30US is a 30-year FIXED-rate average; the ECB series used for euro-area countries is a new-business AAR/NDER rate across all initial rate fixation periods (fixed and variable combined) -- related but not an identical construction.",
    "ECB MFI Interest Rate Statistics (MIR): new-business loans to households for house purchase, all initial rate fixation periods combined -- genuinely country-specific (unlike euro_area_household_net_worth_growth above), available for euro-area members only.",
    "percent",
  "credit_to_private_nonfin_sector",       "Money and Credit",               NA,
    "FRED-QD tracks credit by purpose/level (BUSLOANSx, TOTALSLx, REALLNx, ...), not one combined %GDP series like BIS's.",
    "BIS reports this as a stock, % of GDP (private non-financial sector = households + nonfinancial corporations combined).",
    "percent",
  "household_mortgage_loans",              "Money and Credit",               "REALLNx",
    "FRED-QD's REALLNx is REAL (Core-PCE-deflated) dollars; the ECB BSI series used for euro-area countries is a NOMINAL euro-denominated stock of outstanding MFI loans to households for house purchase -- related but not an identical construction, and not deflated here.",
    "ECB MFI Balance Sheet Items (BSI): outstanding amounts (stocks, millions of EUR) of loans to households for house purchase, domestic counterpart -- genuinely country-specific (unlike euro_area_household_net_worth_growth), available for euro-area members only. Same purpose category as mortgage_rate, but a different ECB dataflow with an entirely different dimension structure -- see R/ecb.R.",
    "level",
  "euro_area_household_net_worth_growth",  "Household Balance Sheets",       "TNWBSHNOx",       NA,
    "ECB QSA_PUB publishes household net worth only for the euro-area AGGREGATE (REF_AREA=I8) -- every euro-area country gets this same figure; it is not country-specific.",
    "growth",
  "household_credit_to_gdp",               "Household Balance Sheets",       NA,
    "No %GDP household-credit series in FRED-QD; FRED itself mirrors the same underlying BIS series for the US as HDTGPDUSQ163N.",
    "BIS credit to households & NPISHs, % of GDP -- country-specific (unlike the ECB net-worth aggregate above).",
    "percent",
  "corporate_credit_to_gdp",               "Non-Household Balance Sheets",   NA,
    "FRED-QD's TLBSNNCBx is a dollar-level series, not %GDP; no confirmed FRED %GDP analog for the US was found.",
    "BIS credit to nonfinancial corporations, % of GDP -- country-specific.",
    "percent",
  "government_debt_to_gdp",                "Non-Household Balance Sheets",   "GFDEGDQ188S",
    "FRED-QD's GFDEGDQ188S is US FEDERAL debt only (excludes state/local government); the BIS series used for every country (incl. the US) is credit to the WHOLE general-government sector (all levels combined) -- related but broader-scoped concepts, not identical.",
    "BIS credit to general government (all levels: federal/state/local combined), % of GDP -- BIS's own credit-statistics methodology treats this as a close proxy for gross government debt; genuinely country-specific and, unlike the euro-area-only mortgage_rate/consumer_confidence overrides, available for non-EU countries too (confirmed live for AT/DE/US).",
    "percent",
  "fx_rate_to_usd",                        "Exchange Rates",                 NA,
    "Not meaningful for the US itself -- this concept is a foreign currency's price in USD.",
    "OECD MEI bilateral exchange rate, national currency per USD.",
    "level",
  "real_effective_exchange_rate",          "Exchange Rates",                 "TWEXAFEGSMTHx",
    "FRED-QD's series is a NOMINAL trade-weighted index against advanced foreign economies only; the OECD-mirror series used for other countries is REAL (price-adjusted) and broader -- related but not identical.",
    "OECD real (price-adjusted) effective exchange rate index -- see us_note for how this differs from FRED-QD's nominal series.",
    "level",
  "consumer_confidence",                   "Other",                          "UMCSENTx",        NA,
    "EU member states: sourced from the European Commission's own Business and Consumer Survey (a live, monthly, seasonally adjusted balance statistic, e.g. \"AT.CONS\"), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/ec_survey.R. Falls back to the FRED mirror if the EC archive is unavailable for a given run.",
    "balance",
  "economic_sentiment_indicator",          "Other",                          NA,
    "No FRED-QD equivalent; DG ECFIN's own flagship composite indicator (weighted average of industry/services/consumer/retail/construction survey balances), explicitly constructed and empirically validated to track and lead euro-area GDP growth.",
    "EU member states only: European Commission Business and Consumer Survey, Economic Sentiment Indicator (\"AT.ESI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "services_confidence",                   "Other",                          NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the services sector.",
    "EU member states only: European Commission Business and Consumer Survey, Services Confidence Indicator (\"AT.SERV\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance",
  "geopolitical_risk",                     "Other",                          NA,
    "No FRED-QD equivalent; the Caldara-Iacoviello (2022) Geopolitical Risk index, the standard academic/policy measure -- country-specific for the 44 countries the source covers (confirmed: includes DEU/USA, excludes AUT), global index used otherwise (see R/gpr.R).",
    "Caldara and Iacoviello's (2022) Geopolitical Risk index, from matteoiacoviello.com's own published data file -- see R/gpr.R. Genuinely country-specific for the 44 countries the source constructs one for (confirmed: Germany, the United States); the global index is used for every other country (confirmed: Austria), not a country-specific gap in this project's own sourcing.",
    "level_event_driven",
  "share_price_index",                     "Stock Markets",                  "S&P 500",         NA,
    "Austria: sourced from the ATX (Austrian Traded Index) via Yahoo Finance (ticker \"^ATX\"), Austria's own actual benchmark index, NOT the generic OECD MEI 'all shares' proxy used for other countries -- see R/yahoo_finance.R. Falls back to the FRED mirror if the Yahoo Finance fetch is unavailable for a given run.",
    "level"
)
