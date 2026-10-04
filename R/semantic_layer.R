## ---------------------------------------------------------------
## semantic_layer.R -- a machine-readable layer over the output panels,
## for AI agents (and people) who need to answer questions with the data
## rather than rebuild it
##
## The panels are wide CSVs with snake_case column names; what a column
## MEANS lives in four places an agent would otherwise have to stitch
## together by hand: `concept_dictionary` (groups, units, codes, caveats),
## each country's <cc>_metadata.csv (provider, key, span), `policy_events`
## and the README. This file adds the facts none of them hold -- a plain
## title, a one-sentence description, the words people actually use for
## a concept ("inflation", "Euribor", "PMI-like"), and whether a column
## is national, euro-area-wide or global -- and joins all of it into one
## catalog:
##
##   output/semantic/catalog.json      datasets, dimensions, concepts
##                                     (with per-country availability),
##                                     derived metrics, transforms and
##                                     the rules for reading the data
##   output/semantic/concepts.csv      one row per concept, flat
##   output/semantic/availability.csv  one row per (country, concept)
##
## written by scripts/build_panels.R after every run (and on its own by
## scripts/build_semantic_layer.R, without fetching anything). Nothing in
## the catalog is authored twice: everything except the four columns of
## `concept_semantics` and the `derived_metrics` table is read from the
## tables and files named above at write time.
##
## The query side -- `amd_search()`, `amd_describe()`, `amd_get()` --
## is what scripts/query.R exposes on the command line, so an agent with
## a shell can find a series, read its caveats and pull it, transformed,
## as CSV in three commands. `amd_get()` never guesses: a name that is
## neither a concept label nor a derived metric is an error that lists
## the closest matches, because a silently substituted series is the
## kind of mistake nobody catches downstream.
## ---------------------------------------------------------------

## ---------------------------------------------------------------
## Concept semantics -- the only facts authored in this file
##
## Columns:
##   label        Primary key, as in `concept_dictionary`.
##   title        Short human name.
##   description  One plain sentence: what the number is. Source details
##                and caveats stay in `concept_dictionary`'s notes and
##                are carried into the catalog from there.
##   synonyms     "|"-separated words and phrases people use for it,
##                lower case; searched by `amd_search()`.
##   scope        "country" (a figure for the country itself),
##                "euro_area" (one euro-area-wide figure, identical for
##                every member) or "world" (identical in every panel).
## ---------------------------------------------------------------

