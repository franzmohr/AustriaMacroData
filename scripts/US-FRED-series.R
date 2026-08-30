

## ---------------------------------------------------------------
## fetch_fred_nipa.R
##
## Downloads a set of quarterly U.S. NIPA series from FRED that have
## reasonably close counterparts in the OECD Quarterly National
## Accounts (QNA) database, so you can benchmark FRED vs. OECD.
##
## No API key required: this uses FRED's public "fredgraph.csv"
## export endpoint, which works for any single series ID.
##
## Output: a single wide CSV (date + one column per series) written
## to fred_nipa_comparison.csv in the working directory.
## ---------------------------------------------------------------

## ---- 0. Packages -------------------------------------------------
required_pkgs <- c("httr", "readr", "dplyr", "purrr", "tidyr", "stringr")
new_pkgs <- required_pkgs[!(required_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs, repos = "https://cloud.r-project.org")

library(httr)
library(readr)
library(dplyr)
library(purrr)
library(tidyr)
library(stringr)

## ---- 1. Series to download ---------------------------------------
## Mnemonics are official FRED codes (not the FRED-QD "x"-suffixed
## researcher-adjusted variants), since those are the ones you'd
## realistically line up against an OECD download.
##
## Feel free to add/remove rows. `label` is just a human-readable
## name used for the output columns.

series_list <- tribble(
  ~fred_id,      ~label,
  "GDPC1",       "real_gdp",
  "PCECC96",     "real_pce_total",
  "PCEDGC96",    "real_pce_durables",
  "PCESVC96",    "real_pce_services",
  "PCNDGC96",    "real_pce_nondurables",
  "GPDIC1",      "real_gross_priv_dom_investment",
  "PNFIC1",      "real_priv_fixed_investment_nonres",
  "PRFIC1",      "real_priv_fixed_investment_res",
  "GCEC1",       "real_gov_consumption_investment",
  "EXPGSC1",     "real_exports_goods_services",
  "IMPGSC1",     "real_imports_goods_services",
  "DPIC96",      "real_disposable_personal_income"
)

## ---- 2. Helper: pull one series via fredgraph.csv -----------------
get_fred_series <- function(fred_id) {
  url <- paste0(
    "https://fred.stlouisfed.org/graph/fredgraph.csv?id=", fred_id
  )
  
  resp <- GET(url)
  if (status_code(resp) != 200) {
    warning(sprintf("Failed to download %s (HTTP %s)", fred_id, status_code(resp)))
    return(NULL)
  }
  
  df <- read_csv(content(resp, as = "text", encoding = "UTF-8"),
                 show_col_types = FALSE)
  
  # fredgraph.csv returns columns: DATE, <SERIES_ID>
  names(df) <- c("date", fred_id)
  df$date <- as.Date(df$date)
  df
}

## ---- 3. Download all series and merge -----------------------------
message("Downloading ", nrow(series_list), " series from FRED...")

raw_data <- map(series_list$fred_id, get_fred_series)
names(raw_data) <- series_list$fred_id

# Drop any that failed to download
ok <- !map_lgl(raw_data, is.null)
if (any(!ok)) {
  message("Warning: the following series failed and were skipped: ",
          paste(series_list$fred_id[!ok], collapse = ", "))
}
raw_data <- raw_data[ok]

merged <- reduce(raw_data, full_join, by = "date") %>%
  arrange(date)

# Rename columns to human-readable labels
id_to_label <- setNames(series_list$label, series_list$fred_id)
names(merged) <- ifelse(names(merged) %in% names(id_to_label),
                        id_to_label[names(merged)],
                        names(merged))

## ---- 4. Restrict to quarterly observations ------------------------
## Some FRED series are released monthly even though they represent
## quarterly concepts (rare here, but just in case) -- this keeps
## only Q1/Q4/Q7/Q10-start months. Skip this filter if your series
## are already quarterly-dated (the ones above are).
merged <- merged %>%
  filter(format(date, "%m") %in% c("01", "04", "07", "10"))

## ---- 5. Save output -------------------------------------------------
out_file <- "fred_nipa_comparison.csv"
write_csv(merged, out_file)

message("Done. Saved ", nrow(merged), " rows x ", ncol(merged) - 1,
        " series to '", out_file, "'")

## ---- 6. Quick peek ---------------------------------------------------
print(tail(merged, 8))
