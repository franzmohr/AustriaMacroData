## ---------------------------------------------------------------
## concept_dictionary.R -- the single authored source of metadata for
## every one of this project's 114 FRED-QD-style concepts
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
##                          "level", "level_event_driven", "nonneg_seasonal" or "nonneg_event_driven" -- see
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
  ~label,                                  ~fred_qd_group,                   ~fred_qd_mnemonic, ~us_note, ~cross_country_note, ~plausibility_category, ~available_monthly,
  "real_gdp",                              "Output and Income",              "GDPC1",           NA,
    NA,
    "level", FALSE,
  "real_household_consumption",            "Output and Income",              "PCECC96",         NA,
    "Source-dependent: for EU members (Eurostat NA_ITEM=P31_S14) this is household-only consumption, a close match to FRED-QD's household-only PCE; where OECD QNA is used instead (sector S1M), it is total-economy final consumption expenditure INCLUDING NPISHs, broader than FRED-QD's definition.",
    "level", FALSE,
  "real_govt_consumption",                 "Output and Income",              "GCEC1",           NA,
    "SNA/ESA transaction P3, sector S13 (general government) is government consumption expenditure only, whether sourced from OECD or Eurostat; FRED-QD's GCEC1 also includes government gross investment.",
    "level", FALSE,
  "real_gfcf_total",                       "Output and Income",              "FPIx",            NA,
    "SNA/ESA transaction P51G (gross fixed capital formation) is for ALL sectors (incl. government), whether sourced from OECD or Eurostat; FRED-QD's FPIx is private-sector fixed investment only.",
    "level", FALSE,
  "real_exports",                          "Output and Income",              "EXPGSC1",         NA,
    NA,
    "level", FALSE,
  "real_imports",                          "Output and Income",              "IMPGSC1",         NA,
    NA,
    "level", FALSE,
  "inventory_change_to_gdp",               "Output and Income",              "A014RE1Q156NBEA", NA,
    "Change in inventories as a PERCENT OF GDP (both nominal), signed -- not a real level like the other expenditure components, because Eurostat publishes no chain-linked volume for it (a signed flow that crosses zero, for which chain-linked volumes are not additive; see R/inventories.R). EU member states: Eurostat namq_10_gdp, NA_ITEM=P52 (excluding valuables, P53), UNIT=PC_GDP, seasonally and calendar adjusted -- the same construction as FRED-QD's A014RE1Q156NBEA, except that P52 covers inventories of all sectors where FRED-QD's covers private inventories only. From 1995 for Austria (1991 for Germany). Outside the EU only the United States resolves (FRED-QD's own series); NA elsewhere.",
    "balance", FALSE,
  "real_household_disposable_income",      "Output and Income",              "DPIC96",          NA,
    "EU member states: Eurostat quarterly sector accounts, nasq_10_nf_tr B6G for households and NPISH (S14_S15), current prices, seasonally and calendar adjusted, deflated by the implicit deflator of household and NPISH final consumption (namq_10_gdp P31_S14_S15, CP_MEUR / CLV20_MEUR), so million euro at chain-linked 2020 prices -- the construction of FRED-QD's DPIC96, which deflates personal disposable income (also including NPISH) by the PCE price index. From 1999-Q1 for Austria and Germany; its quarterly growth matches Eurostat's own real per-capita indicator (nasq_10_ki B6G_R_HAB_GR) at correlation 0.998 for Austria and 0.974 for Germany, the gap being population growth (checked live 2026-10-04). Austria's 2022-Q3/Q4 swing (+6.4%, -5.4% q/q) is real: one-off energy and anti-inflation transfers. Outside the EU the OECD's DF_QNA_INC_SAV is tried, but it carries the total economy (S1) only, so it is NA for most countries, including the USA.",
    "level", FALSE,
  "industrial_production",                 "Industrial Production",          "INDPRO",          NA,
    "EU member states: sourced from Eurostat short-term statistics (sts_inpr_q, NACE B-D, seasonally and calendar adjusted, index 2021 = 100), NOT the OECD-MEI-via-FRED mirror used elsewhere -- see R/eurostat_sts.R. The mirror is frozen: AUTPROINDQISMEI was confirmed live 2026-09-25 to stop at 2024-Q1 while every other concept in the panel ran to the current quarter, which silently truncates any model estimated on it. The mirror earlier history (back to 1955 for Austria) is spliced on, rescaled to the Eurostat base at the overlap. Read that spliced history with care: over the 334 months the two share they correlate 0.896 in log differences, so they are close relatives rather than the same series.",
    "level", TRUE,
  "industrial_confidence",                 "Industrial Production",          NA,
    "No FRED-QD equivalent; the EC's Industrial Confidence Indicator (since 1985) is a standard input to the OECD's Composite Leading Indicators for many countries, with documented leading-indicator value for industrial production/GDP turning points.",
    "EU member states only: European Commission Business and Consumer Survey, Industrial Confidence Indicator (\"AT.INDU\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "unemployment_rate",                     "Employment and Unemployment",    "UNRATE",          NA,
    NA,
    "percent", TRUE,
  "employment_rate",                       "Employment and Unemployment",    NA,
    "No FRED-QD employment-rate series; nearest are CE16OV (level) and CIVPART (participation rate).",
    "Employment-to-population ratio, ages 15-64 (OECD MEI); included as a standard cross-country labour-market indicator even though FRED-QD has no direct equivalent (see us_note).",
    "percent", FALSE,
  "hours_worked",                          "Employment and Unemployment",    "HOANBS",          
    "HOANBS is hours of all persons in the NONFARM BUSINESS sector; the series here is the total economy, which additionally includes general government, households as employers and the farm sector. The broader coverage is what the national-accounts source publishes and what pairs with this panel's own total-economy real_gdp.",
    "EU member states only: Eurostat namq_10_a10_e, total hours worked, domestic concept (NA_ITEM=EMP_DC, employees and self-employed together), seasonally and calendar adjusted -- see R/eurostat.R. No FRED-mirror fallback exists: FRED's OECD mirror carries hours PER WORKER for some countries and total hours for none, so this resolves to NA outside the EU.",
    "level", FALSE,
  "population",                            "Employment and Unemployment",    NA,
    "No FRED-QD equivalent; none of FRED-QD's 245 series is a population count. A live --country USA run resolves this concept to the BEA's total population including armed forces overseas (FRED POPTHM, monthly, averaged within the quarter) -- see R/population.R.",
    "Total resident population in THOUSANDS OF PERSONS, the per-capita denominator for real_gdp, real_household_consumption and hours_worked. EU member states: Eurostat namq_10_pe, total population, national concept (NA_ITEM=POP_NC, UNIT=THS_PER, S_ADJ=SCA) -- the population figure of the quarterly national accounts themselves, so a per-capita ratio against this panel's real_gdp is internally consistent. Quarterly from 1995 for Austria (1991 for Germany); the annual series that reaches further back is not interpolated onto quarters. Outside the EU only countries with an explicit entry in R/population.R's national_population table resolve (currently the United States); FRED mirrors population for most other countries only annually, so this is NA for them rather than an interpolation.",
    "level", FALSE,
  "employment_expectations",               "Employment and Unemployment",    NA,
    "No FRED-QD equivalent; DG ECFIN's own purpose-built leading indicator for employment turning points (introduced 2013 specifically because the surveys' employment sub-components lead employment growth).",
    "EU member states only: European Commission Business and Consumer Survey, Employment Expectations Indicator (\"AT.EEI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "house_price_real",                      "Housing",                        "USSTHPI",         NA,
    NA,
    "level", FALSE,
  "construction_confidence",               "Housing",                        NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the construction sector, companion to house_price_real.",
    "EU member states only: European Commission Business and Consumer Survey, Construction Confidence Indicator (\"AT.BUIL\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_sales_volume",                   "Inventories, Orders, and Sales", "RSAFSx",          NA,
    "EU member states: sourced from Eurostat short-term statistics (sts_trtu_q, NACE G47, indicator VOL_SLS -- the VOLUME of sales, not NETTUR, which is turnover in current prices), NOT the OECD-MEI-via-FRED mirror, which is frozen at 2024-Q1 -- see R/eurostat_sts.R. The mirror earlier history is spliced on and rescaled at the overlap, where the two correlate 0.998 in log differences. OECD MEI retail sales volume is not published for the USA itself via this mirror -- a genuine coverage gap for that one country, not a wrong code.",
    "level", TRUE,
  "retail_confidence",                     "Inventories, Orders, and Sales", NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the retail sector, companion to retail_sales_volume.",
    "EU member states only: European Commission Business and Consumer Survey, Retail Trade Confidence Indicator (\"AT.RETA\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "cpi_index",                             "Prices",                         "CPIAUCSL",        NA,
    "EU member states: sourced from Eurostat's Harmonised Index of Consumer Prices (HICP, all-items, prc_hicp_minr at 2025=100; the older prc_hicp_midx was frozen at 2025-12 when Eurostat rebased in 2026), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/eurostat.R. Confirmed live 2026-10-03 to run to 2026-09 for Austria and Germany, versus the FRED mirror's confirmed freeze at 2023-Q4. HICP's basket/methodology differs somewhat from the US CPI-U basket underlying FRED-QD's CPIAUCSL, but is the standard EU consumer-price measure. Countries outside the EU take their own national index instead (R/fred_mirror.R national_cpi_index; CPIAUCSL for the United States) rather than the OECD MEI mirror, whose only CPI series are GROWTH RATES -- CPALTT01{cc2}Q657N runs -2.83 to 3.95 for the US. Until 2026-09-25 this column therefore held an index for EU members and a percent change for everyone else; it is one statistic everywhere now, which is why its plausibility category is the strict 'level' again rather than a band wide enough for both.",
    "level", TRUE,
  "core_cpi_index",                        "Prices",                         "CPILFESL",        NA,
    "Eurostat HICP excluding energy, food, alcohol and tobacco (COICOP=TOT_X_NRG_FOOD) -- the standard ECB/Eurostat \"core inflation\" measure. EU member states only; no FRED-mirror fallback exists for this concept.",
    "level", TRUE,
  "food_price_index",                      "Prices",                         NA,
    "No standalone CPI-food mnemonic in FRED-QD's 245-series list (the closest entries are PCE-side, e.g. DFXARG3Q086SBEA); included as a standard EU/ECB headline-inflation breakdown component.",
    "Eurostat HICP, food and non-alcoholic beverages (COICOP=CP01). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level", TRUE,
  "energy_price_index",                    "Prices",                         NA,
    "No standalone CPI-energy mnemonic in FRED-QD's 245-series list (the closest entries are producer-price WPU0531/WPU0561 or the global OILPRICEx benchmark, none implemented here); included as a standard EU/ECB headline-inflation breakdown component.",
    "Eurostat HICP, energy (COICOP=NRG). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level", TRUE,
  "services_price_index",                  "Prices",                         "CUSR0000SAS",     NA,
    "Eurostat HICP, services (overall index excluding goods) (COICOP=SERV). EU member states only; no FRED-mirror fallback exists for this concept.",
    "level", TRUE,
  "unit_labor_cost",                       "Earnings and Productivity",      "ULCNFB",
    "FRED-QD's ULCNFB is a nonfarm-business, hours-based unit-labor-cost INDEX; the OECD-mirror series used for every country (incl. the US) is an employment-based % CHANGE -- related concepts, different construction.",
    "Where Eurostat publishes an index-level series for it (confirmed for Austria: namq_10_lp_ulc, NA_ITEM=NULC_HW, UNIT=I10, hours-based like FRED-QD's ULCNFB), this replaces the default OECD-mirror proxy (OECD MEI unit labour cost, employment-based, % change, confirmed live for AT/DE/FR/GB/US) -- see R/eurostat.R. Not every EU country publishes this index-level series, and which do changes over time: it was confirmed absent for Germany when this note was first written, and confirmed present for Germany on 2026-09-24, so Germany now resolves through Eurostat rather than keeping the OECD-mirror value. A country for which Eurostat has nothing still falls back to the mirror.",
    "balance", FALSE,
  "long_term_rate",                        "Interest Rates",                 "GS10",            NA,
    NA,
    "percent", TRUE,
  "short_term_rate",                       "Interest Rates",                 "TB3MS",           NA,
    NA,
    "percent", TRUE,
  "government_bond_yield_2y",              "Interest Rates",                 NA,
    "No FRED-QD equivalent: FRED-QD's Treasury yields are GS1, GS5 and GS10, with no 2-year maturity. The US value is FRED's GS2, the 2-year Treasury constant-maturity yield, monthly average of daily values, from 1976-06.",
    "Germany: Deutsche Bundesbank, zero-coupon yield on listed Federal securities at a residual maturity of 2.0 years (Svensson term structure, BBSIS.D.I.ZST.ZI.EUR.S1311.B.A604.R02XX.R.A.A._Z._Z.A), averaged over the month's daily values from 1997-08 and end-of-month values back to 1972-09. NA for Austria and every other country: no Austrian yield at a fixed 2-year maturity is published (the OeNB carries issue yields and an all-bond average only, the ECB a euro-area aggregate only) -- see R/gov_yields.R.",
    "percent", TRUE,
  "government_bond_yield_5y",              "Interest Rates",                 "GS5",             NA,
    "Germany: Deutsche Bundesbank, zero-coupon yield on listed Federal securities at a residual maturity of 5.0 years (Svensson term structure, BBSIS.D.I.ZST.ZI.EUR.S1311.B.A604.R05XX.R.A.A._Z._Z.A), averaged over the month's daily values from 1997-08 and end-of-month values back to 1972-09. A zero-coupon yield, where FRED-QD's GS5 is a par (constant-maturity) yield; at five years the two differ by a few basis points. United States: GS5 itself, from 1953-04. NA for Austria and every other country -- see government_bond_yield_2y.",
    "percent", TRUE,
  "mortgage_rate",                         "Interest Rates",                 "MORTGAGE30US",
    "FRED-QD's MORTGAGE30US is a 30-year FIXED-rate average; the ECB series used for euro-area countries is a new-business AAR/NDER rate across all initial rate fixation periods (fixed and variable combined) -- related but not an identical construction.",
    "ECB MFI Interest Rate Statistics (MIR): new-business loans to households for house purchase, all initial rate fixation periods combined -- genuinely country-specific (unlike euro_area_household_net_worth_growth above), available for euro-area members only.",
    "percent", TRUE,
  "mortgage_rate_pure_new_loans",          "Interest Rates",                 NA,
    "No FRED-QD equivalent: MORTGAGE30US (see mortgage_rate) is a survey rate for one fixed-rate product, and the US has no published split of mortgage pricing into new loans and renegotiations.",
    "ECB MFI Interest Rate Statistics (MIR), key A2C.R.A.2250.EUR.P: the rate on PURE new loans to households for house purchase (IR_BUS_COV=P), i.e. mortgage_rate without renegotiations of existing loans, all initial rate fixation periods combined. Euro-area members only. Published from 2017-08 for Austria; earlier months back to 2017-01 are computed from the MIR identity, r_P = (r_N * N - r_R * R) / (N - R), new business less renegotiations, which reproduces every published month to within 0.012 pp -- see R/ecb.R.",
    "percent", TRUE,
  "mortgage_rate_oenb",                    "Interest Rates",                 NA,
    "No FRED-QD equivalent beyond mortgage_rate's MORTGAGE30US: this is the same new-business rate as mortgage_rate, from the Austrian national central bank, and exists for Austria only.",
    "OeNB data service, data set 23, position VDBZSBSZN10010: interest rate on new business in loans to households for housing purposes, all initial rate fixation periods combined, % p.a. AUSTRIA ONLY (NA for every other country). From 2000-01 on it is the ECB's mortgage_rate (MIR A2C.R.A.2250.EUR.N) to the last decimal in every month; it reaches back to 1995-12, before the harmonised MIR statistics -- see R/oenb.R.",
    "percent", TRUE,
  "credit_to_private_nonfin_sector",       "Money and Credit",               NA,
    "FRED-QD tracks credit by purpose/level (BUSLOANSx, TOTALSLx, REALLNx, ...), not one combined %GDP series like BIS's.",
    "BIS reports this as a stock, % of GDP (private non-financial sector = households + nonfinancial corporations combined).",
    "percent", FALSE,
  "household_mortgage_loans",              "Money and Credit",               "REALLNx",
    "FRED-QD's REALLNx is REAL (Core-PCE-deflated) dollars; the ECB BSI series used for euro-area countries is a NOMINAL euro-denominated stock of outstanding MFI loans to households for house purchase -- related but not an identical construction, and not deflated here.",
    "ECB MFI Balance Sheet Items (BSI): outstanding amounts (stocks, millions of EUR) of loans to households for house purchase, domestic counterpart -- genuinely country-specific (unlike euro_area_household_net_worth_growth), available for euro-area members only. Same purpose category as mortgage_rate, but a different ECB dataflow with an entirely different dimension structure -- see R/ecb.R.",
    "level", TRUE,
  "mortgage_new_lending",                  "Money and Credit",               NA,
    "No FRED-QD equivalent: FRED-QD tracks credit as outstanding stocks (REALLNx and the like), and no US source publishes a monthly flow of new mortgage loans comparable to the ECB's.",
    "ECB MFI Interest Rate Statistics (MIR), key A2C.B.A.2250.EUR.P: the business volume of PURE new loans to households for house purchase (renegotiations excluded), millions of EUR, NOMINAL and not seasonally adjusted. A FLOW, so the quarterly panel holds the SUM of the quarter's three months, and only complete quarters, where every other monthly concept is averaged. The flow counterpart to household_mortgage_loans' stock; euro-area members only. Published from 2017-08 for Austria; earlier months back to 2014-12 are new business less renegotiations (IR_BUS_COV N minus R), an identity that reproduces every published month exactly -- see R/ecb.R.",
    "level", TRUE,
  "mortgage_new_lending_oenb",             "Money and Credit",               NA,
    "No FRED-QD equivalent: as for mortgage_new_lending, no US source publishes a monthly flow of new mortgage loans.",
    "OeNB data service, data set 100140002, position VDBMSKNWOHNBAU: new loans (excluding revolving loans) to households for housing purposes, millions of EUR per month, NOMINAL and not seasonally adjusted, from 2009-01. AUSTRIA ONLY (NA for every other country). The OeNB's monthly statistics rather than the MIR sample, but the same concept as mortgage_new_lending (pure new loans): over their overlap the monthly changes of the two correlate at 0.994, and this series is eight years longer. A FLOW, so the quarterly panel holds the SUM of complete quarters -- see R/oenb.R.",
    "level", TRUE,
  "euro_area_household_net_worth_growth",  "Household Balance Sheets",       "TNWBSHNOx",       NA,
    "ECB QSA_PUB publishes household net worth only for the euro-area AGGREGATE (REF_AREA=I8) -- every euro-area country gets this same figure; it is not country-specific.",
    "growth", FALSE,
  "household_credit_to_gdp",               "Household Balance Sheets",       NA,
    "No %GDP household-credit series in FRED-QD; FRED itself mirrors the same underlying BIS series for the US as HDTGPDUSQ163N.",
    "BIS credit to households & NPISHs, % of GDP -- country-specific (unlike the ECB net-worth aggregate above).",
    "percent", FALSE,
  "corporate_credit_to_gdp",               "Non-Household Balance Sheets",   NA,
    "FRED-QD's TLBSNNCBx is a dollar-level series, not %GDP; no confirmed FRED %GDP analog for the US was found.",
    "BIS credit to nonfinancial corporations, % of GDP -- country-specific.",
    "percent", FALSE,
  "government_debt_to_gdp",                "Non-Household Balance Sheets",   "GFDEGDQ188S",
    "FRED-QD's GFDEGDQ188S is US FEDERAL debt only (excludes state/local government); the BIS series used for every country (incl. the US) is credit to the WHOLE general-government sector (all levels combined) -- related but broader-scoped concepts, not identical.",
    "BIS credit to general government (all levels: federal/state/local combined), % of GDP, at NOMINAL value (VALUATION=N) -- BIS's own credit-statistics methodology treats this as a close proxy for gross government debt; genuinely country-specific and, unlike the euro-area-only mortgage_rate/consumer_confidence overrides, available for non-EU countries too (confirmed live for AT/DE/US). Nominal rather than market value since 2026-09-14: the market-value series revalues government bonds with their prices, so it swings with interest rates (Austria: 100.7% of GDP in 2020, 75.2% in 2025-Q4), whereas the nominal series reads 81.5% for 2025-Q4, against 81.3% for Eurostat's Maastricht debt ratio.",
    "percent", FALSE,
  "government_primary_balance_to_gdp",     "Non-Household Balance Sheets",   NA,
    "No FRED-QD equivalent; FRED-QD carries no general-government primary balance. Added as the flow companion to government_debt_to_gdp's stock: the primary balance is one of the proximate drivers of the debt ratio in the debt-dynamics identity, beside interest payments and the growth-interest differential.",
    "EU member states only: Eurostat quarterly government finance statistics (gov_10q_ggnfa), general government (S13), net lending/borrowing (B9) plus interest payable (D41PAY), both in % of GDP -- see R/eurostat.R. NOT seasonally adjusted: Eurostat publishes a seasonally adjusted B9 but no seasonally adjusted D41PAY, and summing an adjusted with an unadjusted series would be neither. The ratio is to the same quarter's GDP, so a four-quarter average is the annual equivalent. No non-EU fallback exists for this concept.",
    "balance", FALSE,
  "fx_rate_to_usd",                        "Exchange Rates",                 NA,
    "Not meaningful for the US itself -- this concept is a foreign currency's price in USD.",
    "OECD MEI bilateral exchange rate, national currency per USD.",
    "level", TRUE,
  "real_effective_exchange_rate",          "Exchange Rates",                 "TWEXAFEGSMTHx",
    "FRED-QD's series is a NOMINAL trade-weighted index against advanced foreign economies only; the OECD-mirror series used for other countries is REAL (price-adjusted) and broader -- related but not identical.",
    "OECD real (price-adjusted) effective exchange rate index -- see us_note for how this differs from FRED-QD's nominal series.",
    "level", TRUE,
  "consumer_confidence",                   "Other",                          "UMCSENTx",        NA,
    "EU member states: sourced from the European Commission's own Business and Consumer Survey (a live, monthly, seasonally adjusted balance statistic, e.g. \"AT.CONS\"), NOT the frozen OECD-MEI-via-FRED mirror used for non-EU countries -- see R/ec_survey.R. Falls back to the FRED mirror if the EC archive is unavailable for a given run.",
    "balance", TRUE,
  "consumer_financial_situation_past",      "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 1: How the household's financial situation has changed over the last 12 months (a component of consumer_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 1, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.1.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_financial_situation_expected",  "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 2: How the household expects its financial situation to change over the next 12 months (one of the four components of consumer_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 2, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.2.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_economic_situation_past",       "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 3: How the general economic situation in the country has changed over the last 12 months.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 3, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.3.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_economic_situation_expected",   "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 4: How the general economic situation in the country is expected to change over the next 12 months (a component of consumer_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 4, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.4.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_price_trends_past",             "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 5: How consumer prices are perceived to have moved over the last 12 months -- perceived inflation.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 5, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.5.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_price_expectations",            "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 6: How consumer prices are expected to move over the next 12 months, relative to the last 12 -- a qualitative inflation expectation.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 6, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.6.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_unemployment_expectations",     "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 7: How unemployment is expected to change over the next 12 months; a POSITIVE balance means rising unemployment is expected.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 7, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.7.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_major_purchases_now",           "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 8: Whether now is the right moment to make major purchases (furniture, electrical goods).",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 8, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.8.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_major_purchases_expected",      "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 9: Whether the household expects to spend more or less on major purchases over the next 12 months (a component of consumer_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 9, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.9.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_savings_expected",              "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 11: How likely the household is to save any money over the next 12 months.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 11, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.11.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_household_finances_now",        "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 12: Which statement describes the household's current financial situation, from saving a lot to running into debt.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 12, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.12.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "consumer_home_purchase_intentions",      "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 14: How likely the household is to buy or build a home within the next 12 months -- asked QUARTERLY only.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 14, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.14.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "consumer_home_improvement_intentions",   "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD carries only the Michigan sentiment index (UMCSENTx), not its individual questions. EC consumer survey question 15: How likely the household is to spend on home improvements over the next 12 months -- asked QUARTERLY only.",
    "EU member states only: European Commission Business and Consumer Survey, consumer survey question 15, balance of all consumers, seasonally adjusted (\"CONS.AT.TOT.15.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "industry_production_past",                "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 1: Production trend observed in recent months.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 1, balance, seasonally adjusted (\"INDU.AT.TOT.1.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_order_books",                    "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 2: Assessment of order-book levels (a component of industrial_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 2, balance, seasonally adjusted (\"INDU.AT.TOT.2.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_export_order_books",             "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 3: Assessment of export order-book levels.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 3, balance, seasonally adjusted (\"INDU.AT.TOT.3.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_stocks_finished_products",       "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 4: Assessment of stocks of finished products; a POSITIVE balance means stocks are judged too large (enters industrial_confidence with a negative sign).",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 4, balance, seasonally adjusted (\"INDU.AT.TOT.4.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_production_expectations",        "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 5: Production expectations for the months ahead (a component of industrial_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 5, balance, seasonally adjusted (\"INDU.AT.TOT.5.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_selling_price_expectations",     "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 6: Selling price expectations for the months ahead -- manufacturers' qualitative price-setting intentions.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 6, balance, seasonally adjusted (\"INDU.AT.TOT.6.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_employment_expectations",        "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 7: Employment expectations for the months ahead (an input to the main archive's employment_expectations composite).",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 7, balance, seasonally adjusted (\"INDU.AT.TOT.7.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "industry_limits_none",                    "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'None': the share of firms reporting no constraint.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F1S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F1S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_limits_demand",                  "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'Demand'.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F2S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F2S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_limits_labour",                  "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'Labour'.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F3S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F3S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_limits_material_equipment",      "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'Shortage of material and/or equipment' -- the supply-bottleneck measure of 2021-22.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F4S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F4S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_limits_other",                   "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'Other'.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F5S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F5S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_limits_financial",               "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 8: Factors limiting production, answer 'Financial'.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 8, answer F6S, share of firms naming this factor, in per cent, seasonally adjusted (\"INDU.AT.TOT.8.F6S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_production_capacity",            "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 9: Assessment of current production capacity; a POSITIVE balance means capacity is judged more than sufficient.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 9, balance, seasonally adjusted (\"INDU.AT.TOT.9.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "industry_new_orders_past",                "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 11: New orders in recent months.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 11, balance, seasonally adjusted (\"INDU.AT.TOT.11.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "industry_capacity_utilization",           "Industrial Production",            "CUMFNS",
    "FRED-QD's CUMFNS is the Federal Reserve's capacity utilisation for manufacturing, output divided by an estimate of capacity built from production and capital data. The EC measure is survey-based: manufacturers report the percentage of capacity they are currently using (industry survey question 13), asked quarterly.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 13, current level of capacity utilisation in per cent, seasonally adjusted (\"INDU.AT.TOT.13.QPS.Q\") -- see R/ec_survey.R. Reported by firms rather than estimated from output and capital, and quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "industry_competitive_position_eu",        "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 15: Competitive position on markets inside the EU over the past three months.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 15, balance, seasonally adjusted (\"INDU.AT.TOT.15.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "industry_competitive_position_outside_eu", "Industrial Production",            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for industry. EC industry survey question 16: Competitive position on markets outside the EU over the past three months.",
    "EU member states only: European Commission Business and Consumer Survey, industry survey question 16, balance, seasonally adjusted (\"INDU.AT.TOT.16.BS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "balance", FALSE,
  "services_business_situation_past",        "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 1: Business situation development over the past 3 months (a component of services_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 1, balance, seasonally adjusted (\"SERV.AT.TOT.1.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_demand_past",                    "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 2: Evolution of demand over the past 3 months (a component of services_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 2, balance, seasonally adjusted (\"SERV.AT.TOT.2.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_demand_expected",                "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 3: Expectation of demand over the next 3 months (a component of services_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 3, balance, seasonally adjusted (\"SERV.AT.TOT.3.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_employment_expectations",        "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 5: Expectations of employment over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 5, balance, seasonally adjusted (\"SERV.AT.TOT.5.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_price_expectations",             "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 6: Expectations of the prices charged over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 6, balance, seasonally adjusted (\"SERV.AT.TOT.6.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_limits_none",                    "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'None'.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F1S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F1S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_limits_demand",                  "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'Demand'.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F2S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F2S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_limits_labour",                  "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'Labour forces'.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F3S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F3S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_limits_equipment_space",         "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'Equipment and/or Space'.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F4S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F4S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_limits_financial",               "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'Financial' (F5S here, where industry's 'Financial' is F6S -- read off the Index sheet).",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F5S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F5S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_limits_other",                   "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 7: Factors limiting the business, answer 'Other'.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 7, answer F6S, share of firms naming this factor, in per cent, seasonally adjusted (\"SERV.AT.TOT.7.F6S.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "services_capacity_utilization",           "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for services. EC services survey question 8: Current level of capacity utilisation in services, in per cent.",
    "EU member states only: European Commission Business and Consumer Survey, services survey question 8, capacity utilisation in per cent, seasonally adjusted (\"SERV.AT.TOT.8.QPS.Q\") -- see R/ec_survey.R. Quarterly at source, so absent from the monthly panel. No FRED-mirror fallback exists for this concept.",
    "percent", FALSE,
  "retail_business_activity_past",           "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 1: Business activity (sales) development over the past 3 months (a component of retail_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 1, balance, seasonally adjusted (\"RETA.AT.TOT.1.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_stocks",                           "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 2: Volume of stock currently held; a POSITIVE balance means stocks are judged too large (enters retail_confidence with a negative sign).",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 2, balance, seasonally adjusted (\"RETA.AT.TOT.2.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_orders_expected",                  "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 3: Orders placed with suppliers expected over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 3, balance, seasonally adjusted (\"RETA.AT.TOT.3.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_business_activity_expected",       "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 4: Business activity expectations over the next 3 months (a component of retail_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 4, balance, seasonally adjusted (\"RETA.AT.TOT.4.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_employment_expectations",          "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 5: Employment expectations over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 5, balance, seasonally adjusted (\"RETA.AT.TOT.5.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "retail_price_expectations",               "Other",                            NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for retail trade. EC retail trade survey question 6: Selling price expectations over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, retail trade survey question 6, balance, seasonally adjusted (\"RETA.AT.TOT.6.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "construction_activity_past",              "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 1: Building activity development over the past 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 1, balance, seasonally adjusted (\"BUIL.AT.TOT.1.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "construction_limits_none",                "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'None'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F1S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F1S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_limits_demand",              "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'Insufficient demand'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F2S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F2S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_limits_labour",              "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'Shortage of labour force'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F4S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F4S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_limits_material_equipment",  "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'Shortage of material and/or equipment'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F5S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F5S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_limits_other",               "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'Other factors'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F6S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F6S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_limits_financial",           "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 2: Main factors currently limiting building activity, answer 'Financial constraints'.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F7S, share of firms naming this factor, in per cent, seasonally adjusted (\"BUIL.AT.TOT.2.F7S.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "percent", TRUE,
  "construction_order_books",                "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 3: Evolution of current overall order books (a component of construction_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 3, balance, seasonally adjusted (\"BUIL.AT.TOT.3.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "construction_employment_expectations",    "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 4: Employment expectations over the next 3 months (a component of construction_confidence).",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 4, balance, seasonally adjusted (\"BUIL.AT.TOT.4.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "construction_price_expectations",         "Housing",                          NA,
    "No FRED-QD equivalent; FRED-QD carries no question-level business survey for construction. EC construction survey question 5: Prices expectations over the next 3 months.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 5, balance, seasonally adjusted (\"BUIL.AT.TOT.5.BS.M\") -- see R/ec_survey.R. Monthly at source, averaged within the quarter. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "economic_sentiment_indicator",          "Other",                          NA,
    "No FRED-QD equivalent; DG ECFIN's own flagship composite indicator (weighted average of industry/services/consumer/retail/construction survey balances), explicitly constructed and empirically validated to track and lead euro-area GDP growth.",
    "EU member states only: European Commission Business and Consumer Survey, Economic Sentiment Indicator (\"AT.ESI\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "services_confidence",                   "Other",                          NA,
    "No FRED-QD equivalent; a standard EC sentiment sub-index for the services sector.",
    "EU member states only: European Commission Business and Consumer Survey, Services Confidence Indicator (\"AT.SERV\") -- see R/ec_survey.R. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "oil_price",                             "Prices",                         "OILPRICEx",       
    "FRED-QD's OILPRICEx is the real refiner acquisition cost of crude, deflated by core PCE; the series here is the nominal spot price in US dollars, left undeflated because which deflator and which exchange rate belong in front of it is a modelling decision and the panel already carries cpi_index and fx_rate_to_usd for either.",
    "Not country-specific and not intended to be: a barrel of crude has one world price, so this column is identical in every country's panel, as R/gpr.R's global index is for countries the GPR source does not cover separately. It is here because the world oil price is the classic exogenous supply shifter for a small open economy. FRED WTISPLC (spot West Texas Intermediate, monthly from 1946, averaged within the quarter) -- see R/commodities.R, whose header says why WTI rather than Brent.",
    "level_event_driven", TRUE,
  "geopolitical_risk",                     "Other",                          NA,
    "No FRED-QD equivalent; the Caldara-Iacoviello (2022) Geopolitical Risk index, the standard academic/policy measure -- country-specific for the 44 countries the source covers (confirmed: includes DEU/USA, excludes AUT), global index used otherwise (see R/gpr.R).",
    "Caldara and Iacoviello's (2022) Geopolitical Risk index, from matteoiacoviello.com's own published data file -- see R/gpr.R. Genuinely country-specific for the 44 countries the source constructs one for (confirmed: Germany, the United States); the global index is used for every other country (confirmed: Austria), not a country-specific gap in this project's own sourcing.",
    "level_event_driven", TRUE,
  "global_activity",                       "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD is a US panel and carries no measure of WORLD activity at all. Kilian's (2009) index of global real economic activity, built from dry cargo ocean freight rates.",
    "Not country-specific and not intended to be, exactly as oil_price is not: there is one world business cycle, so this column is identical in every country's panel. FRED IGREA, monthly from 1968, averaged within the quarter -- see R/global_activity.R. It is expressed in PERCENT DEVIATIONS FROM TREND, so it is signed and roughly half its observations are negative: do not log it and do not take quarter-over-quarter percent changes of it. It is here so that a panel carrying oil_price can separate an oil supply disturbance from an oil demand one, which is the distinction Kilian (2009) exists to make.",
    "deviation", TRUE,
  "financial_stress",                      "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD has no composite financial stress index. The ECB publishes its country-level Composite Indicator of Systemic Stress for the United States too (REF_AREA=US, confirmed live), so the US panel carries the same construction as every other country rather than a US-specific substitute.",
    "ECB country-level Composite Indicator of Systemic Stress (CISS), dataflow CISS, key D.<cc2>.Z0Z.4F.EC.SS_CIN.IDX -- daily, averaged to calendar quarters, see R/ecb.R. Bounded between 0 and 1 by construction; combines stress measures from several financial market segments, weighting them by their time-varying cross-correlations, so that stress in several segments at once counts for more than stress in one.",
    "level_event_driven", TRUE,
  "world_uncertainty_index",               "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD has no text-based uncertainty index. The US panel uses the same country-level World Uncertainty Index (WUIUSA) as every other country, not the Baker-Bloom-Davis economic policy uncertainty index.",
    "World Uncertainty Index (Ahir, Bloom and Furceri, 2022), the frequency of the word 'uncertainty' and its variants in the Economist Intelligence Unit's country reports -- quarterly and country-specific, via FRED's mirror (mnemonic WUI<ISO3>, e.g. WUIAUT, confirmed live for AUT/DEU/USA), see R/fred_mirror.R. Legitimately 0 in some early quarters in which a short report happens not to use the word, which is why it has a non-negative rather than a positive plausibility category.",
    "nonneg_event_driven", FALSE,
  "share_price_index",                     "Stock Markets",                  "S&P 500",         NA,
    "Austria: sourced from the ATX (Austrian Traded Index) via Yahoo Finance (ticker \"^ATX\"), Austria's own actual benchmark index, NOT the generic OECD MEI 'all shares' proxy used for other countries -- see R/yahoo_finance.R. Falls back to the FRED mirror if the Yahoo Finance fetch is unavailable for a given run.",
    "level", TRUE,
  "construction_weather_constraint",        "Housing",                        NA,
    "No FRED-QD equivalent; FRED-QD contains no weather variable of any kind. This is the share of construction firms naming weather as a factor currently limiting their building activity -- weather measured by its reported ECONOMIC effect rather than meteorologically, and the companion concept to construction_confidence from the same survey.",
    "EU member states only: European Commission Business and Consumer Survey, construction survey question 2, answer F3S (\"AT.TOT.2.F3S\") -- see R/ec_survey.R. Already seasonally adjusted at source, so it reads as a weather ANOMALY (how unusually obstructive this quarter's weather was) rather than a raw seasonal pattern. No FRED-mirror fallback exists for this concept.",
    "balance", TRUE,
  "heating_degree_days",                    "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD contains no weather variable of any kind. Degree days are the standard quantitative weather input in applied macro (energy demand, gas consumption, construction, the energy trade balance) and are exogenous and essentially never revised, unlike every national-accounts series in this panel.",
    "Monthly heating degree days (the quarterly panel holds the total of each complete quarter) on Eurostat's definition (reference 18 C, counted on days with a mean temperature at or below 15 C). Eurostat's own nrg_chdd_m is used wherever it publishes; because that dataflow runs roughly nine months behind, the pre-1980 history and the recent quarters are filled with an ERA5 series (via the Open-Meteo archive) computed over a population-weighted set of representative cities and level-calibrated to Eurostat over the overlap -- see R/weather.R. Countries with neither a city set nor Eurostat coverage resolve to NA.",
    "nonneg_seasonal", TRUE,
  "cooling_degree_days",                    "Other",                          NA,
    "No FRED-QD equivalent; FRED-QD contains no weather variable of any kind. The cooling-side companion to heating_degree_days, and the more informative of the two for a warming climate.",
    "Monthly cooling degree days (the quarterly panel holds the total of each complete quarter) on Eurostat's definition (reference 21 C, counted on days with a mean temperature at or above 24 C -- note the deliberate gap between the reference and threshold temperatures, which is Eurostat's convention and not the single-base-temperature convention common in US work). Same source hierarchy as heating_degree_days; legitimately 0.00 for whole quarters in cooler countries, which is why these two concepts have their own plausibility category.",
    "nonneg_seasonal", TRUE
)

## ---------------------------------------------------------------
## Per-series metadata for the monthly and quarterly panels (FRED-MD/QD
## and EA-MD-QD conventions)
##
## Kept as a second, narrow table joined onto `concept_dictionary` rather
## than as seven more columns in every row above, so that the notes stay
## readable and a metadata fact is still authored in exactly one place.
##
## Columns:
##   aggregation  How a QUARTER is formed from the months of a monthly
##                concept: "mean" for stocks, prices, rates, indices and
##                survey balances; "sum" for flows, whose quarter is the
##                total of its three months and which is reported only
##                for complete quarters (monthly_to_quarterly_sum() in
##                R/frequency.R). EA-MD-QD's rule. Recorded for quarterly
##                concepts too, for the day one gains a monthly source.
##   unit         Short unit string as published, before any transformation.
##   sa           Seasonal adjustment AS PUBLISHED by the source: "SCA"
##                (seasonally and calendar adjusted), "SA" (seasonally
##                adjusted) or "NSA". This project adjusts nothing itself.
##                For Austria; a country whose source differs (a FRED
##                mirror where Austria has Eurostat) may differ.
##   tcode_fred   FRED-MD/QD transformation code: 1 level, 2 first
##                difference, 3 second difference, 4 log, 5 first
##                difference of logs, 6 second difference of logs, 7 first
##                difference of the percent change. Where the concept has a
##                FRED-QD mnemonic this is FRED-QD's own code (2026-07
##                vintage, read from its "transform" row); otherwise it
##                follows the same conventions: real and nominal levels 5,
##                price indices 6, rates and ratios 2, survey balances,
##                shares and indices that are stationary by construction 1.
##   class        EA-MD-QD's class: "R" real, "N" nominal, "F" financial,
##                "C" confidence (surveys and uncertainty indices).
##
## The EA-MD-QD codes are DERIVED from `tcode_fred` and `class` by
## `ea_md_qd_codes()` below rather than authored: 0 level, 1 100*log,
## 2 100*diff(log), 3 100*diff(diff(log)), 4 diff, 5 diff(diff). The light
## set never differences twice; the heavy set treats nominal stocks and
## prices as I(2), as EA-MD-QD's benchmark heavy transformation does.
## They follow EA-MD-QD's published conventions, not a series-by-series
## copy of its own codes.
## ---------------------------------------------------------------

concept_metadata <- tibble::tribble(
  ~label,                                    ~aggregation, ~unit,                         ~sa,   ~tcode_fred, ~class,
  "real_gdp",                                "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "real_household_consumption",              "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "real_govt_consumption",                   "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "real_gfcf_total",                         "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "real_exports",                            "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "real_imports",                            "mean",       "EUR mn, chain-linked volume", "SCA", 5L, "R",
  "inventory_change_to_gdp",                 "mean",       "% of GDP",                    "SCA", 1L, "R",
  "real_household_disposable_income",        "mean",       "national currency, volume",   "SCA", 5L, "R",
  "industrial_production",                   "mean",       "index 2021=100",              "SCA", 5L, "R",
  "industrial_confidence",                   "mean",       "balance",                     "SA",  1L, "C",
  "unemployment_rate",                       "mean",       "% of labour force",           "SA",  2L, "R",
  "employment_rate",                         "mean",       "% of population 15-64",       "SA",  2L, "R",
  "hours_worked",                            "mean",       "mn hours",                    "SCA", 5L, "R",
  "population",                              "mean",       "thousand persons",            "SCA", 5L, "R",
  "employment_expectations",                 "mean",       "index",                       "SA",  1L, "C",
  "house_price_real",                        "mean",       "index",                       "NSA", 5L, "R",
  "construction_confidence",                 "mean",       "balance",                     "SA",  1L, "C",
  "retail_sales_volume",                     "mean",       "index 2021=100",              "SCA", 5L, "R",
  "retail_confidence",                       "mean",       "balance",                     "SA",  1L, "C",
  "cpi_index",                               "mean",       "index 2025=100",              "NSA", 6L, "N",
  "core_cpi_index",                          "mean",       "index 2025=100",              "NSA", 6L, "N",
  "food_price_index",                        "mean",       "index 2025=100",              "NSA", 6L, "N",
  "energy_price_index",                      "mean",       "index 2025=100",              "NSA", 6L, "N",
  "services_price_index",                    "mean",       "index 2025=100",              "NSA", 6L, "N",
  "unit_labor_cost",                         "mean",       "index 2010=100",              "SCA", 5L, "N",
  "long_term_rate",                          "mean",       "% p.a.",                      "NSA", 2L, "F",
  "short_term_rate",                         "mean",       "% p.a.",                      "NSA", 2L, "F",
  "government_bond_yield_2y",                "mean",       "% p.a.",                      "NSA", 2L, "F",
  "government_bond_yield_5y",                "mean",       "% p.a.",                      "NSA", 2L, "F",
  "mortgage_rate",                           "mean",       "% p.a.",                      "NSA", 2L, "F",
  "mortgage_rate_pure_new_loans",            "mean",       "% p.a.",                      "NSA", 2L, "F",
  "mortgage_rate_oenb",                      "mean",       "% p.a.",                      "NSA", 2L, "F",
  "credit_to_private_nonfin_sector",         "mean",       "% of GDP",                    "NSA", 2L, "N",
  "household_mortgage_loans",                "mean",       "EUR mn, outstanding",         "NSA", 5L, "N",
  "mortgage_new_lending",                    "sum",        "EUR mn per period",           "NSA", 5L, "N",
  "mortgage_new_lending_oenb",               "sum",        "EUR mn per period",           "NSA", 5L, "N",
  "euro_area_household_net_worth_growth",    "mean",       "% change",                    "NSA", 1L, "F",
  "household_credit_to_gdp",                 "mean",       "% of GDP",                    "NSA", 2L, "N",
  "corporate_credit_to_gdp",                 "mean",       "% of GDP",                    "NSA", 2L, "N",
  "government_debt_to_gdp",                  "mean",       "% of GDP",                    "NSA", 2L, "N",
  "government_primary_balance_to_gdp",       "mean",       "% of GDP",                    "NSA", 1L, "N",
  "fx_rate_to_usd",                          "mean",       "national currency per USD",   "NSA", 5L, "F",
  "real_effective_exchange_rate",            "mean",       "index 2015=100",              "NSA", 5L, "F",
  "consumer_confidence",                     "mean",       "balance",                     "SA",  1L, "C",
  "consumer_financial_situation_past",       "mean",       "balance",                     "SA",  1L, "C",
  "consumer_financial_situation_expected",   "mean",       "balance",                     "SA",  1L, "C",
  "consumer_economic_situation_past",        "mean",       "balance",                     "SA",  1L, "C",
  "consumer_economic_situation_expected",    "mean",       "balance",                     "SA",  1L, "C",
  "consumer_price_trends_past",              "mean",       "balance",                     "SA",  1L, "C",
  "consumer_price_expectations",             "mean",       "balance",                     "SA",  1L, "C",
  "consumer_unemployment_expectations",      "mean",       "balance",                     "SA",  1L, "C",
  "consumer_major_purchases_now",            "mean",       "balance",                     "SA",  1L, "C",
  "consumer_major_purchases_expected",       "mean",       "balance",                     "SA",  1L, "C",
  "consumer_savings_expected",               "mean",       "balance",                     "SA",  1L, "C",
  "consumer_household_finances_now",         "mean",       "balance",                     "SA",  1L, "C",
  "consumer_home_purchase_intentions",       "mean",       "balance",                     "SA",  1L, "C",
  "consumer_home_improvement_intentions",    "mean",       "balance",                     "SA",  1L, "C",
  "industry_production_past",                "mean",       "balance",                     "SA",  1L, "C",
  "industry_order_books",                    "mean",       "balance",                     "SA",  1L, "C",
  "industry_export_order_books",             "mean",       "balance",                     "SA",  1L, "C",
  "industry_stocks_finished_products",       "mean",       "balance",                     "SA",  1L, "C",
  "industry_production_expectations",        "mean",       "balance",                     "SA",  1L, "C",
  "industry_selling_price_expectations",     "mean",       "balance",                     "SA",  1L, "C",
  "industry_employment_expectations",        "mean",       "balance",                     "SA",  1L, "C",
  "industry_limits_none",                    "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_limits_demand",                  "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_limits_labour",                  "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_limits_material_equipment",      "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_limits_other",                   "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_limits_financial",               "mean",       "% of firms",                  "SA",  1L, "C",
  "industry_production_capacity",            "mean",       "balance",                     "SA",  1L, "C",
  "industry_new_orders_past",                "mean",       "balance",                     "SA",  1L, "C",
  "industry_capacity_utilization",           "mean",       "% of capacity",               "SA",  1L, "C",
  "industry_competitive_position_eu",        "mean",       "balance",                     "SA",  1L, "C",
  "industry_competitive_position_outside_eu", "mean",      "balance",                     "SA",  1L, "C",
  "services_business_situation_past",        "mean",       "balance",                     "SA",  1L, "C",
  "services_demand_past",                    "mean",       "balance",                     "SA",  1L, "C",
  "services_demand_expected",                "mean",       "balance",                     "SA",  1L, "C",
  "services_employment_expectations",        "mean",       "balance",                     "SA",  1L, "C",
  "services_price_expectations",             "mean",       "balance",                     "SA",  1L, "C",
  "services_limits_none",                    "mean",       "% of firms",                  "SA",  1L, "C",
  "services_limits_demand",                  "mean",       "% of firms",                  "SA",  1L, "C",
  "services_limits_labour",                  "mean",       "% of firms",                  "SA",  1L, "C",
  "services_limits_equipment_space",         "mean",       "% of firms",                  "SA",  1L, "C",
  "services_limits_financial",               "mean",       "% of firms",                  "SA",  1L, "C",
  "services_limits_other",                   "mean",       "% of firms",                  "SA",  1L, "C",
  "services_capacity_utilization",           "mean",       "% of capacity",               "SA",  1L, "C",
  "retail_business_activity_past",           "mean",       "balance",                     "SA",  1L, "C",
  "retail_stocks",                           "mean",       "balance",                     "SA",  1L, "C",
  "retail_orders_expected",                  "mean",       "balance",                     "SA",  1L, "C",
  "retail_business_activity_expected",       "mean",       "balance",                     "SA",  1L, "C",
  "retail_employment_expectations",          "mean",       "balance",                     "SA",  1L, "C",
  "retail_price_expectations",               "mean",       "balance",                     "SA",  1L, "C",
  "construction_activity_past",              "mean",       "balance",                     "SA",  1L, "C",
  "construction_limits_none",                "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_limits_demand",              "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_limits_labour",              "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_limits_material_equipment",  "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_limits_other",               "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_limits_financial",           "mean",       "% of firms",                  "SA",  1L, "C",
  "construction_order_books",                "mean",       "balance",                     "SA",  1L, "C",
  "construction_employment_expectations",    "mean",       "balance",                     "SA",  1L, "C",
  "construction_price_expectations",         "mean",       "balance",                     "SA",  1L, "C",
  "economic_sentiment_indicator",            "mean",       "index, long-term mean = 100", "SA",  1L, "C",
  "services_confidence",                     "mean",       "balance",                     "SA",  1L, "C",
  "oil_price",                               "mean",       "USD per barrel",              "NSA", 5L, "N",
  "geopolitical_risk",                       "mean",       "index",                       "NSA", 1L, "C",
  "global_activity",                         "mean",       "deviation from trend",        "NSA", 1L, "R",
  "financial_stress",                        "mean",       "index 0-1",                   "NSA", 1L, "F",
  "world_uncertainty_index",                 "mean",       "index",                       "NSA", 1L, "C",
  "share_price_index",                       "mean",       "index points",                "NSA", 5L, "F",
  "construction_weather_constraint",         "mean",       "% of firms",                  "SA",  1L, "C",
  "heating_degree_days",                     "sum",        "degree days",                 "NSA", 1L, "R",
  "cooling_degree_days",                     "sum",        "degree days",                 "NSA", 1L, "R"
)

#' EA-MD-QD light and heavy transformation codes from a FRED code and class
#'
#' Codes: 0 level, 1 100*log, 2 100*diff(log), 3 100*diff(diff(log)),
#' 4 diff, 5 diff(diff). The two sets differ only where EA-MD-QD's do: the
#' heavy set takes second log differences of nominal stocks and of prices,
#' which it treats as I(2), where the light set rules I(2) dynamics out.
ea_md_qd_codes <- function(tcode_fred, class, aggregation) {
  base <- c(`1` = 0L, `2` = 4L, `3` = 5L, `4` = 1L, `5` = 2L, `6` = 2L, `7` = 2L)
  light <- unname(base[as.character(tcode_fred)])
  heavy <- light
  i2 <- tcode_fred == 6L | (tcode_fred == 5L & class == "N" & aggregation == "mean")
  heavy[i2] <- 3L
  list(light = light, heavy = heavy)
}

## Native frequency of the source used: "M" concepts are fetched monthly
## and their quarters derived by `aggregation`; "Q" concepts are fetched
## quarterly and appear only in the quarterly panel. `available_monthly` above stays the authored
## flag, so readers of docs/concept_dictionary.csv that use it keep working.
concept_dictionary <- concept_dictionary %>%
  dplyr::left_join(concept_metadata, by = "label") %>%
  dplyr::mutate(frequency = ifelse(.data$available_monthly, "M", "Q"))
ea_codes <- ea_md_qd_codes(concept_dictionary$tcode_fred, concept_dictionary$class,
                           concept_dictionary$aggregation)
concept_dictionary$tcode_lt <- ea_codes$light
concept_dictionary$tcode_ht <- ea_codes$heavy
rm(ea_codes)
