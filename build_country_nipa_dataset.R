## ---------------------------------------------------------------
## build_country_nipa_dataset.R
##
## Builds a FRED-QD-style quarterly NIPA panel for ANY OECD member
## country, using OECD's Quarterly National Accounts (QNA) SDMX API.
##
## Strategy:
##   1. "Anchor" concepts (GDP, consumption, government, investment,
##      exports, imports, disposable income) use OECD's standardized
##      SNA transaction codes (B1GQ, P6, P7, ...), which are IDENTICAL
##      across every OECD member country. No fuzzy matching needed --
##      just change the REF_AREA / country code.
##   2. For anything beyond those anchors, this script includes a
##      fuzzy-matching helper: it pulls the REAL codelist of concepts
##      published for OECD's National Accounts, and scores it against
##      a keyword you supply -- so you only ever try codes that
##      actually exist, instead of guessing.
##   3. Optional: send ambiguous fuzzy matches to Claude (Haiku, cheap)
##      for a single adjudication call instead of eyeballing every row.
##      Skipped automatically if you don't set an API key.
##
## HONESTY NOTE: SDMX dataflow structures (dimension order, codelist
## JSON shape) do change between releases and I can't execute this
## live to verify every field name. The script is written to fail
## LOUDLY (a warning + empty result) rather than silently returning
## wrong data, and the fields most likely to need a tweak are marked
## with "# ADJUST IF NEEDED" comments. Test on one country/series pair
## before looping over many.
## ---------------------------------------------------------------

## ---- 0. Packages -------------------------------------------------
required_pkgs <- c("httr", "jsonlite", "readr", "dplyr", "purrr",
                    "tidyr", "stringr", "stringdist", "imfapi")
new_pkgs <- required_pkgs[!(required_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs, repos = "https://cloud.r-project.org")

library(httr)
library(jsonlite)
library(readr)
library(dplyr)
library(purrr)
library(tidyr)
library(stringr)
library(stringdist)
library(imfapi)

## =================================================================
## 1. CONFIG -- change this for each country
## =================================================================

COUNTRY       <- "DEU"        # OECD REF_AREA code (3-letter): "DEU", "GBR", "JPN", "FRA", "CAN", ...
FRED_COUNTRY  <- "DE"         # FRED's OECD-mirror code (2-letter): "DE", "GB", "JP", "FR", "CA", ...
                               # NOTE: these are two DIFFERENT coding conventions from two
                               # different sources. Mixing them up is a common silent-failure
                               # trap -- e.g. requesting OECD data with "DE" or FRED data with
                               # "DEU" will just come back empty, not error loudly.
START_PERIOD  <- "1995-Q1"

# Optional. Leave blank ("") to skip LLM adjudication entirely and
# just take the top string-similarity match.
ANTHROPIC_API_KEY <- Sys.getenv("ANTHROPIC_API_KEY")

## =================================================================
## 2. ANCHOR CONCEPTS -- stable OECD SNA transaction codes
##    Same code works for any REF_AREA in OECD's QNA dataflow.
## =================================================================

anchor_concepts <- tribble(
  ~label,                              ~transaction,  ~sector, ~counterpart_sector,
  "real_gdp",                          "B1GQ",        "S1",    "S1",
  "real_household_consumption",        "P31S14_S15",  "S1",    "S1",
  "real_govt_consumption",             "P3",          "S13",   "S1",
  "real_gfcf_total",                   "P51G",        "S1",    "S1",
  "real_exports",                      "P6",           "S1",   "S1",
  "real_imports",                      "P7",           "S1",   "S1",
  "real_household_disposable_income",  "B6G",         "S14",   "S1"
)

## Helper: build an OECD SDMX key for the DF_TABLE1_EXPENDITURE dataflow.
## Dimension order assumed: FREQ.REF_AREA.SECTOR.COUNTERPART_SECTOR.
##   TRANSACTION.ACTIVITY.VALUATION.PRICE_BASE.TRANSFORMATION.ADJUSTMENT
## ADJUST IF NEEDED: confirm this order via OECD Data Explorer's
## "Developer API" button for one series before trusting it at scale.
build_oecd_key <- function(country, sector, counterpart_sector, transaction) {
  paste("Q", country, sector, counterpart_sector, transaction,
        "_T", "_Z", "L", "N", "Y", sep = ".")
}

fetch_oecd_series <- function(country, sector, counterpart_sector, transaction, label,
                               start_period = START_PERIOD) {
  key <- build_oecd_key(country, sector, counterpart_sector, transaction)
  url <- paste0(
    "https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NAMAIN10@DF_TABLE1_EXPENDITURE/",
    key,
    "?startPeriod=", start_period,
    "&dimensionAtObservation=AllDimensions&format=csvfilewithlabels"
  )

  resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    warning(sprintf("[%s] OECD fetch failed for %s (HTTP %s) -- URL: %s",
                     label, transaction,
                     if (is.null(resp)) "no response" else status_code(resp),
                     url))
    return(NULL)
  }

  txt <- content(resp, as = "text", encoding = "UTF-8")
  if (nchar(trimws(txt)) == 0 || !str_detect(txt, regex("OBS_VALUE|obsValue", ignore_case = TRUE))) {
    warning(sprintf("[%s] OECD returned no observations for key '%s' -- likely wrong dimension order or unavailable for this country",
                     label, key))
    return(NULL)
  }

  df <- suppressWarnings(read_csv(txt, show_col_types = FALSE))

  # Column names vary by dataflow vintage -- find them dynamically.
  time_col  <- names(df)[str_detect(names(df), regex("TIME_PERIOD|obsTime", ignore_case = TRUE))][1]  # ADJUST IF NEEDED
  value_col <- names(df)[str_detect(names(df), regex("OBS_VALUE|obsValue", ignore_case = TRUE))][1]   # ADJUST IF NEEDED

  if (is.na(time_col) || is.na(value_col)) {
    warning(sprintf("[%s] Could not identify time/value columns in response", label))
    return(NULL)
  }

  out <- df %>%
    transmute(period = .data[[time_col]], value = as.numeric(.data[[value_col]])) %>%
    distinct(period, .keep_all = TRUE)

  names(out)[2] <- label
  out
}