concept_semantics <- tibble::tribble(
  ~label, ~title, ~description, ~synonyms, ~scope,
  "real_gdp", "Real GDP",
    "Gross domestic product at constant (chain-linked) prices, seasonally and calendar adjusted.",
    "gdp|output|economic growth|real output|national income|b1gq|gross domestic product", "country",
  "real_household_consumption", "Real private consumption",
    "Household final consumption expenditure at constant prices.",
    "consumption|private consumption|consumer spending|household spending|pce|p31", "country",
  "real_govt_consumption", "Real government consumption",
    "General government final consumption expenditure at constant prices.",
    "government spending|public consumption|government expenditure|fiscal spending|p3 s13", "country",
  "real_gfcf_total", "Real gross fixed capital formation",
    "Gross fixed capital formation of all sectors at constant prices.",
    "investment|gfcf|capital formation|fixed investment|capex|p51g", "country",
  "real_exports", "Real exports",
    "Exports of goods and services at constant prices.",
    "exports|foreign demand|trade|p6", "country",
  "real_imports", "Real imports",
    "Imports of goods and services at constant prices.",
    "imports|trade|p7", "country",
  "inventory_change_to_gdp", "Change in inventories (% of GDP)",
    "Change in inventories as a share of nominal GDP, signed.",
    "inventories|stockbuilding|inventory investment|p52", "country",
  "real_household_disposable_income", "Real household disposable income",
    "Gross disposable income of households and NPISHs, deflated by the household consumption deflator.",
    "disposable income|household income|real income|b6g", "country",
  "industrial_production", "Industrial production",
    "Volume index of production in industry excluding construction (NACE B-D).",
    "ip|industrial output|manufacturing output|production index|indpro", "country",
  "industrial_confidence", "Industrial confidence (EC survey)",
    "European Commission Industrial Confidence Indicator, a balance of firms' assessments.",
    "industry confidence|business confidence|manufacturing sentiment|business climate|pmi", "country",
  "unemployment_rate", "Unemployment rate",
    "Unemployed persons as a percentage of the labour force.",
    "unemployment|jobless rate|labour market slack|unrate", "country",
  "employment_rate", "Employment rate (15-64)",
    "Employed persons aged 15-64 as a percentage of the population of that age.",
    "employment to population|employment ratio|jobs", "country",
  "hours_worked", "Total hours worked",
    "Total hours worked by employees and self-employed in the whole economy.",
    "hours|labour input|working hours|total hours", "country",
  "population", "Population",
    "Total resident population, in thousands of persons.",
    "inhabitants|residents|population size|per capita denominator", "country",
  "employment_expectations", "Employment Expectations Indicator (EC survey)",
    "European Commission composite of firms' hiring plans across industry, services, retail and construction.",
    "hiring plans|employment outlook|labour demand expectations|eei", "country",
  "house_price_real", "Real house prices",
    "Residential property price index deflated by consumer prices.",
    "house prices|property prices|housing prices|real estate prices|home prices", "country",
  "construction_confidence", "Construction confidence (EC survey)",
    "European Commission Construction Confidence Indicator, a balance of firms' assessments.",
    "construction sentiment|building confidence|construction climate", "country",
  "retail_sales_volume", "Retail sales volume",
    "Volume of retail trade sales (NACE G47), seasonally and calendar adjusted.",
    "retail sales|retail trade|shop sales|consumer sales", "country",
  "retail_confidence", "Retail confidence (EC survey)",
    "European Commission Retail Trade Confidence Indicator, a balance of firms' assessments.",
    "retail sentiment|retailer confidence|shop confidence", "country",
  "cpi_index", "Consumer price index (headline)",
    "All-items consumer price index: HICP for EU members, the national CPI elsewhere.",
    "cpi|hicp|consumer prices|price level|price index|cost of living|vpi", "country",
  "core_cpi_index", "Core consumer price index",
    "HICP excluding energy, food, alcohol and tobacco.",
    "core inflation|core cpi|core hicp|underlying inflation|hicp ex energy and food", "country",
  "food_price_index", "Food price index",
    "HICP component for food and non-alcoholic beverages.",
    "food prices|food inflation|groceries prices", "country",
  "energy_price_index", "Energy price index",
    "HICP component for energy (fuels, electricity, gas, heating).",
    "energy prices|energy inflation|fuel prices|electricity prices|gas prices", "country",
  "services_price_index", "Services price index",
    "HICP component for services.",
    "services prices|services inflation", "country",
  "unit_labor_cost", "Unit labour cost",
    "Labour cost per unit of real output (an index where Eurostat publishes one, a percent change otherwise).",
    "ulc|unit labor costs|wage costs|labour costs|cost competitiveness", "country",
  "long_term_rate", "10-year government bond yield",
    "Yield on 10-year government bonds, monthly average.",
    "long-term interest rate|10y yield|bond yield|government bond yield|sovereign yield|gs10", "country",
  "short_term_rate", "3-month interest rate",
    "3-month money-market rate: Euribor for euro-area members from euro adoption on (so identical across members), the national interbank rate before.",
    "short-term interest rate|euribor|3m rate|money market rate|interbank rate|policy rate proxy|t-bill", "country",
  "government_bond_yield_2y", "2-year government bond yield",
    "Yield on 2-year government bonds (Germany and the USA only).",
    "2y yield|two-year yield|short-end yield|schatz", "country",
  "government_bond_yield_5y", "5-year government bond yield",
    "Yield on 5-year government bonds (Germany and the USA only).",
    "5y yield|five-year yield|bobl|gs5", "country",
  "mortgage_rate", "Mortgage rate (new business)",
    "Interest rate on new loans to households for house purchase, all rate fixation periods, including renegotiations.",
    "mortgage interest rate|housing loan rate|home loan rate|lending rate for house purchase|wohnbaukredit zins", "country",
  "mortgage_rate_pure_new_loans", "Mortgage rate (pure new loans)",
    "Interest rate on pure new loans to households for house purchase, excluding renegotiations of existing loans.",
    "mortgage rate excluding renegotiations|new mortgage rate", "country",
  "mortgage_rate_oenb", "Mortgage rate (OeNB, Austria)",
    "OeNB interest rate on new business in housing loans to households; equals mortgage_rate from 2000 and reaches back to 1995.",
    "oenb mortgage rate|austrian mortgage rate|wohnbaukredit zinssatz", "country",
  "credit_to_private_nonfin_sector", "Private credit (% of GDP)",
    "Credit to the private non-financial sector (households and non-financial corporations) as a percentage of GDP.",
    "private credit|credit to gdp|credit gap|leverage|bis credit", "country",
  "household_mortgage_loans", "Outstanding mortgage loans",
    "Stock of MFI loans to households for house purchase, nominal.",
    "mortgage stock|housing loans outstanding|mortgage debt|home loans", "country",
  "mortgage_new_lending", "New mortgage lending",
    "Volume of pure new loans to households for house purchase per period, nominal and not seasonally adjusted (a flow).",
    "new mortgages|mortgage origination|housing loan flow|new housing loans|mortgage volume", "country",
  "mortgage_new_lending_oenb", "New mortgage lending (OeNB, Austria)",
    "OeNB new loans to households for housing purposes per period, nominal and not seasonally adjusted (a flow).",
    "oenb new mortgages|austrian new housing loans|wohnbaukredite neugeschaeft", "country",
  "euro_area_household_net_worth_growth", "Household net worth growth (euro area)",
    "Growth of euro-area household net worth; the same euro-area figure for every member.",
    "household wealth|net worth|household balance sheet", "euro_area",
  "household_credit_to_gdp", "Household credit (% of GDP)",
    "Credit to households and NPISHs as a percentage of GDP.",
    "household debt|household leverage|household credit", "country",
  "corporate_credit_to_gdp", "Corporate credit (% of GDP)",
    "Credit to non-financial corporations as a percentage of GDP.",
    "corporate debt|business credit|firm leverage|nfc credit", "country",
  "government_debt_to_gdp", "Government debt (% of GDP)",
    "Credit to general government at nominal value as a percentage of GDP, a close proxy for gross public debt.",
    "public debt|debt ratio|sovereign debt|government debt", "country",
  "government_primary_balance_to_gdp", "Government primary balance (% of GDP)",
    "General government net lending plus interest payable as a percentage of GDP, not seasonally adjusted.",
    "primary balance|primary surplus|primary deficit|fiscal balance|budget balance", "country",
  "fx_rate_to_usd", "Exchange rate to the US dollar",
    "National currency per US dollar (so a rise is a depreciation against the dollar).",
    "exchange rate|eur usd|dollar exchange rate|fx|currency", "country",
  "real_effective_exchange_rate", "Real effective exchange rate",
    "Trade-weighted, price-adjusted exchange rate index (a rise is a real appreciation).",
    "reer|effective exchange rate|competitiveness|trade-weighted exchange rate", "country",
  "consumer_confidence", "Consumer confidence",
    "Consumer Confidence Indicator from the European Commission survey for EU members, the OECD mirror otherwise.",
    "consumer sentiment|household confidence|consumer climate|umcsent", "country",
  "consumer_financial_situation_past", "Consumers: financial situation, past 12 months",
    "Balance of consumers reporting their household's financial situation improved over the past 12 months.",
    "household finances past|consumer survey q1", "country",
  "consumer_financial_situation_expected", "Consumers: financial situation, next 12 months",
    "Balance of consumers expecting their household's financial situation to improve over the next 12 months.",
    "household finances outlook|consumer survey q2", "country",
  "consumer_economic_situation_past", "Consumers: general economic situation, past 12 months",
    "Balance of consumers saying the country's economic situation improved over the past 12 months.",
    "perceived economy|consumer survey q3", "country",
  "consumer_economic_situation_expected", "Consumers: general economic situation, next 12 months",
    "Balance of consumers expecting the country's economic situation to improve over the next 12 months.",
    "economic outlook consumers|consumer survey q4", "country",
  "consumer_price_trends_past", "Consumers: perceived inflation",
    "Balance of consumers saying prices rose over the past 12 months.",
    "perceived inflation|consumer survey q5", "country",
  "consumer_price_expectations", "Consumers: inflation expectations",
    "Balance of consumers expecting prices to rise over the next 12 months.",
    "inflation expectations|household inflation expectations|consumer survey q6", "country",
  "consumer_unemployment_expectations", "Consumers: unemployment expectations",
    "Balance of consumers expecting unemployment to rise over the next 12 months.",
    "unemployment fears|job worries|consumer survey q7", "country",
  "consumer_major_purchases_now", "Consumers: major purchases, right time now",
    "Balance of consumers saying now is the right time to make major purchases.",
    "durable goods purchases|big-ticket purchases|consumer survey q8", "country",
  "consumer_major_purchases_expected", "Consumers: major purchases, next 12 months",
    "Balance of consumers planning to spend more on major purchases over the next 12 months.",
    "durables spending plans|consumer survey q9", "country",
  "consumer_savings_expected", "Consumers: savings, next 12 months",
    "Balance of consumers likely to save money over the next 12 months.",
    "saving intentions|household saving|consumer survey q11", "country",
  "consumer_household_finances_now", "Consumers: current financial situation",
    "Balance of consumers describing their household as saving rather than running into debt.",
    "household financial situation|debt or savings|consumer survey q12", "country",
  "consumer_home_purchase_intentions", "Consumers: intention to buy a home",
    "Balance of consumers likely to buy or build a home over the next 12 months.",
    "home buying intentions|housing demand|house purchase plans|consumer survey q14", "country",
  "consumer_home_improvement_intentions", "Consumers: home improvement plans",
    "Balance of consumers planning to spend on home improvements over the next 12 months.",
    "renovation plans|home renovation|consumer survey q15", "country",
  "industry_production_past", "Industry: production trend, past 3 months",
    "Balance of industrial firms reporting rising production over the past three months.",
    "recent production|industry survey q1", "country",
  "industry_order_books", "Industry: order books",
    "Balance of industrial firms assessing their order books as above normal.",
    "order backlog|orders|industry survey q2", "country",
  "industry_export_order_books", "Industry: export order books",
    "Balance of industrial firms assessing their export order books as above normal.",
    "export orders|foreign orders|industry survey q3", "country",
  "industry_stocks_finished_products", "Industry: stocks of finished products",
    "Balance of industrial firms assessing their stocks of finished products as above normal.",
    "inventories survey|finished goods stocks|industry survey q4", "country",
  "industry_production_expectations", "Industry: production expectations",
    "Balance of industrial firms expecting production to rise over the next three months.",
    "production outlook|output expectations|industry survey q5", "country",
  "industry_selling_price_expectations", "Industry: selling price expectations",
    "Balance of industrial firms expecting to raise selling prices over the next three months.",
    "price expectations firms|producer price expectations|pricing intentions|industry survey q6", "country",
  "industry_employment_expectations", "Industry: employment expectations",
    "Balance of industrial firms expecting employment to rise over the next three months.",
    "industry hiring plans|industry survey q7", "country",
  "industry_limits_none", "Industry: no factor limiting production",
    "Share of industrial firms reporting no factor limiting production.",
    "no constraints|industry survey q8 none", "country",
  "industry_limits_demand", "Industry: production limited by demand",
    "Share of industrial firms naming insufficient demand as limiting production.",
    "demand constraint|weak demand|industry survey q8 demand", "country",
  "industry_limits_labour", "Industry: production limited by labour shortage",
    "Share of industrial firms naming shortage of labour as limiting production.",
    "labour shortage|labor shortage|skills shortage|worker shortage|industry survey q8 labour", "country",
  "industry_limits_material_equipment", "Industry: production limited by materials or equipment",
    "Share of industrial firms naming shortage of material and/or equipment as limiting production.",
    "supply bottlenecks|supply chain|material shortage|equipment shortage|industry survey q8 material", "country",
  "industry_limits_other", "Industry: production limited by other factors",
    "Share of industrial firms naming other factors as limiting production.",
    "other constraints|industry survey q8 other", "country",
  "industry_limits_financial", "Industry: production limited by financial constraints",
    "Share of industrial firms naming financial constraints as limiting production.",
    "credit constraints|financing constraints|industry survey q8 financial", "country",
  "industry_production_capacity", "Industry: assessment of production capacity",
    "Balance of industrial firms assessing their current production capacity as more than sufficient.",
    "spare capacity|capacity assessment|industry survey q9", "country",
  "industry_new_orders_past", "Industry: new orders, past 3 months",
    "Balance of industrial firms reporting rising new orders over the past three months.",
    "new orders|incoming orders|industry survey q11", "country",
  "industry_capacity_utilization", "Industry: capacity utilisation",
    "Firms' reported current level of capacity utilisation in industry, in percent.",
    "capacity utilization|utilisation rate|output gap proxy|cumfns|industry survey q13", "country",
  "industry_competitive_position_eu", "Industry: competitive position inside the EU",
    "Balance of industrial firms reporting an improved competitive position on markets inside the EU over the past three months.",
    "competitiveness eu|industry survey q15", "country",
  "industry_competitive_position_outside_eu", "Industry: competitive position outside the EU",
    "Balance of industrial firms reporting an improved competitive position on markets outside the EU over the past three months.",
    "competitiveness non-eu|industry survey q16", "country",
  "services_business_situation_past", "Services: business situation, past 3 months",
    "Balance of services firms reporting an improved business situation over the past three months.",
    "services business climate|services survey q1", "country",
  "services_demand_past", "Services: demand, past 3 months",
    "Balance of services firms reporting rising demand over the past three months.",
    "services turnover|services survey q2", "country",
  "services_demand_expected", "Services: demand expectations",
    "Balance of services firms expecting demand to rise over the next three months.",
    "services outlook|services survey q3", "country",
  "services_employment_expectations", "Services: employment expectations",
    "Balance of services firms expecting employment to rise over the next three months.",
    "services hiring plans|services survey q5", "country",
  "services_price_expectations", "Services: selling price expectations",
    "Balance of services firms expecting to raise prices over the next three months.",
    "services pricing intentions|services survey q6", "country",
  "services_limits_none", "Services: no factor limiting business",
    "Share of services firms reporting no factor limiting their business.",
    "services survey q7 none", "country",
  "services_limits_demand", "Services: business limited by demand",
    "Share of services firms naming insufficient demand as limiting their business.",
    "services demand constraint|services survey q7 demand", "country",
  "services_limits_labour", "Services: business limited by labour shortage",
    "Share of services firms naming shortage of labour as limiting their business.",
    "services labour shortage|services labor shortage|services survey q7 labour", "country",
  "services_limits_equipment_space", "Services: business limited by space or equipment",
    "Share of services firms naming shortage of space and/or equipment as limiting their business.",
    "services capacity constraint|services survey q7 equipment", "country",
  "services_limits_financial", "Services: business limited by financial constraints",
    "Share of services firms naming financial constraints as limiting their business.",
    "services financing constraints|services survey q7 financial", "country",
  "services_limits_other", "Services: business limited by other factors",
    "Share of services firms naming other factors as limiting their business.",
    "services survey q7 other", "country",
  "services_capacity_utilization", "Services: capacity utilisation",
    "Services firms' reported current level of capacity utilisation, in percent.",
    "services utilization|services survey q8", "country",
  "retail_business_activity_past", "Retail: business activity, past 3 months",
    "Balance of retailers reporting improved business activity (sales) over the past three months.",
    "retail sales survey|retail survey q1", "country",
  "retail_stocks", "Retail: volume of stocks",
    "Balance of retailers assessing their stocks as above normal.",
    "retail inventories|retail survey q2", "country",
  "retail_orders_expected", "Retail: orders placed with suppliers, expected",
    "Balance of retailers expecting to place more orders with suppliers over the next three months.",
    "retail orders|retail survey q3", "country",
  "retail_business_activity_expected", "Retail: business activity expectations",
    "Balance of retailers expecting business activity to improve over the next three months.",
    "retail outlook|retail survey q4", "country",
  "retail_employment_expectations", "Retail: employment expectations",
    "Balance of retailers expecting employment to rise over the next three months.",
    "retail hiring plans|retail survey q5", "country",
  "retail_price_expectations", "Retail: selling price expectations",
    "Balance of retailers expecting to raise prices over the next three months.",
    "retail pricing intentions|retail survey q6", "country",
  "construction_activity_past", "Construction: building activity, past 3 months",
    "Balance of construction firms reporting rising building activity over the past three months.",
    "construction output survey|construction survey q1", "country",
  "construction_limits_none", "Construction: no factor limiting building activity",
    "Share of construction firms reporting no factor limiting their building activity.",
    "construction survey q2 none", "country",
  "construction_limits_demand", "Construction: activity limited by demand",
    "Share of construction firms naming insufficient demand as limiting their building activity.",
    "construction demand constraint|construction survey q2 demand", "country",
  "construction_limits_labour", "Construction: activity limited by labour shortage",
    "Share of construction firms naming shortage of labour as limiting their building activity.",
    "construction labour shortage|construction labor shortage|construction survey q2 labour", "country",
  "construction_limits_material_equipment", "Construction: activity limited by materials or equipment",
    "Share of construction firms naming shortage of material and/or equipment as limiting their building activity.",
    "construction material shortage|construction supply bottlenecks|construction survey q2 material", "country",
  "construction_limits_other", "Construction: activity limited by other factors",
    "Share of construction firms naming other factors as limiting their building activity.",
    "construction survey q2 other", "country",
  "construction_limits_financial", "Construction: activity limited by financial constraints",
    "Share of construction firms naming financial constraints as limiting their building activity.",
    "construction financing constraints|construction survey q2 financial", "country",
  "construction_order_books", "Construction: order books",
    "Balance of construction firms assessing their order books as above normal.",
    "construction orders|construction backlog|construction survey q3", "country",
  "construction_employment_expectations", "Construction: employment expectations",
    "Balance of construction firms expecting employment to rise over the next three months.",
    "construction hiring plans|construction survey q4", "country",
  "construction_price_expectations", "Construction: price expectations",
    "Balance of construction firms expecting to raise prices over the next three months.",
    "construction prices outlook|building costs expectations|construction survey q5", "country",
  "economic_sentiment_indicator", "Economic Sentiment Indicator",
    "European Commission composite of industry, services, consumer, construction and retail confidence, scaled to a long-term mean of 100.",
    "esi|economic sentiment|business and consumer sentiment|overall confidence|business cycle indicator", "country",
  "services_confidence", "Services confidence (EC survey)",
    "European Commission Services Confidence Indicator, a balance of firms' assessments.",
    "services sentiment|services climate|services pmi", "country",
  "construction_cost_index", "Construction cost index (residential)",
    "Cost to the builder of materials and labour for new residential buildings, not seasonally adjusted.",
    "construction costs|building costs|baukostenindex|input costs construction|residential construction costs", "country",
  "construction_producer_prices", "Construction producer prices (residential)",
    "Price builders charge for new residential buildings, not seasonally adjusted; its gap to construction_cost_index is the builder's margin.",
    "construction prices|building prices|baupreisindex|output prices construction|residential construction prices", "country",
  "oil_price", "Oil price (WTI)",
    "Spot price of West Texas Intermediate crude oil in US dollars per barrel; one world price, identical in every panel.",
    "crude oil|oil|wti|brent|energy commodity price|oilprice", "world",
  "geopolitical_risk", "Geopolitical risk index",
    "Caldara-Iacoviello Geopolitical Risk index: country-specific where the source has one (DEU, USA), the global index otherwise (AUT).",
    "gpr|geopolitics|war risk|political risk", "country",
  "global_activity", "Global real economic activity (Kilian index)",
    "Kilian's index of global real economic activity from dry-bulk freight rates, deviation from trend; identical in every panel.",
    "world economy|global demand|global business cycle|kilian index|igrea", "world",
  "financial_stress", "Financial stress (CISS)",
    "ECB Composite Indicator of Systemic Stress for the country, bounded between 0 and 1.",
    "ciss|systemic stress|financial conditions|market stress|risk sentiment", "country",
  "world_uncertainty_index", "World Uncertainty Index",
    "Ahir-Bloom-Furceri index of how often 'uncertainty' appears in the EIU's reports on the country.",
    "wui|uncertainty|economic uncertainty|policy uncertainty", "country",
  "share_price_index", "Share price index",
    "Benchmark stock market index: the ATX for Austria, the OECD all-shares index otherwise.",
    "stock market|equities|stock prices|atx|dax|s&p 500|share prices", "country",
  "construction_weather_constraint", "Construction: activity limited by weather",
    "Share of construction firms naming weather conditions as limiting their building activity, seasonally adjusted (so a weather anomaly).",
    "weather|bad weather|weather shock|construction survey q2 weather", "country",
  "heating_degree_days", "Heating degree days",
    "Heating degree days per period on Eurostat's definition, population-weighted (a flow).",
    "hdd|heating demand|cold weather|temperature|winter severity", "country",
  "cooling_degree_days", "Cooling degree days",
    "Cooling degree days per period on Eurostat's definition, population-weighted (a flow).",
    "cdd|cooling demand|hot weather|heat|temperature|summer heat", "country"
)

