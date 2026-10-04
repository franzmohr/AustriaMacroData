## ---------------------------------------------------------------
## panel_monthly.R -- every concept that is MONTHLY at source, fetched
## once, at its own frequency
##
## The fetching half of what was scripts/build_monthly_panel.R, moved
## here unchanged so that scripts/build_panels.R can build all three
## panels from one fetch: the monthly panel is this; the quarterly panel
## takes these concepts' quarters from it (R/panel_derive.R) rather than
## fetching them again from a quarterly source; the mixed-frequency panel
## holds them as they are. Before that split the two builders fetched
## every concept separately and their panels "shared labels, not series"
## -- industrial production came from sts_inpr_q in one and sts_inpr_m in
## the other, the share price index from the ATX in one and an OECD
## mirror in the other.
##
## Two concepts are monthly here for the first time: the ATX (Yahoo
## Finance publishes monthly closes; the quarterly builder averaged them)
## and the heating and cooling degree days (Eurostat's nrg_chdd_m and the
## ERA5 series are both monthly; the quarterly builder totalled them).
## ---------------------------------------------------------------

#' Fetch every monthly-at-source concept for one country
#'
#' Returns `list(panel = <tibble: date + one column per resolved concept>,
#' concept_source = <named list of list(provider =, key =)>)`. Concepts
#' that do not resolve are simply absent; the caller imposes the
#' canonical schema.
fetch_monthly_concepts <- function(country, start_period, country2 = lookup_country2(country)) {
  freq <- "M"
  start_period <- as_period(start_period, freq)
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

  ## ===================================================================
  ## 1. FRED's OECD MEI mirrors, monthly
  ##
  ##    The base layer: ten concepts, several with history back to the
  ##    1950s. Four of the ten are frozen mirrors and are spliced onto a
  ##    current Eurostat or EC source below rather than replaced outright,
  ##    so the long history survives.
  ## ===================================================================
  if (!is.na(country2)) {
    message("Fetching the monthly OECD MEI / FRED mirrors for ", country2, "...")
    mirror_keys <- other_groups %>%
      dplyr::filter(!is.na(.data$m_id_template)) %>%
      dplyr::mutate(id = stringr::str_replace_all(
        .data$m_id_template, c("\\{cc2\\}" = country2, "\\{cc3\\}" = country)))
    mirrors <- fetch_other_groups(country2, country, frequency = freq)
    for (lbl in names(mirrors)) {
      join_concept(mirrors[[lbl]], lbl, "FRED_MIRROR",
                   mirror_keys$id[match(lbl, mirror_keys$label)])
    }
  } else {
    message("Skipping FRED-mirror concepts: no FRED 2-letter code known for ", country, " (pass --fred-country2)")
  }

  ## ===================================================================
  ## 2. Eurostat short-term statistics, current where the mirrors above
  ##    are frozen. Spliced, not substituted: Eurostat's industrial
  ##    production starts in 1996 and the mirror's in 1955, and the two
  ##    sit on different index bases.
  ## ===================================================================
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

  ## ===================================================================
  ## 2b. Market interest rates from the ECB for euro-area members, current
  ##     within days of a month's end where the mirror runs a month behind.
  ##     Same units, so the mirror fills the earlier months unchanged
  ##     ("prefer") -- see R/ecb_market_rates.R.
  ## ===================================================================
  if (country %in% names(euro_adoption)) {
    message("Country is a euro-area member -- fetching Euribor and the 10-year yield from the ECB...")
    rates <- list(short_term_rate = list(fetch_ecb_short_term_rate(country, start_period = start_period, frequency = freq), "ECB_FM"),
                  long_term_rate  = list(fetch_ecb_long_term_rate(country, start_period = start_period, frequency = freq), "ECB_IRS"))
    for (lbl in names(rates)) {
      got <- rates[[lbl]][[1]]
      if (is.null(got)) {
        message("  ", lbl, ": ECB unavailable this run -- keeping the FRED-mirror series, if any.")
        next
      }
      combine_in(got, lbl, rates[[lbl]][[2]], attr(got, "key"), mode = "prefer")
    }
  }

  ## ===================================================================
  ## 3. Eurostat HICP: the headline index and its four sub-categories.
  ## ===================================================================
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
                                 coicop = coicop, frequency = freq)
      combine_in(got, lbl, "EUROSTAT_HICP",
                 sprintf("%s:M.%s.%s.%s", eurostat_hicp_dataflow, eurostat_hicp_unit, coicop,
                         lookup_ec_country2(country)), mode = "replace")
    }
  }

  ## ===================================================================
  ## 3b. A national CPI index where the HICP does not reach
  ##
  ##     The OECD MEI mirror cannot serve here: its only CPI series are
  ##     growth rates (see R/fred_mirror.R). So a country outside the EU
  ##     gets its own national index if this project has verified one, and
  ##     an honest NA otherwise.
  ## ===================================================================
  if (!"cpi_index" %in% names(concept_source)) {
    national <- fetch_national_cpi_index(country, start_period = start_period,
                                         frequency = freq)
    if (!is.null(national)) {
      message("No Eurostat HICP for ", country, " -- using its national CPI index.")
      join_concept(national, "cpi_index", "FRED", attr(national, "source_col"))
    }
  }

  ## ===================================================================
  ## 4. European Commission Business and Consumer Survey -- monthly at
  ##    source and published within the month they refer to, which makes
  ##    them the timeliest thing in this panel. The questions asked only
  ##    quarterly are quarterly concepts (R/panel_quarterly.R).
  ## ===================================================================
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- fetching the EC Business and Consumer Survey...")
    combine_in(fetch_ec_consumer_confidence(country, start_period = start_period, frequency = freq),
               "consumer_confidence", "EC_BCS", paste0(lookup_ec_country2(country), ".CONS"),
               mode = "replace")
    for (i in seq_len(nrow(ec_survey_indicators))) {
      lbl <- ec_survey_indicators$label[i]
      indicator <- ec_survey_indicators$indicator[i]
      join_concept(fetch_ec_survey_indicator(country, label = lbl, indicator = indicator,
                                             start_period = start_period, frequency = freq),
                   lbl, "EC_BCS", paste0(lookup_ec_country2(country), ".", indicator))
    }
    join_concept(fetch_ec_construction_weather_constraint(country, start_period = start_period,
                                                          frequency = freq),
                 "construction_weather_constraint", "EC_BCS",
                 ec_building_factor_column(lookup_ec_country2(country)))
    monthly_questions <- ec_consumer_questions[ec_consumer_questions$frequency == "M", ]
    for (i in seq_len(nrow(monthly_questions))) {
      lbl <- monthly_questions$label[i]
      question <- monthly_questions$question[i]
      join_concept(fetch_ec_consumer_question(country, label = lbl, question = question,
                                              start_period = start_period, frequency = freq),
                   lbl, "EC_BCS", ec_consumer_question_column(lookup_ec_country2(country), question))
    }
    monthly_business <- ec_business_questions$label[ec_business_questions$frequency == "M"]
    for (lbl in monthly_business) {
      join_concept(fetch_ec_business_question(country, label = lbl, start_period = start_period,
                                              frequency = freq),
                   lbl, "EC_BCS", ec_business_question_key(lbl, lookup_ec_country2(country)))
    }
  }

  ## ===================================================================
  ## 5. ECB: four monthly series and one daily one. The CISS is averaged
  ##    within the month.
  ## ===================================================================
  message("Fetching the monthly ECB series...")
  join_concept(fetch_ecb_mortgage_rate(country, start_period = start_period, frequency = freq),
               "mortgage_rate", "ECB_MIR", "A2C.R.A.2250.EUR.N")
  join_concept(fetch_ecb_household_mortgage_loans(country, start_period = start_period,
                                                  frequency = freq),
               "household_mortgage_loans", "ECB_BSI", "A22T.A.1.U6.2250.Z01.E")
  join_concept(fetch_ecb_mortgage_rate_pure_new(country, start_period = start_period,
                                                frequency = freq),
               "mortgage_rate_pure_new_loans", "ECB_MIR", "A2C.R.A.2250.EUR.P")
  join_concept(fetch_ecb_mortgage_new_lending(country, start_period = start_period, frequency = freq),
               "mortgage_new_lending", "ECB_MIR", "A2C.B.A.2250.EUR.P")
  ciss <- fetch_ecb_ciss(country, start_period = start_period, frequency = freq)
  join_concept(ciss, "financial_stress", "ECB_CISS",
               paste0(attr(ciss, "key") %||% "CISS", " (daily, averaged within the month)"))

  ## ===================================================================
  ## 6. Austria: the ATX in place of the OECD "all shares" mirror, as the
  ##    quarterly builder has always done. Monthly closes at source. And
  ##    the OeNB's new lending for housing and its rate (R/oenb.R), which
  ##    reach back further than the ECB's MIR series.
  ## ===================================================================
  if (country == "AUT") {
    message("Country is Austria -- trying the ATX index (Yahoo Finance) for share_price_index...")
    combine_in(fetch_atx_monthly(start_period = start_period), "share_price_index",
               "YAHOO_FINANCE", "^ATX (monthly close)", mode = "replace")
    message("Country is Austria -- fetching new lending for housing and its rate from the OeNB...")
    for (lbl in oenb_series$label) {
      join_concept(fetch_oenb_series(country, lbl, start_period = start_period, frequency = freq),
                   lbl, "OENB", oenb_key(lbl))
    }
  }

  ## ===================================================================
  ## 7. Heating and cooling degree days, monthly -- see R/weather.R for
  ##    the Eurostat/ERA5 splice and its calibration.
  ## ===================================================================
  message("Fetching heating/cooling degree days for ", country, "...")
  degree_days <- fetch_degree_days(country, start_period = start_period, frequency = freq)
  if (!is.null(degree_days)) {
    dd_sources <- attr(degree_days, "sources")
    for (lbl in names(dd_sources)) {
      join_concept(degree_days, lbl, dd_sources[[lbl]]$provider, dd_sources[[lbl]]$key)
      message("  ", lbl, ": ", dd_sources[[lbl]]$key)
    }
  }

  ## ===================================================================
  ## 8. The three unconditional concepts -- identical in every country's
  ##    panel.
  ## ===================================================================
  message("Fetching geopolitical risk, the world oil price and global activity...")
  gpr <- fetch_geopolitical_risk(country, start_period = start_period, frequency = freq)
  join_concept(gpr, "geopolitical_risk", "GPR", attr(gpr, "source_col") %||% "GPR")
  oil <- fetch_oil_price(country, start_period = start_period, frequency = freq)
  join_concept(oil, "oil_price", "FRED", attr(oil, "source_col") %||% oil_price_fred_id)
  act <- fetch_global_activity(country, start_period = start_period, frequency = freq)
  join_concept(act, "global_activity", "FRED", attr(act, "source_col") %||% global_activity_fred_id)

  list(panel = dplyr::arrange(panel, .data$date), concept_source = concept_source)
}
