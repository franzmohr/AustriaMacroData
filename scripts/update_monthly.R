#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## update_monthly.R -- scheduled entrypoint, run by
## .github/workflows/monthly-update.yml on the 1st of every month.
##
## Rebuilds both panels for each country below -- the quarterly one via
## scripts/build_country_panel.R and the monthly one via
## scripts/build_monthly_panel.R -- then archives a dated copy of each
## into output/vintages/, mirroring how FRED-QD itself keeps a monthly
## vintage history rather than only ever exposing "latest".
##
## The name of this file is about CADENCE, not frequency: it has run
## monthly since before there was a monthly panel. The monthly panel is
## rebuilt on the same schedule because its sources revise on the same
## schedule, not because of the coincidence in the two names.
## ---------------------------------------------------------------

countries <- c("AUT", "DEU", "USA")
output_dir <- "output"
vintage_dir <- file.path(output_dir, "vintages")
dir.create(vintage_dir, showWarnings = FALSE, recursive = TRUE)

vintage_tag <- format(Sys.Date(), "%Y-%m")

archive <- function(cc, stem) {
  for (ext in c("csv", "json")) {
    name <- if (ext == "csv") paste0(cc, stem, "panel") else paste0(cc, stem, "coverage")
    from <- file.path(output_dir, paste0(name, ".", ext))
    if (!file.exists(from)) next
    file.copy(from, file.path(vintage_dir, paste0(name, "_", vintage_tag, ".", ext)),
              overwrite = TRUE)
  }
}

for (country in countries) {
  cc <- tolower(country)

  message("=== Building ", country, " quarterly (vintage ", vintage_tag, ") ===")
  status <- system2(
    "Rscript",
    c("scripts/build_country_panel.R", "--country", country, "--output-dir", output_dir)
  )
  if (status != 0) {
    stop("build_country_panel.R failed for ", country, " (exit status ", status, ")", call. = FALSE)
  }
  archive(cc, "_")

  message("=== Building ", country, " monthly (vintage ", vintage_tag, ") ===")
  status <- system2(
    "Rscript",
    c("scripts/build_monthly_panel.R", "--country", country, "--output-dir", output_dir)
  )
  if (status != 0) {
    stop("build_monthly_panel.R failed for ", country, " (exit status ", status, ")", call. = FALSE)
  }
  archive(cc, "_monthly_")
}

message("Update complete (both frequencies) for: ", paste(countries, collapse = ", "))