## ---------------------------------------------------------------
## Derived metrics -- the handful of numbers people ask for that are not
## a column of any panel, defined once so every agent computes them the
## same way
##
## `formula` is an R expression over panel columns (and metrics defined
## above it in this table), evaluated per country on one panel;
## `synonyms` are searched by `amd_search()` as for concepts. In it,
## `ppy` is the panel's periods per year (12 or 4), and
##   pct_change(x, k)  100 * (x / x[t-k] - 1)
##   lag_n(x, k)       x[t-k]
## shift by PERIODS on a complete date grid, so `pct_change(x, ppy)` is a
## year-on-year rate in either panel. A metric exists in every panel that
## carries all of its inputs: monthly and quarterly when all of them are
## monthly concepts, quarterly only otherwise (`metric_frequencies()`).
## ---------------------------------------------------------------

derived_metrics <- tibble::tribble(
  ~name, ~title, ~unit, ~formula, ~description, ~synonyms,
  "inflation_yoy", "Headline inflation", "% y/y",
    "pct_change(cpi_index, ppy)",
    "Year-on-year change of the headline consumer price index (HICP for EU members).",
    "inflation|headline inflation|cpi inflation|hicp inflation|inflation rate|price growth",
  "core_inflation_yoy", "Core inflation", "% y/y",
    "pct_change(core_cpi_index, ppy)",
    "Year-on-year change of the HICP excluding energy, food, alcohol and tobacco.",
    "core inflation|underlying inflation|core hicp inflation",
  "energy_inflation_yoy", "Energy inflation", "% y/y",
    "pct_change(energy_price_index, ppy)",
    "Year-on-year change of the HICP energy component.",
    "energy inflation|fuel price inflation",
  "food_inflation_yoy", "Food inflation", "% y/y",
    "pct_change(food_price_index, ppy)",
    "Year-on-year change of the HICP food component.",
    "food inflation|food price inflation",
  "services_inflation_yoy", "Services inflation", "% y/y",
    "pct_change(services_price_index, ppy)",
    "Year-on-year change of the HICP services component.",
    "services inflation|service price inflation",
  "real_gdp_growth_qoq", "Real GDP growth, q/q", "% q/q",
    "pct_change(real_gdp, 1)",
    "Quarter-on-quarter change of real GDP, not annualised.",
    "gdp growth|quarterly growth|economic growth|q/q growth",
  "real_gdp_growth_saar", "Real GDP growth, annualised", "% q/q, annualised",
    "100 * ((real_gdp / lag_n(real_gdp, 1))^ppy - 1)",
    "Quarter-on-quarter change of real GDP compounded to an annual rate (as US GDP growth is reported).",
    "annualized gdp growth|annualised growth|saar",
  "real_gdp_growth_yoy", "Real GDP growth, y/y", "% y/y",
    "pct_change(real_gdp, ppy)",
    "Year-on-year change of real GDP.",
    "gdp growth|annual growth|economic growth|y/y growth",
  "real_consumption_growth_yoy", "Real private consumption growth, y/y", "% y/y",
    "pct_change(real_household_consumption, ppy)",
    "Year-on-year change of real household consumption.",
    "consumption growth|consumer spending growth",
  "real_investment_growth_yoy", "Real investment growth, y/y", "% y/y",
    "pct_change(real_gfcf_total, ppy)",
    "Year-on-year change of real gross fixed capital formation.",
    "investment growth|capex growth",
  "industrial_production_growth_yoy", "Industrial production growth, y/y", "% y/y",
    "pct_change(industrial_production, ppy)",
    "Year-on-year change of the industrial production index.",
    "ip growth|industrial output growth",
  "retail_sales_growth_yoy", "Retail sales volume growth, y/y", "% y/y",
    "pct_change(retail_sales_volume, ppy)",
    "Year-on-year change of the retail sales volume index.",
    "retail sales growth",
  "real_gdp_per_capita", "Real GDP per capita", "real_gdp's currency unit per person",
    "1000 * real_gdp / population",
    "Real GDP divided by population (real_gdp in millions, population in thousands). Its level inherits real_gdp's unit for the country (`unit` in availability): a quarterly level in EUR for EU members, an annual rate in USD for the USA, so the USA's is four times a quarterly figure. Compare growth rates, not levels.",
    "gdp per capita|income per head|living standards|per capita output",
  "labour_productivity_per_hour", "Labour productivity per hour", "real_gdp's currency unit per hour",
    "1000 * real_gdp / hours_worked",
    "Real GDP per hour worked (real_gdp in millions over hours_worked in thousands, both quarterly). hours_worked resolves for EU members only, from the same Eurostat accounts as their real_gdp.",
    "productivity|labor productivity|output per hour",
  "unemployment_rate_change_yoy", "Change in the unemployment rate, y/y", "pp",
    "unemployment_rate - lag_n(unemployment_rate, ppy)",
    "Change of the unemployment rate over a year, in percentage points.",
    "change in unemployment|unemployment change",
  "term_spread", "Term spread (10y minus 3m)", "pp",
    "long_term_rate - short_term_rate",
    "Slope of the yield curve: 10-year government bond yield less the 3-month rate.",
    "yield curve|yield spread|slope|term premium|10y-3m spread",
  "real_short_rate", "Real short-term rate (ex post)", "pp",
    "short_term_rate - inflation_yoy",
    "3-month rate less realised year-on-year headline inflation.",
    "real interest rate|real rate|real euribor|monetary stance",
  "real_long_rate", "Real long-term rate (ex post)", "pp",
    "long_term_rate - inflation_yoy",
    "10-year government bond yield less realised year-on-year headline inflation.",
    "real yield|real long rate|real bond yield",
  "mortgage_spread", "Mortgage spread over the 3-month rate", "pp",
    "mortgage_rate - short_term_rate",
    "Mortgage rate on new business less the 3-month money-market rate.",
    "mortgage margin|lending spread|bank margin",
  "mortgage_loans_growth_yoy", "Mortgage stock growth, y/y", "% y/y",
    "pct_change(household_mortgage_loans, ppy)",
    "Year-on-year growth of outstanding loans to households for house purchase (nominal).",
    "mortgage growth|housing loan growth|credit growth",
  "house_price_growth_yoy", "Real house price growth, y/y", "% y/y",
    "pct_change(house_price_real, ppy)",
    "Year-on-year change of real house prices.",
    "house price growth|house price inflation|property price growth",
  "share_price_return_yoy", "Share price change, y/y", "% y/y",
    "pct_change(share_price_index, ppy)",
    "Year-on-year change of the share price index (price only, no dividends).",
    "stock market return|equity return|share price growth",
  "oil_price_change_yoy", "Oil price change, y/y", "% y/y",
    "pct_change(oil_price, ppy)",
    "Year-on-year change of the WTI oil price in US dollars.",
    "oil price change|oil price growth|oil shock"
)