## ---- Download all anchor series -----------------------------------
message("Downloading anchor NIPA concepts for ", COUNTRY, " from OECD...")

anchor_data <- pmap(
  list(anchor_concepts$sector, anchor_concepts$counterpart_sector,
       anchor_concepts$transaction, anchor_concepts$label),
  function(sector, counterpart_sector, transaction, label) {
    fetch_oecd_series(COUNTRY, sector, counterpart_sector, transaction, label)
  }
)
names(anchor_data) <- anchor_concepts$label
anchor_data <- compact(anchor_data)  # drop any failed pulls, with warnings already printed

if (length(anchor_data) == 0) {
  stop("No anchor series downloaded -- check the COUNTRY code and the key structure (see warnings above).")
}

anchor_merged <- reduce(anchor_data, full_join, by = "period") %>%
  arrange(period)

## =================================================================
## 2b. IMF FALLBACK -- for anchor concepts OECD didn't return
## =================================================================
## IMF covers far more countries than OECD (whose membership is a
## fixed list of ~38 mostly-high-income countries), so this matters
## most when COUNTRY isn't an OECD member. Uses the "imfapi" package
## (CRAN, Econdataverse project) rather than a hand-built SDMX key --
## it resolves dimension codes against the dataset's own structure
## instead of requiring a guessed dot-position order, which is more
## robust than what I could verify for OECD/BIS/ECB above.
##
## CONFIDENCE NOTE: I'm confident in the package and its mechanism; I
## am NOT fully confident in the exact INDICATOR codes below for the
## "NEA" (National Economic Accounts, Quarterly) dataflow, since I
## can't execute this live. It's wrapped in tryCatch so a wrong code
## just skips that concept with a message, rather than erroring the
## whole script.

