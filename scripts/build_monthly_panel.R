#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_monthly_panel.R -- kept so that existing commands keep working
##
## Until 2026-10 this script built the monthly panel on its own, beside a
## quarterly builder that fetched the same concepts again at quarterly
## frequency. It now runs scripts/build_panels.R with the same arguments,
## which fetches every concept once at its native frequency and writes the
## monthly panel (output/<cc>_monthly_panel.csv, same name and columns as
## before, plus the two degree-day concepts that are now monthly) together
## with the quarterly panel, the series metadata and the policy-event
## dummies. The fetching code, with its notes on how each
## monthly source was verified, is in R/panel_monthly.R.
##
## Usage (unchanged):
##   Rscript scripts/build_monthly_panel.R --country AUT
##   Rscript scripts/build_monthly_panel.R --country DEU --start-period 1990-M01
## ---------------------------------------------------------------

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m)) return(normalizePath(sub("^--file=", "", args[m[1]])))
  normalizePath(sys.frames()[[1]]$ofile)
}
source(file.path(dirname(this_file()), "build_panels.R"))