## ---------------------------------------------------------------
## Transformations `amd_get()` applies, per country, on a complete date
## grid and BEFORE the date filter, so the first period kept still has
## its lags. The FRED and EA-MD-QD codes are the ones documented in
## `concept_dictionary.R`; "tcode_*" applies each series' own code.
## ---------------------------------------------------------------

semantic_transforms <- tibble::tribble(
  ~name,          ~unit,              ~description,
  "level",        "as published",     "No transformation.",
  "pct_change",   "% period on period", "100 * (x / x[t-1] - 1).",
  "yoy",          "% y/y",            "100 * (x / x[t-ppy] - 1), ppy = 12 monthly, 4 quarterly.",
  "saar",         "% annualised",     "100 * ((x / x[t-1])^ppy - 1).",
  "diff",         "units of x",       "x - x[t-1]; the right change for rates, balances and shares.",
  "diff_yoy",     "units of x",       "x - x[t-ppy].",
  "log",          "100 * log",        "100 * log(x).",
  "log_diff",     "100 * dlog",       "100 * (log x - log x[t-1]).",
  "tcode_fred",   "stationary",       "Each series' FRED-MD/QD code: 1 x, 2 dx, 3 d2x, 4 log x, 5 dlog x, 6 d2log x, 7 d(x/x[t-1] - 1).",
  "tcode_lt",     "stationary",       "Each series' EA-MD-QD light code: 0 x, 1 100 log x, 2 100 dlog x, 3 100 d2log x, 4 dx, 5 d2x.",
  "tcode_ht",     "stationary",       "Each series' EA-MD-QD heavy code (prices and nominal stocks as I(2)), same scale as tcode_lt."
)