imf_indicator_map <- tribble(
  ~label,                              ~imf_indicator,
  "real_gdp",                          "NGDP_R",
  "real_household_consumption",        "NCP_R",
  "real_govt_consumption",             "NCGG_R",
  "real_gfcf_total",                   "NFI_R",
  "real_exports",                      "NX_R",
  "real_imports",                      "NM_R"
)
## NOTE: no IMF fallback attempted for household disposable income --
## that concept is not reliably present in IMF's country-level national
## accounts data.

fetch_imf_fallback <- function(indicator, country3, label) {
  result <- tryCatch(
    imf_get(
      dataflow_id = "NEA",
      dimensions = list(REF_AREA = country3, INDICATOR = indicator, FREQ = "Q"),
      start_period = START_PERIOD
    ),
    error = function(e) {
      message(sprintf("[%s] IMF fallback failed for indicator '%s': %s",
                       label, indicator, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result) || nrow(result) == 0) return(NULL)

  # ADJUST IF NEEDED: exact column names returned by imf_get() -- inspect
  # str(result) if this breaks, the package returns a tidy tibble but
  # column naming may differ by dataflow version.
  time_col  <- names(result)[str_detect(names(result), regex("period|TIME", ignore_case = TRUE))][1]
  value_col <- names(result)[str_detect(names(result), regex("value|OBS", ignore_case = TRUE))][1]
  if (is.na(time_col) || is.na(value_col)) return(NULL)

  out <- result %>% transmute(period = .data[[time_col]], value = as.numeric(.data[[value_col]]))
  names(out)[2] <- label
  out
}

missing_anchors <- setdiff(anchor_concepts$label, names(anchor_merged))
if (length(missing_anchors) > 0) {
  message("OECD had no data for: ", paste(missing_anchors, collapse = ", "),
          " -- trying IMF NEA quarterly as a fallback...")

  imf_fallback_data <- imf_indicator_map %>%
    filter(label %in% missing_anchors) %>%
    pmap(function(label, imf_indicator) fetch_imf_fallback(imf_indicator, COUNTRY, label)) %>%
    compact()

  if (length(imf_fallback_data) > 0) {
    for (df in imf_fallback_data) {
      anchor_merged <- full_join(anchor_merged, df, by = "period")
    }
    anchor_merged <- arrange(anchor_merged, period)
    message("Filled ", length(imf_fallback_data), " concept(s) from IMF.")
  } else {
    message("IMF fallback also returned nothing for the missing concepts -- ",
            "verify indicator codes at https://data.imf.org for dataflow 'NEA'.")
  }
}

## =================================================================
## 3. FUZZY MATCHING -- for anything beyond the 7 anchor concepts
## =================================================================
## Pulls the REAL list of transaction concepts OECD publishes, then
## scores it against a keyword, so you only ever try codes that
## genuinely exist rather than guessing at BEA-style breakdowns that
## OECD may not carry (e.g. "residential vs nonresidential investment").

get_oecd_transaction_codelist <- function() {
  url <- "https://sdmx.oecd.org/public/rest/codelist/OECD.SDD.NAD/CL_TRANSACTION/latest?format=jsondata"
  resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    warning("Could not fetch OECD transaction codelist -- check URL / connectivity")
    return(NULL)
  }
  js <- fromJSON(content(resp, as = "text", encoding = "UTF-8"), flatten = TRUE)
  # ADJUST IF NEEDED: the exact nesting of codes in the JSON response
  # can vary between SDMX-JSON versions. Inspect `js` interactively
  # (e.g. str(js, max.level = 3)) if this line errors, and fix the path.
  codes <- js$Codelist$Code[[1]]
  codes
}

suggest_matches <- function(keyword, codelist, top_n = 5) {
  if (is.null(codelist)) return(NULL)
  labels <- codelist$Name.en  # ADJUST IF NEEDED: field name for the English label
  scores <- stringdist(tolower(keyword), tolower(labels), method = "jw")
  codelist %>%
    mutate(match_score = 1 - scores) %>%
    arrange(desc(match_score)) %>%
    head(top_n)
}

## ---- Optional: single cheap LLM call to adjudicate ambiguous matches
adjudicate_with_claude <- function(fred_description, candidates) {
  if (ANTHROPIC_API_KEY == "") {
    message("No ANTHROPIC_API_KEY set -- skipping LLM step, returning top string match")
    return(candidates[1, ])
  }

  prompt <- paste0(
    "I'm matching a US macroeconomic series to the closest OECD National Accounts ",
    "concept for cross-country comparison.\n\n",
    "US series description: \"", fred_description, "\"\n\n",
    "Candidate OECD concepts:\n",
    paste(sprintf("- %s: %s", candidates$id, candidates$Name.en), collapse = "\n"),
    "\n\nWhich candidate ID is the best conceptual match? Reply with ONLY the ID, ",
    "or NONE if none are a reasonable match."
  )

  resp <- POST(
    "https://api.anthropic.com/v1/messages",
    add_headers(
      "x-api-key" = ANTHROPIC_API_KEY,
      "anthropic-version" = "2023-06-01",
      "content-type" = "application/json"
    ),
    body = toJSON(list(
      model = "claude-haiku-4-5",
      max_tokens = 20,
      messages = list(list(role = "user", content = prompt))
    ), auto_unbox = TRUE)
  )

  if (status_code(resp) != 200) {
    warning("Claude API call failed (HTTP ", status_code(resp), ") -- falling back to top string match")
    return(candidates[1, ])
  }

  answer <- content(resp)$content[[1]]$text
  match_id <- str_trim(answer)
  matched <- candidates %>% filter(id == match_id)
  if (nrow(matched) == 0) candidates[1, ] else matched
}

## =================================================================
## 4. SAVE OUTPUT
## =================================================================
out_file <- paste0("nipa_", tolower(COUNTRY), "_from_oecd.csv")
write_csv(anchor_merged, out_file)
message("Saved ", nrow(anchor_merged), " periods x ", ncol(anchor_merged) - 1,
        " anchor series to '", out_file, "'")

print(tail(anchor_merged, 8))

## =================================================================
## 5. EXAMPLE: extending beyond the anchors
## =================================================================
## Uncomment to try matching something not in the anchor list, e.g.
## the FRED-QD "residential fixed investment" concept for Germany:
##
## codelist  <- get_oecd_transaction_codelist()
## candidates <- suggest_matches("gross fixed capital formation dwellings", codelist)
## best <- adjudicate_with_claude("Real private residential fixed investment (PRFIx)", candidates)
## print(best)
##
## Then feed best$id into fetch_oecd_series() as the `transaction`
## argument, using the appropriate sector for that concept.

## =================================================================
## 6. OTHER FRED-QD GROUPS -- via FRED's OECD/MEI mirror
## =================================================================
## FRED re-publishes OECD's Main Economic Indicators (MEI) database
## for most member countries under a predictable mnemonic pattern:
##   {OECD_MEI_PREFIX}{2-letter country}{freq}{measure/SA suffix}
## e.g. IRLTLT01DEM156N = long-term interest rate, Germany, monthly.
##
## This reuses the plain fredgraph.csv downloader (no API key) from
## the original fetch_fred_nipa.R script, so no new OECD dimension
## keys need to be guessed for these domains.
##
## CONFIDENCE NOTE: I'm reasonably confident in the PREFIX codes below
## (they're long-standing, widely-used OECD/MEI mnemonics), but the
## exact SUFFIX (frequency letter, seasonal adjustment, measure code)
## can vary by country depending on what that country actually
## reports. If a pull below comes back empty, the fetch function
## prints a FRED search URL so you can find the right suffix by hand
## in ~10 seconds, rather than silently giving you nothing.

other_groups <- tribble(
  ~fred_qd_group,                 ~label,                    ~id_template,             ~source,
  "Industrial Production",        "industrial_production",  "PRINTO01{cc}Q661S",      "OECD MEI (via FRED)",
  "Employment and Unemployment",  "unemployment_rate",       "LRHUTTTT{cc}Q156S",      "OECD MEI (via FRED)",
  "Prices",                       "cpi_index",               "CPALTT01{cc}Q661S",      "OECD MEI (via FRED)",
  "Interest Rates",               "long_term_rate",          "IRLTLT01{cc}Q156N",      "OECD MEI (via FRED)",
  "Exchange Rates",               "fx_rate_to_usd",          "CCUSMA02{cc}Q618N",      "OECD MEI (via FRED)",
  "Other",                        "consumer_confidence",     "CSCICP03{cc}Q460S",      "OECD MEI (via FRED)",
  "Housing",                      "house_price_real",        "Q{cc}R628BIS",           "BIS Residential Property Prices (via FRED)",
  "Inventories, Orders, and Sales","retail_sales_volume",    "SLRTTO01{cc}Q189S",      "OECD MEI (via FRED)",
  "Stock Markets",                "share_price_index",       "SPASTT01{cc}Q661N",      "OECD MEI (via FRED)"
)
## CONFIDENCE NOTE, by row:
##   - Industrial production / unemployment / CPI / interest rates /
##     exchange rates / consumer confidence: long-standing, widely
##     used OECD MEI mnemonic families -- reasonably confident in the
##     prefix, less so in the exact suffix for any given country.
##   - House prices: BIS's Residential Property Price database is the
##     standard cross-country source (much more consistent than trying
##     to replicate US-style "housing starts/permits", which most
##     countries don't report in a comparable way). Mnemonic pattern
##     is "Q" + 2-letter country + "R628BIS" (real) on FRED's mirror.
##   - Retail sales volume: used here as the closest cross-country
##     proxy for FRED-QD's Group 5 concept -- it is NOT the same thing
##     as US manufacturers' new orders/inventories, which don't have a
##     good cross-country equivalent at all (see skipped-groups note).
##   - Share price index: OECD MEI also carries a generic "all
##     shares" index, more consistent across countries than trying to
##     match a specific national index (DAX, FTSE, etc.) to the S&P 500.

get_fred_series <- function(fred_id) {
  url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=", fred_id)
  resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)

  txt <- content(resp, as = "text", encoding = "UTF-8")
  if (str_detect(txt, regex("<html|Bad Request|series does not exist", ignore_case = TRUE))) {
    return(NULL)
  }

  df <- suppressWarnings(read_csv(txt, show_col_types = FALSE))
  if (ncol(df) != 2) return(NULL)
  names(df) <- c("date", fred_id)
  df$date <- as.Date(df$date)
  df
}

