#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## build_monthly_panel.R -- CLI entrypoint for the MONTHLY panel
##
## The companion to scripts/build_country_panel.R, standing to it as
## FRED-MD stands to FRED-QD: fewer concepts, twelve observations a year
## instead of four, and the same concept labels wherever the same thing
## is being measured.
##
## Usage:
##   Rscript scripts/build_monthly_panel.R --country AUT
##   Rscript scripts/build_monthly_panel.R --country DEU --start-period 1990-M01
##
## NOT TO BE CONFUSED WITH scripts/update_monthly.R, which is about
## CADENCE rather than frequency: it is the scheduled job that rebuilds
## the QUARTERLY panels once a month and archives a vintage of each.
##
## WHY A SEPARATE SCRIPT. Adding a --frequency flag to the quarterly
## builder was the other option and was rejected: two thirds of that
## file is national accounts, BIS credit and government finance, none of
## which exist monthly, so the flag would have had to guard nearly every
## section and the quarterly path -- which is in use -- would have had
## to be re-verified line by line to prove it had not moved. The risk is
## all on one side. What the two scripts DO share is the thing that
## would otherwise drift: both take their concept list from
## R/concept_dictionary.R rather than from a hand-written list, and this
## one asks it for `available_monthly`.
##
## WHAT IS NOT HERE, AND WHY IT IS NOT INTERPOLATED. Twenty-two of the 49
## concepts are quarterly at source -- every national-accounts concept,
## the BIS credit series, government debt and the primary balance, hours
## worked, population, the change in inventories, unit labour cost, the
## employment rate, real house prices, the World Uncertainty Index and
## the two degree-day series. They are absent from this panel rather
## than spread across three months each. A quarterly figure repeated or
## smoothed into monthly cells is an invention that is indistinguishable
## from data once it is in a CSV, and anyone who wants one can make it
## from the quarterly panel knowing that they did.
##
## THE TWO PANELS SHARE LABELS, NOT SERIES. Where a concept is in both,
## it often comes from a different source at the two frequencies --
## industrial production is Eurostat's sts_inpr_m here and an OECD MEI
## mirror there, on different index bases. Growth rates are comparable;
## levels are not. docs/data_sources_monthly.csv records exactly what
## each monthly column is, separately from the quarterly registry, for
## that reason.
## ---------------------------------------------------------------

suppressPackageStartupMessages({
  library(httr); library(jsonlite); library(readr); library(dplyr)
  library(purrr); library(tidyr); library(stringr); library(tibble)
  library(optparse)
})

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m)) return(normalizePath(sub("^--file=", "", args[m[1]])))
  normalizePath(sys.frames()[[1]]$ofile)
}
project_root <- dirname(dirname(this_file()))
for (f in list.files(file.path(project_root, "R"), full.names = TRUE, pattern = "\\.R$")) {
  source(f)
}

FREQ <- "M"
`%||%` <- function(a, b) if (is.null(a)) b else a

option_list <- list(
  make_option("--country", type = "character", default = NULL,
              help = "ISO-3166 alpha-3 country code, e.g. AUT, DEU [required]"),
  make_option("--start-period", type = "character", default = "1960-M01", dest = "start_period",
              help = "First month to fetch, format YYYY-Mnn (a YYYY-Qn start is accepted and read as the first month of that quarter) [default %default]"),
  make_option("--fred-country2", type = "character", default = NULL, dest = "fred_country2",
              help = "FRED's 2-letter OECD-mirror country code, if not in the built-in table"),
  make_option("--output-dir", type = "character", default = "output", dest = "output_dir",
              help = "Directory to write <country>_monthly_panel.csv and <country>_monthly_coverage.json into [default %default]")
)
opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$country)) stop("--country is required, e.g. --country AUT", call. = FALSE)
country <- toupper(opt$country)
start_period <- as_period(opt$start_period, FREQ)
dir.create(opt$output_dir, showWarnings = FALSE, recursive = TRUE)
country2 <- if (!is.null(opt$fred_country2)) opt$fred_country2 else lookup_country2(country)