lag_n <- function(x, k) {
  k <- as.integer(k)
  if (k <= 0) return(x)
  if (k >= length(x)) return(rep(NA_real_, length(x)))
  c(rep(NA_real_, k), x[seq_len(length(x) - k)])
}

pct_change <- function(x, k) 100 * (x / lag_n(x, k) - 1)

#' Apply one FRED-MD/QD transformation code
apply_tcode_fred <- function(x, code) {
  d <- function(v) v - lag_n(v, 1)
  switch(as.character(code),
    `1` = x, `2` = d(x), `3` = d(d(x)), `4` = log(x), `5` = d(log(x)),
    `6` = d(d(log(x))), `7` = d(x / lag_n(x, 1) - 1),
    stop("Unknown FRED transformation code: ", code, call. = FALSE))
}

#' Apply one EA-MD-QD transformation code
apply_tcode_ea <- function(x, code) {
  d <- function(v) v - lag_n(v, 1)
  switch(as.character(code),
    `0` = x, `1` = 100 * log(x), `2` = 100 * d(log(x)), `3` = 100 * d(d(log(x))),
    `4` = d(x), `5` = d(d(x)),
    stop("Unknown EA-MD-QD transformation code: ", code, call. = FALSE))
}

#' Transform one series held on a complete date grid
#'
#' `codes` is the series' row of `concept_dictionary` (or NULL for a
#' derived metric, which has no codes and so takes no "tcode_*").
transform_series <- function(x, transform, ppy, codes = NULL) {
  if (grepl("^tcode_", transform) && is.null(codes)) {
    stop("'", transform, "' needs a concept's transformation code; derived metrics have none",
         call. = FALSE)
  }
  # log() of a non-positive value is NaN, with a warning per call; NA
  # is the honest result and the warning is noise in a CSV pipeline.
  suppressWarnings(switch(transform,
    level = x,
    pct_change = pct_change(x, 1),
    yoy = pct_change(x, ppy),
    saar = 100 * ((x / lag_n(x, 1))^ppy - 1),
    diff = x - lag_n(x, 1),
    diff_yoy = x - lag_n(x, ppy),
    log = 100 * log(x),
    log_diff = 100 * (log(x) - log(lag_n(x, 1))),
    tcode_fred = apply_tcode_fred(x, codes$tcode_fred),
    tcode_lt = apply_tcode_ea(x, codes$tcode_lt),
    tcode_ht = apply_tcode_ea(x, codes$tcode_ht),
    stop("Unknown transform '", transform, "'; one of: ",
         paste(semantic_transforms$name, collapse = ", "), call. = FALSE)))
}