fetch_other_group_series <- function(id_template, country2, label, source) {
  fred_id <- str_replace(id_template, "\\{cc\\}", country2)
  df <- get_fred_series(fred_id)

  if (is.null(df)) {
    warning(sprintf(
      "[%s / %s] '%s' not found. Search for the right mnemonic at: https://fred.stlouisfed.org/search?st=%s",
      label, source, fred_id, URLencode(str_remove(id_template, "\\{cc\\}"))
    ))
    return(NULL)
  }

  names(df)[2] <- label
  df
}

message("Downloading additional FRED-QD-style groups for ", FRED_COUNTRY,
        " via FRED's OECD/BIS mirrors...")

other_data <- pmap(
  list(other_groups$id_template, other_groups$label, other_groups$source),
  function(id_template, label, source) {
    fetch_other_group_series(id_template, FRED_COUNTRY, label, source)
  }
)
names(other_data) <- other_groups$label
other_data <- compact(other_data)

if (length(other_data) > 0) {
  other_merged <- reduce(other_data, full_join, by = "date") %>% arrange(date)
  other_out_file <- paste0("other_groups_", tolower(FRED_COUNTRY), "_from_fred_mirrors.csv")
  write_csv(other_merged, other_out_file)
  message("Saved ", nrow(other_merged), " rows x ", ncol(other_merged) - 1,
          " series to '", other_out_file, "'")
} else {
  message("No additional-group series downloaded -- check warnings above for correct mnemonics.")
}

