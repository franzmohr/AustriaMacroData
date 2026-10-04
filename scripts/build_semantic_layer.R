#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_semantic_layer.R -- rewrite output/semantic/ (catalog.json,
## concepts.csv, availability.csv) from the panels already in output/,
## without fetching anything. scripts/build_panels.R does the same at the
## end of every run; this is for when only R/semantic_layer.R or
## R/concept_dictionary.R changed. See R/semantic_layer.R.
##
## Usage:
##   Rscript scripts/build_semantic_layer.R [--output-dir output]
## ---------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble)
})

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m)) return(normalizePath(sub("^--file=", "", args[m[1]])))
  normalizePath(sys.frames()[[1]]$ofile)
}
project_root <- dirname(dirname(this_file()))
for (f in list.files(file.path(project_root, "R"), full.names = TRUE, pattern = "[.]R$")) source(f)

args <- commandArgs(trailingOnly = TRUE)
i <- match("--output-dir", args)
output_dir <- if (!is.na(i) && i < length(args)) args[i + 1] else file.path(project_root, "output")

catalog <- write_semantic_layer(output_dir)
message("Wrote the semantic layer for ", length(catalog$countries), " countries (",
        paste(vapply(catalog$countries, `[[`, "", "code"), collapse = ", "), ") to '",
        file.path(output_dir, "semantic"), "'")
