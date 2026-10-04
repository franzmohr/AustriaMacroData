#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## update_monthly.R -- scheduled entrypoint, run by
## .github/workflows/monthly-update.yml on the 1st of every month.
##
## Rebuilds every panel for each country below with
## scripts/build_panels.R -- one fetch, from which the monthly and
## quarterly panels, the series metadata and the policy-event dummies are
## all written -- then archives a dated copy of each into
## output/vintages/, mirroring how FRED-QD and EA-MD-QD keep a monthly
## vintage history rather than only ever exposing "latest".
##
## The name of this file is about CADENCE, not frequency: it has run
## monthly since before there was a monthly panel.
## ---------------------------------------------------------------

countries <- c("AUT", "DEU", "USA")
output_dir <- "output"
vintage_dir <- file.path(output_dir, "vintages")
dir.create(vintage_dir, showWarnings = FALSE, recursive = TRUE)

vintage_tag <- format(Sys.Date(), "%Y-%m")

## Every file build_panels.R writes for a country, as <cc><suffix>.
archived_suffixes <- c("_panel.csv", "_coverage.json",
                       "_monthly_panel.csv", "_monthly_coverage.json",
                       "_metadata.csv",
                       "_dummies_monthly.csv", "_dummies_quarterly.csv")

archive <- function(cc) {
  for (suffix in archived_suffixes) {
    from <- file.path(output_dir, paste0(cc, suffix))
    if (!file.exists(from)) next
    to <- sub("([.][a-z]+)$", paste0("_", vintage_tag, "\\1"), basename(from))
    file.copy(from, file.path(vintage_dir, to), overwrite = TRUE)
  }
}

for (country in countries) {
  message("=== Building ", country, " (vintage ", vintage_tag, ") ===")
  status <- system2(
    "Rscript",
    c("scripts/build_panels.R", "--country", country, "--output-dir", output_dir)
  )
  if (status != 0) {
    stop("build_panels.R failed for ", country, " (exit status ", status, ")", call. = FALSE)
  }
  archive(tolower(country))
}

message("Update complete (monthly and quarterly) for: ", paste(countries, collapse = ", "))