## =================================================================
## 6b. MONEY AND CREDIT -- via BIS's own SDMX API (not FRED-mirrored)
## =================================================================
## BIS's "Credit to the Non-Financial Sector" database is the
## standard cross-country source for this concept (much more
## consistent across countries than trying to replicate US-specific
## commercial bank loan categories). Unlike the series above, this
## isn't mirrored on FRED under a simple country-swap mnemonic, so it
## needs a direct BIS API call.
##
## CONFIDENCE NOTE: I'm confident this dataset exists and is the right
## source conceptually, but -- same caveat as the OECD QNA key earlier
## -- I have not been able to execute this call live to verify the
## exact dimension order for BIS's SDMX API. This fails loudly (NULL +
## warning) rather than silently if the key is wrong; verify one
## country/series manually at https://data.bis.org before trusting a
## multi-country loop over this function.

fetch_bis_credit <- function(country3, label = "credit_to_private_nonfin_sector") {
  # BIS dataflow: "Credit to the non-financial sector" (WS_TC).
  # Dimension order per BIS documentation: FREQ.BORROWERS_CTY.
  #   LENDING_SECTOR.BORROWING_SECTOR.UNIT_TYPE.VALUATION.
  #   TC_ADJUST.TC_SUFFIX  -- ADJUST IF NEEDED, verify via data.bis.org
  key <- paste("Q", country3, "P", "N", "770", "M", "N", "A", sep = ".")
  url <- paste0(
    "https://stats.bis.org/api/v2/data/dataflow/BIS/WS_TC/1.0/", key,
    "?format=csv&startPeriod=", START_PERIOD
  )

  resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    warning(sprintf(
      "[%s] BIS credit fetch failed for %s (HTTP %s) -- verify the key manually at https://data.bis.org/topics/CRE",
      label, country3, if (is.null(resp)) "no response" else status_code(resp)
    ))
    return(NULL)
  }

  txt <- content(resp, as = "text", encoding = "UTF-8")
  if (nchar(trimws(txt)) == 0) {
    warning(sprintf("[%s] BIS returned no observations for key '%s'", label, key))
    return(NULL)
  }

  df <- suppressWarnings(read_csv(txt, show_col_types = FALSE))
  time_col  <- names(df)[str_detect(names(df), regex("TIME_PERIOD", ignore_case = TRUE))][1]
  value_col <- names(df)[str_detect(names(df), regex("OBS_VALUE", ignore_case = TRUE))][1]
  if (is.na(time_col) || is.na(value_col)) return(NULL)

  df %>% transmute(period = .data[[time_col]], !!label := as.numeric(.data[[value_col]]))
}

