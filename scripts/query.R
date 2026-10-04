#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## query.R -- find, describe and pull series from the built panels,
## through the semantic layer in R/semantic_layer.R. Reads output/ only;
## fetches nothing. Results go to stdout (CSV or JSON) so the script can
## be piped, and errors name the fix.
##
## Usage:
##   Rscript scripts/query.R search house prices
##   Rscript scripts/query.R describe cpi_index
##   Rscript scripts/query.R get --series real_gdp,inflation_yoy --country AUT,DEU \
##       --freq Q --transform level --from 2015-Q1 [--format wide]
##   Rscript scripts/query.R list concepts|metrics|transforms|countries
##
## Options for `get`:
##   --series     comma-separated concept labels / derived metrics (exact)
##   --country    comma-separated ISO alpha-3 codes [default: all built]
##   --freq       Q or M [default Q]
##   --transform  level, pct_change, yoy, saar, diff, diff_yoy, log,
##                log_diff, tcode_fred, tcode_lt, tcode_ht [default level]
##   --from, --to YYYY, YYYY-Qn, YYYY-Mnn, YYYY-MM or YYYY-MM-DD
##   --format     long or wide [default long]
##   --output-dir where the panels are [default output]
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

usage <- function() {
  cat(paste(
    "Usage:",
    "  Rscript scripts/query.R search <words...> [--n 10]",
    "  Rscript scripts/query.R describe <concept-or-metric>",
    "  Rscript scripts/query.R get --series a,b [--country AUT,DEU] [--freq Q|M] [--transform level]",
    "                             [--from 2015-Q1] [--to 2025-Q4] [--format long|wide]",
    "  Rscript scripts/query.R list concepts|metrics|transforms|countries",
    sep = "\n"), "\n")
}

#' Split the arguments into positional words and --key value options
parse_cli <- function(args) {
  opts <- list(); words <- character(0); i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (startsWith(a, "--")) {
      key <- gsub("-", "_", sub("^--", "", a))
      if (grepl("=", key)) {
        opts[[sub("=.*", "", key)]] <- sub("^[^=]*=", "", a)
      } else {
        opts[[key]] <- if (i < length(args)) args[i + 1] else ""
        i <- i + 1
      }
    } else {
      words <- c(words, a)
    }
    i <- i + 1
  }
  list(words = words, opts = opts)
}

split_list <- function(x) if (is.null(x)) NULL else trimws(strsplit(x, ",")[[1]])

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || args[1] %in% c("-h", "--help", "help")) {
  usage(); quit(status = 0)
}
cmd <- args[1]
cli <- parse_cli(args[-1])
output_dir <- cli$opts$output_dir %||% file.path(project_root, "output")
write_out <- function(df) readr::write_csv(df, stdout(), na = "")

result <- tryCatch({
  switch(cmd,
    search = {
      if (length(cli$words) == 0) stop("search needs some words, e.g. `search inflation`", call. = FALSE)
      write_out(amd_search(paste(cli$words, collapse = " "), n = as.integer(cli$opts$n %||% 10)))
    },
    describe = {
      if (length(cli$words) != 1) stop("describe needs exactly one concept or metric name", call. = FALSE)
      cat(jsonlite::toJSON(amd_describe(cli$words, output_dir), auto_unbox = TRUE, pretty = TRUE,
                           na = "null", null = "null"), "\n")
    },
    get = {
      series <- split_list(cli$opts$series %||% paste(cli$words, collapse = ","))
      if (length(series) == 0 || !nzchar(series[1])) stop("get needs --series", call. = FALSE)
      write_out(amd_get(series, countries = split_list(cli$opts$country),
                        frequency = cli$opts$freq %||% "Q", transform = cli$opts$transform %||% "level",
                        from = cli$opts$from, to = cli$opts$to, format = cli$opts$format %||% "long",
                        output_dir = output_dir))
    },
    list = {
      what <- if (length(cli$words) > 0) cli$words[1] else "concepts"
      write_out(switch(what,
        concepts = dplyr::left_join(concept_dictionary, concept_semantics, by = "label") %>%
          dplyr::select("label", "title", group = "fred_qd_group", "frequency", "unit", "scope"),
        metrics = dplyr::mutate(derived_metrics[, c("name", "title", "unit", "formula")],
                                frequencies = vapply(.data$name, function(m) paste(metric_frequencies(m), collapse = ","), "")),
        transforms = semantic_transforms,
        countries = semantic_availability(semantic_countries(output_dir), output_dir) %>%
          dplyr::group_by(.data$country) %>%
          dplyr::summarise(unresolved = sum(!.data$resolved), resolved = sum(.data$resolved),
                           last_quarterly = max(.data$last[.data$frequency == "Q"], na.rm = TRUE),
                           last_monthly = max(.data$last[.data$frequency == "M"], na.rm = TRUE)),
        stop("list what? concepts, metrics, transforms or countries", call. = FALSE)))
    },
    { usage(); stop("Unknown command '", cmd, "'", call. = FALSE) }
  )
  0L
}, error = function(e) {
  message("Error: ", conditionMessage(e))
  1L
})
quit(status = result)