monthly_concepts <- dplyr::filter(concept_dictionary, .data$available_monthly)
canonical_cols <- monthly_concepts$label
message("Building a monthly panel for ", country, " from ", start_period,
        " -- ", length(canonical_cols), " of ", nrow(concept_dictionary),
        " concepts are published monthly.")

panel <- tibble::tibble(date = as.Date(character(0)))
concept_source <- list()

join_concept <- function(df, label, provider, key) {
  if (is.null(df) || !label %in% names(df)) return(invisible(NULL))
  panel <<- dplyr::full_join(panel, df[, c("date", label)], by = "date")
  concept_source[[label]] <<- list(provider = provider, key = key)
  invisible(NULL)
}

## A fresh series arriving where a frozen mirror already sits. What to do
## with the mirror's earlier history depends on what the two series are,
## and getting this wrong is silent -- every combination below produces a
## column of plausible-looking numbers.
##
##   "splice"  both measure the same thing on different index bases, so
##             the mirror's history is rescaled to the fresh series' level
##             at the overlap. Verified before being used: over their
##             overlap the two retail series correlate 0.998 in log
##             differences and the two industrial production series 0.896,
##             at base ratios of 0.94 and 0.82.
##   "prefer"  both are already in the same units -- a rate in percent --
##             so the mirror fills gaps as it stands and is NOT rescaled.
##             Rescaling an unemployment rate to match another unemployment
##             rate would bend it for no reason. (For Austria the two are
##             in fact the same series to the last decimal: FRED's mirror
##             of the harmonised rate and Eurostat's une_rt_m agree over
##             all 379 overlapping months.)
##   "replace" the two are DIFFERENT STATISTICS and no arithmetic joins
##             them. Consumer confidence is the case: the EC survey
##             publishes a balance that sits near -15, the OECD MEI mirror
##             an index that sits near 100. Splicing them produced a
##             column that stepped from 99.7 to -13.3 between two adjacent
##             months, which no plausibility check would catch because
##             both numbers are unremarkable for a "balance" concept.
##             The mirror is dropped where the survey exists.
combine_in <- function(fresh, label, provider, key, mode = "splice") {
  if (is.null(fresh) || !label %in% names(fresh)) return(invisible(NULL))
  old <- if (label %in% names(panel)) panel[, c("date", label)] else NULL
  fresh <- fresh[, c("date", label)]

  combined <- if (identical(mode, "replace") || is.null(old)) {
    fresh
  } else if (identical(mode, "prefer")) {
    merged <- dplyr::full_join(fresh, old, by = "date", suffix = c("", ".old"))
    merged[[label]] <- dplyr::coalesce(merged[[label]], merged[[paste0(label, ".old")]])
    merged[, c("date", label)]
  } else {
    splice_prefer(fresh, old, by = "date")
  }

  panel <<- panel %>%
    dplyr::select(-dplyr::any_of(label)) %>%
    dplyr::full_join(combined, by = "date")
  concept_source[[label]] <<- list(
    provider = provider,
    key = paste0(key, if (is.null(old)) "" else switch(mode,
      splice = " (OECD MEI mirror's earlier history spliced on, rescaled to this base)",
      prefer = " (OECD MEI mirror fills earlier months unchanged, same units)",
      replace = " (OECD MEI mirror dropped: it measures a different statistic)"))
  )
  invisible(NULL)
}

## =====================================================================
## 1. FRED's OECD MEI mirrors, monthly
##
##    The base layer: ten concepts, several with history back to the
##    1950s. Four of the ten are frozen mirrors (see R/eurostat_monthly.R)
##    and are spliced onto a current Eurostat or EC source below rather
##    than replaced outright, so the long history survives.
## =====================================================================
message("Fetching the monthly OECD MEI / FRED mirrors for ", country2, "...")
mirror_keys <- other_groups %>%
  dplyr::filter(!is.na(.data$m_id_template)) %>%
  dplyr::mutate(id = stringr::str_replace_all(
    .data$m_id_template, c("\\{cc2\\}" = country2, "\\{cc3\\}" = country)))