message("Attempting Money and Credit via BIS API for ", COUNTRY, "...")
credit_data <- fetch_bis_credit(COUNTRY)
if (!is.null(credit_data)) {
  anchor_merged <- full_join(anchor_merged, credit_data, by = "period") %>% arrange(period)
  message("Added credit series to the main anchor dataset.")
}

## =================================================================
## 6c. HOUSEHOLD BALANCE SHEETS -- euro-area countries only, via ECB
## =================================================================
## Quarterly household financial balance sheets (net worth,
## liabilities) are genuinely NOT available on a consistent quarterly
## basis for most non-European countries -- annual is the norm
## globally. Euro-area countries are the exception: the ECB's
## Statistical Data Warehouse publishes quarterly sector accounts.
## This block only runs for euro-area countries and is explicitly
## marked lower-confidence on exact key structure.

euro_area_countries <- c("AUT","BEL","CYP","EST","FIN","FRA","DEU","GRC","IRL",
                          "ITA","LVA","LTU","LUX","MLT","NLD","PRT","SVK","SVN","ESP")

if (COUNTRY %in% euro_area_countries) {
  message(COUNTRY, " is a euro-area country -- attempting household balance sheet ",
          "data via ECB SDW (quarterly sector accounts). ADJUST IF NEEDED: verify ",
          "the exact series key at https://data.ecb.europa.eu before trusting this.")

  fetch_ecb_household_networth <- function(country3) {
    # ECB Quarterly Sector Accounts (QSA) dataflow -- key structure is
    # a best-effort guess (FREQ.ADJUSTMENT.REF_AREA.SECTOR.COUNTERPART_SECTOR.
    # ...); this is the least-verified part of the whole script.
    url <- paste0(
      "https://data-api.ecb.europa.eu/service/data/QSA/Q.N.", country3,
      ".W0.S1M.S1.N.B90.A.F._Z._Z._Z.XDC._T.S.V.N._T"
    )
    resp <- tryCatch(GET(url, add_headers(Accept = "text/csv"), timeout(30)),
                      error = function(e) NULL)
    if (is.null(resp) || status_code(resp) != 200) {
      warning("ECB household net worth fetch failed -- this endpoint/key needs manual verification")
      return(NULL)
    }
    suppressWarnings(read_csv(content(resp, as = "text", encoding = "UTF-8"), show_col_types = FALSE))
  }

  hh_networth <- fetch_ecb_household_networth(COUNTRY)
  if (!is.null(hh_networth)) {
    message("ECB household net worth data retrieved -- inspect column names before merging, ",
            "structure varies by release.")
  }
} else {
  message(COUNTRY, " is not a euro-area country -- skipping household balance sheets ",
          "(no consistent quarterly source outside the euro area).")
}