#' The frequencies a derived metric exists at: monthly and quarterly when
#' every concept it rests on is monthly at source, quarterly otherwise
metric_frequencies <- function(name, metrics = derived_metrics, dictionary = concept_dictionary) {
  inputs <- metric_inputs(name, metrics)
  freq <- dictionary$frequency[match(inputs, dictionary$label)]
  if (all(freq == "M")) c("M", "Q") else "Q"
}

#' The concepts a derived metric rests on, through any metrics it uses
metric_inputs <- function(name, metrics = derived_metrics) {
  f <- metrics$formula[metrics$name == name]
  if (length(f) != 1) stop("Unknown derived metric: ", name, call. = FALSE)
  vars <- all.vars(parse(text = f)[[1]])
  vars <- setdiff(vars, "ppy")
  sort(unique(unlist(lapply(vars, function(v) {
    if (v %in% metrics$name) metric_inputs(v, metrics) else v
  }))))
}

## ---------------------------------------------------------------
## Reading the output files
## ---------------------------------------------------------------

#' Countries that have been built into `output_dir`, from their metadata
semantic_countries <- function(output_dir = "output") {
  files <- list.files(output_dir, pattern = "^[a-z]{3}_metadata[.]csv$")
  toupper(substr(files, 1, 3))
}

panel_path <- function(country, frequency, output_dir = "output") {
  suffix <- if (identical(frequency, "M")) "_monthly_panel.csv" else "_panel.csv"
  file.path(output_dir, paste0(tolower(country), suffix))
}

read_panel <- function(country, frequency, output_dir = "output") {
  path <- panel_path(country, frequency, output_dir)
  if (!file.exists(path)) stop("No panel at '", path, "'", call. = FALSE)
  panel <- readr::read_csv(path, col_types = readr::cols(date = readr::col_date(), .default = readr::col_double()),
                           progress = FALSE)
  complete_grid(panel, frequency)
}

#' Fill in any missing periods so that lags shift by periods, not rows
complete_grid <- function(panel, frequency) {
  if (nrow(panel) == 0) return(panel)
  step <- if (identical(frequency, "M")) "month" else "3 months"
  grid <- tibble::tibble(date = seq(min(panel$date), max(panel$date), by = step))
  dplyr::arrange(dplyr::left_join(grid, panel, by = "date"), .data$date)
}

read_country_metadata <- function(country, output_dir = "output") {
  readr::read_csv(file.path(output_dir, paste0(tolower(country), "_metadata.csv")),
                  col_types = readr::cols(.default = "c"), progress = FALSE)
}

## ---------------------------------------------------------------
## The catalog
## ---------------------------------------------------------------

#' Notes on reading the data that hold for every concept -- the things an
#' agent gets wrong if nobody tells it
semantic_rules <- c(
  "Dates are the FIRST day of the period: 2026-04-01 in a quarterly panel is 2026-Q2, in a monthly panel April 2026. `period` in amd_get() output spells this out.",
  "Each concept is held once at its native `frequency`. Monthly concepts are in both panels (the quarterly value is the mean of the quarter's months, or the sum for `aggregation` = sum); quarterly concepts are ONLY in the quarterly panel and are never interpolated to months.",
  "The current quarter of a monthly concept averaged into the quarterly panel holds the mean of the months observed so far, so it can change until the quarter is complete. Summed flows are reported for complete quarters only.",
  "NA means not published or not resolved for that country and period. Every country's file has every column; an all-NA column is a concept that did not resolve (see `availability` and each concept's notes).",
  "A concept's `unit` is its unit for euro-area members. The unit for a given country is `unit` in `availability`, the unit of the source that resolved there: national accounts from Eurostat are EUR quarterly levels, from the OECD (the USA) national-currency seasonally adjusted annual rates, four times a quarterly level; FRED series carry their own index bases. Levels are comparable across countries only where `availability` gives them the same unit; growth rates always are.",
  "`scope` = world means the column is identical in every panel (oil_price, global_activity); euro_area means one euro-area figure for every member. short_term_rate is 3-month Euribor for euro-area members from euro adoption on, so it is the same for Austria and Germany from 1999.",
  "`sa` is the seasonal adjustment as published; nothing is adjusted here. NSA series (prices, mortgage flows, the primary balance) carry seasonality: compare year-on-year, not period-on-period.",
  "Before using a concept for a non-trivial claim, read its `us_note` and `cross_country_note`: they record where it differs from its FRED-QD namesake and how its source was spliced or replaced.",
  "Published data are revised. output/vintages/ keeps each month's quarterly panel, coverage and metadata as <cc>_<file>_<YYYY-MM>.<ext>; use a vintage, not the live file, to reproduce what was known at a date.",
  "Policy-event dummies are in <cc>_dummies_monthly.csv and <cc>_dummies_quarterly.csv (where a country has events): a step dummy is 1 while a measure is in force (in quarters, the share of the quarter's months), an impulse is 1 in the period of a one-off event."
)