mirrors <- fetch_other_groups(country2, country, frequency = FREQ)
for (lbl in names(mirrors)) {
  join_concept(mirrors[[lbl]], lbl, "FRED_MIRROR",
               mirror_keys$id[match(lbl, mirror_keys$label)])
}

## =====================================================================
## 2. Eurostat short-term statistics, current where the mirrors above
##    are frozen. Spliced, not substituted: Eurostat's industrial
##    production starts in 1996 and the mirror's in 1955, and the two
##    sit on different index bases.
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- fetching Eurostat monthly short-term statistics...")
  sts <- list(
    industrial_production = fetch_eurostat_industrial_production(country, start_period = start_period),
    retail_sales_volume   = fetch_eurostat_retail_sales(country, start_period = start_period),
    unemployment_rate     = fetch_eurostat_unemployment(country, start_period = start_period)
  )
  for (lbl in names(sts)) {
    if (is.null(sts[[lbl]])) {
      message("  ", lbl, ": Eurostat unavailable this run -- keeping the FRED-mirror series, if any.")
      next
    }
    combine_in(sts[[lbl]], lbl, "EUROSTAT_STS", attr(sts[[lbl]], "source_col"),
               mode = if (lbl == "unemployment_rate") "prefer" else "splice")
  }
}

## =====================================================================
## 3. Eurostat HICP: the headline index and its four sub-categories.
##    Monthly is the HICP's own frequency -- the quarterly panel is the
##    one doing the aggregating.
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- fetching monthly Eurostat HICP...")
  hicp_wanted <- dplyr::bind_rows(
    tibble::tibble(label = "cpi_index", coicop = eurostat_hicp_coicop),
    eurostat_hicp_subcategories
  )
  for (i in seq_len(nrow(hicp_wanted))) {
    lbl <- hicp_wanted$label[i]
    coicop <- hicp_wanted$coicop[i]
    got <- fetch_eurostat_hicp(country, label = lbl, start_period = start_period,
                               coicop = coicop, frequency = FREQ)
    combine_in(got, lbl, "EUROSTAT_HICP",
               sprintf("prc_hicp_midx:M.%s.%s.%s", eurostat_hicp_unit, coicop,
                       lookup_ec_country2(country)), mode = "replace")
  }
}

## =====================================================================
## 3b. A national CPI index where the HICP does not reach
##
##     The OECD MEI mirror cannot serve here: its only CPI series are
##     growth rates (see R/fred_mirror.R). So a country outside the EU
##     gets its own national index if this project has verified one, and
##     an honest NA otherwise.
## =====================================================================
if (!"cpi_index" %in% names(concept_source)) {
  national <- fetch_national_cpi_index(country, start_period = start_period,
                                       frequency = FREQ)
  if (!is.null(national)) {
    message("No Eurostat HICP for ", country, " -- using its national CPI index.")
    join_concept(national, "cpi_index", "FRED", attr(national, "source_col"))
  }
}

## =====================================================================
## 4. European Commission Business and Consumer Survey -- seven headline
##    concepts, monthly at source and published within the month they
##    refer to, which makes them the timeliest thing in this panel.
## =====================================================================
if (country %in% eu_member_countries) {
  message("Country is an EU member -- fetching the EC Business and Consumer Survey...")
  combine_in(fetch_ec_consumer_confidence(country, start_period = start_period, frequency = FREQ),
             "consumer_confidence", "EC_BCS", paste0(lookup_ec_country2(country), ".CONS"),
             mode = "replace")
  for (i in seq_len(nrow(ec_survey_indicators))) {
    lbl <- ec_survey_indicators$label[i]
    indicator <- ec_survey_indicators$indicator[i]
    join_concept(fetch_ec_survey_indicator(country, label = lbl, indicator = indicator,
                                           start_period = start_period, frequency = FREQ),
                 lbl, "EC_BCS", paste0(lookup_ec_country2(country), ".", indicator))
  }
  join_concept(fetch_ec_construction_weather_constraint(country, start_period = start_period,
                                                        frequency = FREQ),
               "construction_weather_constraint", "EC_BCS",
               paste0(lookup_ec_country2(country), ".BUIL weather factor"))
  ## The consumer survey's monthly questions; the two quarterly ones
  ## (home purchase and improvement intentions) are quarterly-only
  ## concepts and not in this panel.
  monthly_questions <- ec_consumer_questions[ec_consumer_questions$frequency == "M", ]
  for (i in seq_len(nrow(monthly_questions))) {
    lbl <- monthly_questions$label[i]
    question <- monthly_questions$question[i]
    join_concept(fetch_ec_consumer_question(country, label = lbl, question = question,
                                            start_period = start_period, frequency = FREQ),
                 lbl, "EC_BCS", ec_consumer_question_column(lookup_ec_country2(country), question))
  }
}