## ---- Remaining genuine gaps ------------------------------------------
## After the additions above, these FRED-QD groups still have no
## reliable, verifiable cross-country source and are left out rather
## than guessed:
##   - Earnings and Productivity: OECD does publish a Productivity
##     Database (GDP per hour worked, unit labor costs), but I don't
##     have high enough confidence in its dataflow/dimension structure
##     to include a working call here without live verification --
##     start at https://data-explorer.oecd.org, topic "Productivity".
##   - Inventories/new orders specifically (as opposed to retail sales,
##     added above as a proxy): manufacturers' new orders and business
##     inventories are US Census Bureau concepts without a standardized
##     cross-country equivalent.
##   - Non-Household Balance Sheets (corporate sector debt/net worth):
##     BIS also publishes some corporate credit statistics, but a
##     clean nonfinancial-corporate balance sheet series cross-country
##     would need the same kind of manual key verification as the
##     household one above.
message("Remaining unresolved: Earnings and Productivity (needs OECD Productivity ",
        "Database key verification), Inventories/New Orders specifically (no cross-",
        "country equivalent), Non-Household Balance Sheets (needs BIS corporate ",
        "credit key verification, same pattern as household net worth above).")

## =================================================================
## 7. VALIDATE AGAINST THE ACTUAL FRED-QD FILE
## =================================================================
## FRED-QD's real file has an unusual structure: row 1 = mnemonics,
## row 2 = "factors" flag (0/1, whether S&W used it in factor
## estimation), row 3 = "transform" code (1-7, as defined in the
## FRED-QD paper), then data rows with dates as M/D/YYYY.
##
## Two uses here:
##   (a) VALIDATION: when COUNTRY == "USA", compare our OECD-sourced
##       anchor series against the real FRED-QD columns for the same
##       concept. If these don't track each other for the US -- where
##       we have ground truth -- the OECD code mapping is wrong, and
##       there's no point trusting it for another country.
##   (b) REUSE: pull the paper's own transformation codes so a
##       country-level dataset you build stays consistent with the
##       original methodology instead of guessing transformations.

FRED_QD_URL <- "https://www.stlouisfed.org/-/media/project/frbstl/stlouisfed/research/fred-md/quarterly/2026-07-qd.csv"

fetch_actual_fred_qd <- function(url) {
  resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    warning("Could not download the actual FRED-QD file -- check the URL/vintage date, ",
            "it's updated monthly so this exact filename may go stale.")
    return(NULL)
  }

  raw_lines <- content(resp, as = "text", encoding = "UTF-8")
  con <- textConnection(raw_lines)
  raw <- read.csv(con, header = FALSE, stringsAsFactors = FALSE)
  close(con)

  mnemonics  <- as.character(raw[1, ])
  factors    <- as.numeric(raw[2, -1])
  transform  <- as.numeric(raw[3, -1])
  data_rows  <- raw[-(1:3), ]
  names(data_rows) <- mnemonics

  data_rows$sasdate <- as.Date(data_rows$sasdate, format = "%m/%d/%Y")
  data_rows[, -1] <- lapply(data_rows[, -1], as.numeric)

  list(
    data = data_rows,
    transform_codes = setNames(transform, mnemonics[-1]),
    factor_flags    = setNames(factors, mnemonics[-1])
  )
}