#' Build the semantic catalog from the dictionary, the authored semantics
#' above and whatever countries have been built into `output_dir`
build_semantic_catalog <- function(output_dir = "output", display_dir = "output",
                                   dictionary = concept_dictionary,
                                   semantics = concept_semantics, metrics = derived_metrics,
                                   events = policy_events) {
  countries <- semantic_countries(output_dir)
  avail <- semantic_availability(countries, output_dir)
  concepts <- dplyr::left_join(dictionary, semantics, by = "label")

  concept_entries <- lapply(seq_len(nrow(concepts)), function(i) {
    row <- concepts[i, ]
    a <- avail[avail$label == row$label, ]
    list(
      label = row$label,
      title = dplyr::coalesce(row$title, row$label),
      description = row$description,
      synonyms = if (is.na(row$synonyms)) character(0) else strsplit(row$synonyms, "|", fixed = TRUE)[[1]],
      scope = row$scope,
      group = row$fred_qd_group,
      frequency = row$frequency,
      in_panels = if (row$frequency == "M") c("monthly", "quarterly") else "quarterly",
      aggregation = row$aggregation,
      unit = row$unit,
      seasonal_adjustment = row$sa,
      class = row$class,
      tcode_fred = row$tcode_fred,
      tcode_lt = row$tcode_lt,
      tcode_ht = row$tcode_ht,
      fred_qd_mnemonic = row$fred_qd_mnemonic,
      us_note = row$us_note,
      cross_country_note = row$cross_country_note,
      availability = lapply(seq_len(nrow(a)), function(j) as.list(a[j, setdiff(names(a), "label")]))
    )
  })

  metric_entries <- lapply(seq_len(nrow(metrics)), function(i) {
    m <- metrics[i, ]
    list(name = m$name, title = m$title, description = m$description,
         synonyms = strsplit(m$synonyms, "|", fixed = TRUE)[[1]], unit = m$unit,
         formula = m$formula, inputs = metric_inputs(m$name, metrics),
         frequencies = metric_frequencies(m$name, metrics, dictionary))
  })

  country_entries <- lapply(countries, function(cc) {
    list(
      code = cc,
      name = country_code_map$country_name[match(cc, country_code_map$country3)],
      eu_member = cc %in% eu_member_countries,
      euro_adoption = if (cc %in% names(euro_adoption)) euro_adoption[[cc]] else NA,
      n_resolved = sum(avail$country == cc & avail$resolved),
      files = as.list(stats::setNames(
        paste0(tolower(cc), c("_panel.csv", "_monthly_panel.csv", "_metadata.csv",
                                                     "_dummies_quarterly.csv", "_dummies_monthly.csv",
                              "_coverage.json", "_monthly_coverage.json")),
        c("quarterly_panel", "monthly_panel", "metadata", "dummies_quarterly", "dummies_monthly",
          "coverage_quarterly", "coverage_monthly")
      )) |> Filter(f = function(f) file.exists(file.path(output_dir, f))) |>
        lapply(function(f) file.path(display_dir, f))
    )
  })

  list(
    name = "AustriaMacroData",
    description = paste(
      "FRED-QD/FRED-MD-style macroeconomic panels for Austria (and comparison countries),",
      "built from Eurostat, OECD, ECB, BIS, OeNB, the European Commission surveys and FRED.",
      "One wide panel per country and frequency, one column per concept, same columns for every country."
    ),
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    rules = as.list(semantic_rules),
    datasets = list(
      list(name = "quarterly_panel", path = file.path(display_dir, "<cc>_panel.csv"),
           grain = "country x quarter", key = "date", date = "first day of the quarter",
           columns = "date, then every concept (all of them, quarterly and monthly-aggregated)"),
      list(name = "monthly_panel", path = file.path(display_dir, "<cc>_monthly_panel.csv"),
           grain = "country x month", key = "date", date = "first day of the month",
           columns = "date, then every concept whose frequency is M"),
      list(name = "metadata", path = file.path(display_dir, "<cc>_metadata.csv"),
           grain = "country x concept", key = "label",
           columns = "label, codes and units, provider, key, first, last, n_obs"),
      list(name = "dummies", path = file.path(display_dir, "<cc>_dummies_{monthly,quarterly}.csv"),
           grain = "country x period", key = "date",
           columns = "date, then one column per policy event of the country"),
      list(name = "coverage", path = file.path(display_dir, "<cc>_{,monthly_}coverage.json"),
           grain = "country", columns = "resolved and unresolved concepts with sources, plausibility checks"),
      list(name = "vintages", path = file.path(display_dir, "vintages", "<cc>_<file>_<YYYY-MM>.<ext>"),
           grain = "country x vintage", columns = "as the live file of the same kind")
    ),
    countries = country_entries,
    concepts = concept_entries,
    derived_metrics = metric_entries,
    transforms = lapply(seq_len(nrow(semantic_transforms)), function(i) as.list(semantic_transforms[i, ])),
    policy_events = lapply(seq_len(nrow(events)), function(i) as.list(events[i, ])),
    codes = list(
      class = list(R = "real", N = "nominal", F = "financial", C = "confidence (surveys, uncertainty)"),
      seasonal_adjustment = list(SCA = "seasonally and calendar adjusted", SA = "seasonally adjusted",
                                 NSA = "not seasonally adjusted"),
      aggregation = list(mean = "quarter = mean of its observed months",
                         sum = "quarter = sum of its three months, complete quarters only"),
      scope = list(country = "a figure for the country itself",
                   euro_area = "one euro-area figure, identical for every member",
                   world = "one world figure, identical in every panel")
    )
  )
}

#' One row per (country, concept): where it came from and what it covers
semantic_availability <- function(countries, output_dir = "output") {
  rows <- lapply(countries, function(cc) {
    md <- read_country_metadata(cc, output_dir)
    tibble::tibble(
      country = cc, label = md$label, frequency = md$frequency, unit = md$unit,
      resolved = !is.na(md$n_obs) & suppressWarnings(as.integer(md$n_obs)) > 0,
      provider = md$provider, key = md$key, first = md$first, last = md$last,
      n_obs = suppressWarnings(as.integer(md$n_obs))
    )
  })
  if (length(rows) == 0) {
    return(tibble::tibble(country = character(0), label = character(0), frequency = character(0),
                          unit = character(0), resolved = logical(0), provider = character(0), key = character(0),
                          first = character(0), last = character(0), n_obs = integer(0)))
  }
  dplyr::bind_rows(rows)
}

