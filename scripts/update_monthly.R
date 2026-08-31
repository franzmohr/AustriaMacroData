#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## update_monthly.R -- scheduled entrypoint, run by
## .github/workflows/monthly-update.yml on the 1st of every month.
##
## Rebuilds output/<country>_panel.csv + _coverage.json for each country
## below via scripts/build_country_panel.R, then archives a dated copy
## of both into output/vintages/, mirroring how FRED-QD itself keeps a
## monthly vintage history rather than only ever exposing "latest".
## ---------------------------------------------------------------

countries <- c("AUT", "DEU", "USA")
output_dir <- "output"
vintage_dir <- file.path(output_dir, "vintages")
dir.create(vintage_dir, showWarnings = FALSE, recursive = TRUE)

vintage_tag <- format(Sys.Date(), "%Y-%m")

for (country in countries) {
  message("=== Building ", country, " (vintage ", vintage_tag, ") ===")
  status <- system2(
    "Rscript",
    c("scripts/build_country_panel.R", "--country", country, "--output-dir", output_dir)
  )
  if (status != 0) {
    stop("build_country_panel.R failed for ", country, " (exit status ", status, ")", call. = FALSE)
  }

  cc <- tolower(country)
  file.copy(
    file.path(output_dir, paste0(cc, "_panel.csv")),
    file.path(vintage_dir, paste0(cc, "_panel_", vintage_tag, ".csv")),
    overwrite = TRUE
  )
  file.copy(
    file.path(output_dir, paste0(cc, "_coverage.json")),
    file.path(vintage_dir, paste0(cc, "_coverage_", vintage_tag, ".json")),
    overwrite = TRUE
  )
}

message("Monthly update complete for: ", paste(countries, collapse = ", "))
