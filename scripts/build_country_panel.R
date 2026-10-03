#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_country_panel.R -- kept so that existing commands keep working
##
## Until 2026-10 this script built the quarterly panel on its own,
## fetching every concept at quarterly frequency. It now runs
## scripts/build_panels.R with the same arguments, which fetches every
## concept once at its native frequency and writes the quarterly panel
## (output/<cc>_panel.csv, same name and columns as before) together with
## the monthly and mixed-frequency panels, the series metadata and the
## policy-event dummies. See that script's header for why, and git
## history for this script's own record of how each quarterly source was
## verified -- those notes now live beside the code in R/panel_quarterly.R
## and R/panel_monthly.R.
##
## Usage (unchanged):
##   Rscript scripts/build_country_panel.R --country DEU --start-period 1960-Q1
##   Rscript scripts/build_country_panel.R --country USA --validate
## ---------------------------------------------------------------

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m)) return(normalizePath(sub("^--file=", "", args[m[1]])))
  normalizePath(sys.frames()[[1]]$ofile)
}
source(file.path(dirname(this_file()), "build_panels.R"))