message("Downloading the actual FRED-QD file for validation (note: the filename ",
        "is a dated monthly vintage -- update FRED_QD_URL if this one 404s)...")
fred_qd_actual <- fetch_actual_fred_qd(FRED_QD_URL)

if (!is.null(fred_qd_actual) && COUNTRY == "USA") {
  message("COUNTRY is USA -- running validation against the real FRED-QD file...")

  # Map our anchor labels to their real FRED-QD mnemonics
  validation_map <- tribble(
    ~our_label,                          ~fred_qd_mnemonic,
    "real_gdp",                          "GDPC1",
    "real_household_consumption",        "PCECC96",
    "real_govt_consumption",             "GCEC1",
    "real_gfcf_total",                   "GPDIC1",
    "real_exports",                      "EXPGSC1",
    "real_imports",                      "IMPGSC1",
    "real_household_disposable_income",  "DPIC96"
  )

  validation_results <- validation_map %>%
    filter(our_label %in% names(anchor_merged)) %>%
    mutate(
      correlation = map2_dbl(our_label, fred_qd_mnemonic, function(ours, theirs) {
        if (!(theirs %in% names(fred_qd_actual$data))) return(NA_real_)

        ours_series   <- anchor_merged %>% select(period, value = all_of(ours))
        theirs_series <- fred_qd_actual$data %>%
          transmute(period = format(sasdate, "%Y-Q%q"), value = .data[[theirs]])
        # NOTE: OECD's period format (e.g. "1995-Q1") and FRED-QD's date-based
        # format need to line up -- ADJUST IF NEEDED depending on what OECD
        # actually returned for the `period` column upstream.

        # Compare GROWTH RATES, not levels -- OECD reports national-currency
        # levels while FRED-QD reports chained-dollar levels, so only the
        # log-difference (growth) is comparable across the two sources.
        merged <- inner_join(ours_series, theirs_series, by = "period", suffix = c("_oecd", "_fred"))
        if (nrow(merged) < 8) return(NA_real_)

        g_oecd <- diff(log(merged$value_oecd))
        g_fred <- diff(log(merged$value_fred))
        suppressWarnings(cor(g_oecd, g_fred, use = "complete.obs"))
      })
    )

  print(validation_results)
  message("Correlations near 1.0 confirm the OECD transaction code is pulling the ",
          "same underlying concept as FRED-QD's own series. Anything well below ~0.9 ",
          "means the OECD code (sector/transaction combination) is likely wrong for ",
          "that concept and should be checked before trusting it for another country.")
} else if (!is.null(fred_qd_actual)) {
  message("COUNTRY is not USA -- skipping direct validation (FRED-QD only covers ",
          "the US). Using the real file only to borrow its transformation codes below.")
}

## ---- Reuse the paper's own transformation codes ---------------------
if (!is.null(fred_qd_actual)) {
  transform_lookup <- tribble(
    ~our_label,                          ~fred_qd_mnemonic,
    "real_gdp",                          "GDPC1",
    "real_household_consumption",        "PCECC96",
    "real_govt_consumption",             "GCEC1",
    "real_gfcf_total",                   "GPDIC1",
    "real_exports",                      "EXPGSC1",
    "real_imports",                      "IMPGSC1",
    "real_household_disposable_income",  "DPIC96"
  ) %>%
    mutate(transform_code = fred_qd_actual$transform_codes[fred_qd_mnemonic])

  message("Transformation codes borrowed from the actual FRED-QD file (1=none, ",
          "2=diff, 3=2nd diff, 4=log, 5=log-diff, 6=2nd log-diff, 7=pct-change-of-ratio):")
  print(transform_lookup)

  # Apply them to the country-level series, e.g.:
  # anchor_merged$real_gdp_transformed <- if (transform_lookup$transform_code[transform_lookup$our_label == "real_gdp"] == 5) {
  #   c(NA, diff(log(anchor_merged$real_gdp)))
  # } else {
  #   anchor_merged$real_gdp
  # }
}