## =====================================================================
## 5. ECB: two monthly series and one daily one. The CISS is averaged
##    within the month exactly as the quarterly panel averages it within
##    the quarter.
## =====================================================================
message("Fetching the monthly ECB series...")
join_concept(fetch_ecb_mortgage_rate(country, start_period = start_period, frequency = FREQ),
             "mortgage_rate", "ECB_MIR", "MIR")
join_concept(fetch_ecb_household_mortgage_loans(country, start_period = start_period,
                                                frequency = FREQ),
             "household_mortgage_loans", "ECB_BSI", "BSI")
join_concept(fetch_ecb_ciss(country, start_period = start_period, frequency = FREQ),
             "financial_stress", "ECB_CISS", "CISS (daily, averaged within the month)")

## =====================================================================
## 6. The three unconditional concepts -- identical in every country's
##    panel, as in the quarterly builder.
## =====================================================================
message("Fetching geopolitical risk, the world oil price and global activity...")
gpr <- fetch_geopolitical_risk(country, start_period = start_period, frequency = FREQ)
join_concept(gpr, "geopolitical_risk", "GPR", attr(gpr, "source_col") %||% "GPR")
oil <- fetch_oil_price(country, start_period = start_period, frequency = FREQ)
join_concept(oil, "oil_price", "FRED", attr(oil, "source_col") %||% oil_price_fred_id)
act <- fetch_global_activity(country, start_period = start_period, frequency = FREQ)
join_concept(act, "global_activity", "FRED", attr(act, "source_col") %||% global_activity_fred_id)

## =====================================================================
## 7. Canonical schema, and a panel sorted by date
##
##    Same contract as the quarterly panel: every country's monthly file
##    has the same columns in the same order, whether or not each one
##    resolved, so that changing --country returns a like-for-like file.
##    The sort matters for the same reason it does there -- a full_join
##    appends periods the left side lacks, and a concept reaching
##    further back than the panel leaves the rows out of order.
## =====================================================================
for (col in setdiff(canonical_cols, names(panel))) panel[[col]] <- NA_real_
panel <- panel %>%
  dplyr::select("date", dplyr::all_of(canonical_cols)) %>%
  dplyr::arrange(.data$date) %>%
  dplyr::filter(.data$date >= period_to_date(start_period))

## A month in which nothing at all was observed is not a month of the
## panel. Without this the file would begin wherever the longest series
## begins and carry rows of nothing but NA wherever none overlap.
observed <- rowSums(!is.na(panel[, canonical_cols, drop = FALSE])) > 0
panel <- panel[observed, ]

## =====================================================================
## 8. Output, coverage and plausibility
## =====================================================================
csv_path <- file.path(opt$output_dir, paste0(tolower(country), "_monthly_panel.csv"))
readr::write_csv(panel, csv_path)
n_resolved <- sum(canonical_cols %in% names(concept_source))
message("Saved ", nrow(panel), " months x ", length(canonical_cols),
        " canonical concepts (", n_resolved, " resolved, ",
        length(canonical_cols) - n_resolved, " NA) to '", csv_path, "'")