#' Write catalog.json, concepts.csv and availability.csv
write_semantic_layer <- function(output_dir = "output", semantic_dir = file.path(output_dir, "semantic")) {
  dir.create(semantic_dir, showWarnings = FALSE, recursive = TRUE)
  catalog <- build_semantic_catalog(output_dir)
  jsonlite::write_json(catalog, file.path(semantic_dir, "catalog.json"),
                       auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")

  concepts <- dplyr::left_join(concept_dictionary, concept_semantics, by = "label") %>%
    dplyr::select("label", "title", "description", "synonyms", "scope", group = "fred_qd_group",
                  "frequency", "aggregation", "unit", "sa", "class", "tcode_fred", "tcode_lt", "tcode_ht",
                  "fred_qd_mnemonic", "us_note", "cross_country_note")
  readr::write_csv(concepts, file.path(semantic_dir, "concepts.csv"), na = "")
  readr::write_csv(semantic_availability(semantic_countries(output_dir), output_dir),
                   file.path(semantic_dir, "availability.csv"), na = "")
  invisible(catalog)
}

## ---------------------------------------------------------------
## Querying
## ---------------------------------------------------------------

#' Find concepts and derived metrics for a natural-language query
#'
#' Scores each entry on its label, title, synonyms, FRED-QD mnemonic and
#' description; returns the best matches, best first.
amd_search <- function(query, n = 10, dictionary = concept_dictionary,
                       semantics = concept_semantics, metrics = derived_metrics) {
  entries <- dplyr::bind_rows(
    dplyr::left_join(dictionary, semantics, by = "label") %>%
      # A concept added to the dictionary before its semantics row is
      # still found by its label; test-semantic_layer.R flags the gap.
      dplyr::transmute(name = .data$label, kind = "concept", title = dplyr::coalesce(.data$title, .data$label),
                       synonyms = dplyr::coalesce(.data$synonyms, ""),
                       mnemonic = tolower(dplyr::coalesce(.data$fred_qd_mnemonic, "")),
                       description = dplyr::coalesce(.data$description, ""),
                       frequency = .data$frequency, unit = .data$unit),
    metrics %>%
      dplyr::transmute(name = .data$name, kind = "metric", title = .data$title, synonyms = .data$synonyms,
                       mnemonic = "", description = .data$description,
                       frequency = vapply(.data$name, function(m) paste(metric_frequencies(m, metrics, dictionary), collapse = ","), ""),
                       unit = .data$unit)
  )
  q <- tolower(trimws(query))
  q_label <- gsub("[^a-z0-9]+", "_", q)
  tokens <- setdiff(strsplit(q, "[^a-z0-9&]+")[[1]], c("", "the", "of", "a", "an", "and", "in", "for", "to", "rate"))
  if (length(tokens) == 0) tokens <- strsplit(q, "[^a-z0-9&]+")[[1]]
  has <- function(text, tok) grepl(paste0("\\b", tok), tolower(text))
  score <- vapply(seq_len(nrow(entries)), function(i) {
    e <- entries[i, ]
    syn <- strsplit(e$synonyms, "|", fixed = TRUE)[[1]]
    s <- 0
    if (q_label == e$name) s <- s + 100
    if (q %in% syn || q == tolower(e$title) || (nzchar(e$mnemonic) && q == e$mnemonic)) s <- s + 50
    for (tok in tokens) {
      s <- s + 6 * has(e$name, tok) + 5 * has(e$title, tok) +
        4 * any(has(syn, tok)) + 1 * has(e$description, tok)
    }
    s
  }, 0)
  out <- entries[score > 0, c("name", "kind", "title", "frequency", "unit", "description")]
  out$score <- score[score > 0]
  utils::head(out[order(-out$score, out$name), ], n)
}

#' Everything known about one concept or derived metric, as a list
amd_describe <- function(name, output_dir = "output") {
  if (name %in% derived_metrics$name) {
    m <- derived_metrics[derived_metrics$name == name, ]
    return(list(name = name, kind = "metric", title = m$title, description = m$description,
                unit = m$unit, formula = m$formula, inputs = metric_inputs(name),
                frequencies = metric_frequencies(name)))
  }
  if (!name %in% concept_dictionary$label) unknown_series_error(name)
  row <- dplyr::left_join(concept_dictionary[concept_dictionary$label == name, ], concept_semantics, by = "label")
  avail <- semantic_availability(semantic_countries(output_dir), output_dir)
  avail <- avail[avail$label == name, setdiff(names(avail), "label")]
  c(list(name = name, kind = "concept"),
    as.list(row[, c("title", "description", "synonyms", "scope", "fred_qd_group", "frequency", "aggregation",
                    "unit", "sa", "class", "tcode_fred", "tcode_lt", "tcode_ht", "fred_qd_mnemonic",
                    "us_note", "cross_country_note")]),
    list(availability = avail))
}

unknown_series_error <- function(name) {
  hits <- amd_search(gsub("_", " ", name), n = 5)
  hint <- if (nrow(hits) > 0) paste0(" Did you mean: ", paste(hits$name, collapse = ", "), "?") else ""
  stop("'", name, "' is neither a concept label nor a derived metric.", hint,
       " Use amd_search() / `scripts/query.R search` to find one.", call. = FALSE)
}

#' Series for one or more countries, optionally transformed, as a tidy
#' data frame
#'
#' @param series     Concept labels and/or derived-metric names; exact,
#'                   never guessed (see amd_search()).
#' @param countries  ISO alpha-3 codes; default every built country.
#' @param frequency  "Q" (default) or "M". A quarterly concept asked for
#'                   at "M" is an error, not an interpolation.
#' @param transform  One of `semantic_transforms$name`, applied per
#'                   series before the date filter.
#' @param from,to    Period bounds: "YYYY", "YYYY-Qn", "YYYY-Mnn",
#'                   "YYYY-MM" or "YYYY-MM-DD".
#' @param format     "long" (country, date, period, series, transform,
#'                   value) or
#'                   "wide" (date, period, one column per country_series).
amd_get <- function(series, countries = NULL, frequency = "Q", transform = "level",
                    from = NULL, to = NULL, format = c("long", "wide"), output_dir = "output") {
  format <- match.arg(format)
  frequency <- toupper(frequency)
  if (!frequency %in% c("M", "Q")) stop("frequency must be 'M' or 'Q'", call. = FALSE)
  if (!transform %in% semantic_transforms$name) {
    stop("Unknown transform '", transform, "'; one of: ", paste(semantic_transforms$name, collapse = ", "),
         call. = FALSE)
  }
  for (s in series) if (!s %in% c(concept_dictionary$label, derived_metrics$name)) unknown_series_error(s)
  if (frequency == "M") {
    quarterly_only <- series[vapply(series, function(s) {
      if (s %in% derived_metrics$name) !"M" %in% metric_frequencies(s)
      else concept_dictionary$frequency[concept_dictionary$label == s] != "M"
    }, logical(1))]
    if (length(quarterly_only) > 0) {
      stop("Quarterly at source, so not in the monthly panel (never interpolated): ",
           paste(quarterly_only, collapse = ", "), ". Ask for frequency = 'Q'.", call. = FALSE)
    }
  }
  if (is.null(countries)) countries <- semantic_countries(output_dir)
  countries <- toupper(countries)
  if (frequency == "M") {
    # A monthly concept some country publishes only quarterly (Germany's
    # construction costs) is all-NA in that country's monthly panel,
    # which would otherwise read as "not available at all".
    avail <- semantic_availability(countries, output_dir)
    inputs <- unique(unlist(lapply(series, function(s) if (s %in% derived_metrics$name) metric_inputs(s) else s)))
    q_only <- avail[avail$label %in% inputs & avail$frequency == "Q" & avail$resolved, ]
    if (nrow(q_only) > 0) {
      warning("Quarterly only for this country, so NA in its monthly panel: ",
              paste0(q_only$country, " ", q_only$label, collapse = ", "),
              ". Ask for frequency = 'Q' to get it.", call. = FALSE)
    }
  }
  ppy <- if (frequency == "M") 12 else 4
  lo <- period_bound(from, frequency)
  hi <- period_bound(to, frequency)

  rows <- lapply(countries, function(cc) {
    panel <- read_panel(cc, frequency, output_dir)
    env <- list2env(as.list(panel), parent = environment())
    assign("ppy", ppy, envir = env)
    for (i in seq_len(nrow(derived_metrics))) {
      m <- derived_metrics[i, ]
      if (!all(metric_inputs(m$name) %in% names(panel))) next
      assign(m$name, eval(parse(text = m$formula)[[1]], envir = env), envir = env)
    }
    lapply(series, function(s) {
      x <- get(s, envir = env)
      codes <- if (s %in% concept_dictionary$label) concept_dictionary[concept_dictionary$label == s, ] else NULL
      y <- transform_series(x, transform, ppy, codes)
      tibble::tibble(country = cc, date = panel$date, series = s, value = y)
    })
  })
  out <- dplyr::bind_rows(unlist(rows, recursive = FALSE))
  if (!is.null(lo)) out <- out[out$date >= lo, ]
  if (!is.null(hi)) out <- out[out$date <= hi, ]
  out <- out[!is.nan(out$value), ]
  out$value[is.infinite(out$value)] <- NA_real_
  out$period <- date_to_period(out$date, frequency)
  out$transform <- transform
  out <- out[, c("country", "date", "period", "series", "transform", "value")]

  if (format == "wide") {
    # A transformed column is named for it, so a y/y rate saved to disk
    # can never be read back as the level it came from.
    suffix <- if (transform == "level") "" else paste0("__", transform)
    out$key <- paste0(tolower(out$country), "_", out$series, suffix)
    out <- tidyr::pivot_wider(out[, c("date", "period", "key", "value")], names_from = "key", values_from = "value")
  }
  dplyr::arrange(out, .data$date)
}

#' A period string or date as the first day of its period
period_bound <- function(x, frequency) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return(NULL)
  if (grepl("^\\d{4}-(Q[1-4]|M\\d{2})$", x)) {
    d <- period_to_date(x)
  } else {
    if (grepl("^\\d{4}-\\d{2}$", x)) x <- paste0(x, "-01")
    if (grepl("^\\d{4}$", x)) x <- paste0(x, "-01-01")
    d <- tryCatch(as.Date(x), error = function(e) as.Date(NA))
  }
  if (is.na(d)) stop("Cannot read '", x, "' as a period; use YYYY, YYYY-Qn, YYYY-Mnn, YYYY-MM or YYYY-MM-DD",
                     call. = FALSE)
  if (frequency == "Q") quarter_start(d) else as.Date(format(d, "%Y-%m-01"))
}