provider_display_names <- c(
  FRED_MIRROR = "OECD MEI (via FRED mirror), monthly",
  EUROSTAT_STS = "Eurostat short-term statistics (sts_inpr_m / sts_trtu_m / une_rt_m)",
  EUROSTAT_HICP = "Eurostat (prc_hicp_midx, HICP), monthly",
  EC_BCS = "European Commission Business and Consumer Survey",
  ECB_MIR = "ECB MFI Interest Rate Statistics (MIR)",
  ECB_BSI = "ECB MFI Balance Sheet Items (BSI)",
  ECB_CISS = "ECB Composite Indicator of Systemic Stress (CISS)",
  GPR = "Geopolitical Risk Index (Caldara-Iacoviello)",
  FRED = "FRED (series published by FRED itself, not an OECD/BIS mirror)"
)
format_source <- function(src) {
  if (is.null(src)) return(NA_character_)
  sprintf("%s [%s]", provider_display_names[[src$provider]] %||% src$provider, src$key)
}
coverage_rows <- monthly_concepts %>%
  dplyr::transmute(
    fred_qd_group,
    label,
    resolved = .data$label %in% names(concept_source),
    source = purrr::map_chr(.data$label, ~ format_source(concept_source[[.x]]))
  )

## The same checks the quarterly panel runs. Their one frequency-sensitive
## rule is the "level" category's jump check, which flags a period-on-
## period change above 90%: month-on-month changes are smaller than
## quarter-on-quarter ones, so the check is if anything more lenient here,
## and it still catches what it is for -- a units error, or a series that
## came back on a different base than the one it is spliced onto.
plausibility_results <- run_plausibility_checks(panel, canonical_cols)
plausibility_counts <- table(vapply(plausibility_results, function(x) x$status, character(1)))
message("Plausibility checks: ", sum(plausibility_counts[c("PASS")], na.rm = TRUE), " PASS, ",
        sum(plausibility_counts[c("FLAG")], na.rm = TRUE), " FLAG, ",
        sum(plausibility_counts[c("NO_DATA", "TOO_SHORT")], na.rm = TRUE), " NO_DATA/TOO_SHORT")
for (f in Filter(function(x) x$status == "FLAG", plausibility_results)) {
  message("  FLAG [", f$label, "]: ", f$detail)
}

coverage <- list(
  country = country,
  frequency = "monthly",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  start_period = start_period,
  concepts_published_monthly = length(canonical_cols),
  concepts_quarterly_only = nrow(concept_dictionary) - length(canonical_cols),
  resolved = coverage_rows %>% dplyr::filter(.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label, source) %>% purrr::transpose(),
  skipped = coverage_rows %>% dplyr::filter(!.data$resolved) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  quarterly_only = concept_dictionary %>% dplyr::filter(!.data$available_monthly) %>%
    dplyr::transmute(fred_qd_group, label) %>% purrr::transpose(),
  plausibility_checks = plausibility_results
)
coverage_path <- file.path(opt$output_dir, paste0(tolower(country), "_monthly_coverage.json"))
jsonlite::write_json(coverage, coverage_path, auto_unbox = TRUE, pretty = TRUE)
message("Saved coverage report to '", coverage_path, "'")

## =====================================================================
## 9. The monthly data-sources registry
##
##    Kept apart from docs/data_sources.csv rather than merged into it
##    with a frequency column, because the same concept label often
##    resolves to a DIFFERENT source at the two frequencies, and one
##    table keyed on country and variable cannot hold both without
##    either colliding or growing a key every existing reader would have
##    to learn.
## =====================================================================
registry_path <- file.path(project_root, "docs", "data_sources_monthly.csv")
rows <- coverage_rows %>%
  dplyr::filter(.data$resolved) %>%
  dplyr::transmute(
    country = !!country,
    variable = .data$label,
    provider = purrr::map_chr(.data$label, ~ concept_source[[.x]]$provider),
    key = purrr::map_chr(.data$label, ~ concept_source[[.x]]$key)
  )
existing <- if (file.exists(registry_path)) {
  readr::read_csv(registry_path, show_col_types = FALSE) %>%
    dplyr::filter(.data$country != !!country)
} else {
  rows[0, ]
}
readr::write_csv(dplyr::arrange(dplyr::bind_rows(existing, rows), .data$country, .data$variable),
                 registry_path)
message("Updated the monthly data-sources registry: '", registry_path, "'")
