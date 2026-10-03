## ---------------------------------------------------------------
## panel_quarterly.R -- every concept that is QUARTERLY at source
##
## The fetching half of what was scripts/build_country_panel.R, restricted
## to the concepts no monthly source exists for: the national accounts,
## BIS credit, government finance, household net worth, the quarterly-only
## OECD MEI/BIS mirrors, unit labour cost, hours, population, the change
## in inventories and the EC survey questions that are asked only once a
## quarter. Everything monthly at source is fetched once by
## R/panel_monthly.R, and the quarterly panel takes its quarters from
## there (R/panel_derive.R).
##
## The code of each section is the quarterly builder's own, with its
## history comments; only the monthly-at-source sections have left.
## ---------------------------------------------------------------

#' Fetch every quarterly-at-source concept for one country
#'
#' Returns `list(panel = <tibble: date + one column per resolved concept>,
#' concept_source = <named list of list(provider =, key =)>, anchors =
#' <the national-accounts tibble keyed by `period`, for --validate>)`.
fetch_quarterly_native_concepts <- function(country, start_period, country2 = lookup_country2(country)) {
  start_period <- as_period(start_period, "Q")
  concept_source <- list()
  quarterly_labels <- concept_dictionary$label[concept_dictionary$frequency == "Q"]

  join_concept <- function(df, label, provider, key) {
    if (is.null(df) || !label %in% names(df)) return(invisible(NULL))
    panel <<- dplyr::full_join(panel, df[, c("date", label)], by = "date")
    concept_source[[label]] <<- list(provider = provider, key = key)
    invisible(NULL)
  }

  ## ===================================================================
  ## 1. Anchor NIPA concepts: Eurostat preferred for EU members, EXTENDED
  ##    with OECD QNA's longer history (level-spliced, see splice_prefer()
  ##    in R/utils.R for the ~4x discontinuity a plain merge introduced),
  ##    then IMF QNEA fallback for whatever neither has any data for
  ## ===================================================================
  all_anchor_labels <- c(oecd_anchor_concepts$label, "real_household_disposable_income")

  eurostat_result <- NULL
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- trying Eurostat for anchor NIPA concepts...")
    eurostat_result <- fetch_eurostat_anchors(country, start_period = start_period)
  }

  message("Fetching anchor NIPA concepts for ", country, " from OECD QNA...")
  oecd_result <- fetch_oecd_anchors(country, start_period = start_period)

  anchor_merged <- splice_prefer(eurostat_result, oecd_result)

  oecd_anchor_key <- function(label) {
    row <- oecd_anchor_concepts[oecd_anchor_concepts$label == label, ]
    if (nrow(row) == 1) return(paste0(row$sector, ".", row$transaction))
    paste0(oecd_disposable_income_dims$sector, ".", oecd_disposable_income_dims$transaction, " (DF_QNA_INC_SAV)")
  }

  for (lbl in all_anchor_labels) {
    from_eurostat <- has_data(eurostat_result, lbl)
    from_oecd <- has_data(oecd_result, lbl)
    if (from_eurostat && from_oecd) {
      na_item <- eurostat_anchor_concepts$na_item[eurostat_anchor_concepts$label == lbl]
      concept_source[[lbl]] <- list(
        provider = "EUROSTAT",
        key = sprintf("namq_10_gdp:%s (extended pre-1995 with level-spliced OECD_QNA:%s)", na_item, oecd_anchor_key(lbl))
      )
    } else if (from_eurostat) {
      na_item <- eurostat_anchor_concepts$na_item[eurostat_anchor_concepts$label == lbl]
      concept_source[[lbl]] <- list(provider = "EUROSTAT", key = paste0("namq_10_gdp:", na_item))
    } else if (from_oecd) {
      concept_source[[lbl]] <- list(provider = "OECD_QNA", key = oecd_anchor_key(lbl))
    }
  }

  missing_anchors <- setdiff(all_anchor_labels, names(concept_source))
  if (length(missing_anchors) > 0) {
    message("OECD/Eurostat had no data for: ", paste(missing_anchors, collapse = ", "), " -- trying IMF QNEA fallback...")
    imf_fallback <- fetch_imf_fallbacks(country, missing_anchors, start_period = start_period)
    for (lbl in names(imf_fallback)) {
      anchor_merged <- if (is.null(anchor_merged)) imf_fallback[[lbl]] else dplyr::full_join(anchor_merged, imf_fallback[[lbl]], by = "period")
      imf_indicator <- imf_indicator_map$imf_indicator[imf_indicator_map$label == lbl]
      concept_source[[lbl]] <- list(provider = "IMF_QNEA", key = imf_indicator)
    }
  }

  if (is.null(anchor_merged)) stop("No anchor series resolved from Eurostat, OECD or IMF -- check the country code.", call. = FALSE)
  anchor_merged <- dplyr::arrange(anchor_merged, .data$period)

  panel <- anchor_merged %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-"period")

  ## ===================================================================
  ## 2. BIS credit -- private non-financial sector, households,
  ##    nonfinancial corporations, and general government (same dataflow,
  ##    four TC_BORROWERS codes; general government at NOMINAL value since
  ##    2026-09-14, see R/bis.R)
  ## ===================================================================
  bis_credit_concepts <- tibble::tribble(
    ~label,                             ~tc_borrowers, ~valuation,
    "credit_to_private_nonfin_sector",  "P",           "M",
    "household_credit_to_gdp",          "H",           "M",
    "corporate_credit_to_gdp",          "N",           "M",
    "government_debt_to_gdp",           "G",           "N"
  )
  if (!is.na(country2)) {
    message("Fetching Money and Credit from BIS for ", country2, "...")
    for (i in seq_len(nrow(bis_credit_concepts))) {
      lbl <- bis_credit_concepts$label[i]
      tcb <- bis_credit_concepts$tc_borrowers[i]
      val <- bis_credit_concepts$valuation[i]
      credit <- fetch_bis_credit(country2, tc_borrowers = tcb, label = lbl,
                                 start_period = start_period, valuation = val)
      if (!is.null(credit)) {
        credit <- credit %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-"period")
        join_concept(credit, lbl, "BIS_WSTC", sprintf("Q.%s.%s.A.%s.770.A", country2, tcb, val))
      }
    }
  } else {
    message("Skipping BIS credit: no FRED 2-letter code known for ", country, " (pass --fred-country2)")
  }

  ## ===================================================================
  ## 3. EU-specific: general-government primary balance (Eurostat
  ##    gov_10q_ggnfa), and the euro-area household net worth (ECB QSA)
  ## ===================================================================
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- fetching the government primary balance from Eurostat...")
    join_concept(fetch_eurostat_primary_balance(country, start_period = start_period),
                 "government_primary_balance_to_gdp", "EUROSTAT_GOV",
                 sprintf("%s:Q.PC_GDP.NSA.S13.B9+D41PAY.%s", eurostat_gov_dataflow, lookup_ec_country2(country)))
  }

  networth <- fetch_ecb_household_networth(country, start_period = start_period)
  if (!is.null(networth)) {
    networth <- networth %>% dplyr::mutate(date = period_to_date(.data$period)) %>% dplyr::select(-"period")
    join_concept(networth, "euro_area_household_net_worth_growth", "ECB_QSA_PUB", "I8")
  }

  ## ===================================================================
  ## 4. The OECD MEI / BIS / WUI mirrors that are quarterly at source --
  ##    employment rate, unit labour cost, real house prices, the World
  ##    Uncertainty Index. The rest of the mirror table is monthly and
  ##    comes from R/panel_monthly.R.
  ## ===================================================================
  if (!is.na(country2)) {
    message("Fetching the quarterly-only FRED/OECD-MEI/BIS mirrors for ", country2, "...")
    other <- fetch_other_groups(country2, country, labels = quarterly_labels)
    for (lbl in names(other)) {
      id_template <- other_groups$id_template[other_groups$label == lbl]
      resolved_mnemonic <- stringr::str_replace(id_template, stringr::fixed("{cc2}"), country2)
      resolved_mnemonic <- stringr::str_replace(resolved_mnemonic, stringr::fixed("{cc3}"), country)
      join_concept(other[[lbl]], lbl, "FRED_MIRROR", resolved_mnemonic)
    }
  } else {
    message("Skipping FRED-mirror groups: no FRED 2-letter code known for ", country, " (pass --fred-country2)")
  }

  ## ===================================================================
  ## 4f. EU-specific override: unit labor cost from Eurostat's labour
  ##     productivity and unit-labour-cost dataflow, where it publishes an
  ##     index-level series (a closer match to FRED-QD's ULCNFB than the
  ##     employment-based OECD-mirror proxy above) -- see R/eurostat.R
  ## ===================================================================
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- trying Eurostat labour productivity/ULC for unit_labor_cost...")
    ulc <- fetch_eurostat_ulc(country, start_period = start_period)
    if (!is.null(ulc)) {
      panel <- dplyr::select(panel, -dplyr::any_of("unit_labor_cost"))
      join_concept(ulc, "unit_labor_cost", "EUROSTAT_ULC",
                   sprintf("namq_10_lp_ulc:Q.%s.SCA.%s.%s", eurostat_ulc_unit, eurostat_ulc_na_item,
                           lookup_ec_country2(country)))
    } else {
      message("Eurostat ULC unavailable for ", country, " this run -- keeping the FRED-mirror unit_labor_cost value, if any.")
    }
  }

  ## ===================================================================
  ## 4i. EU-specific: the EC survey questions asked only once a quarter --
  ##     the consumer survey's home purchase and improvement intentions,
  ##     and the business surveys' limiting factors, capacity and
  ##     competitiveness questions (see R/ec_survey.R)
  ## ===================================================================
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- fetching the quarterly EC survey questions...")
    quarterly_consumer <- ec_consumer_questions[ec_consumer_questions$frequency == "Q", ]
    for (i in seq_len(nrow(quarterly_consumer))) {
      lbl <- quarterly_consumer$label[i]
      question <- quarterly_consumer$question[i]
      join_concept(fetch_ec_consumer_question(country, label = lbl, question = question,
                                              start_period = start_period),
                   lbl, "EC_BCS",
                   ec_consumer_question_column(lookup_ec_country2(country), question, "Q"))
    }
    for (lbl in ec_business_questions$label[ec_business_questions$frequency == "Q"]) {
      join_concept(fetch_ec_business_question(country, label = lbl, start_period = start_period),
                   lbl, "EC_BCS", ec_business_question_key(lbl, lookup_ec_country2(country)))
    }
  }

  ## ===================================================================
  ## 4k. Hours (EU only), the change in inventories and population --
  ##     see R/eurostat.R, R/inventories.R and R/population.R
  ## ===================================================================
  if (country %in% eu_member_countries) {
    message("Country is an EU member -- fetching Eurostat total hours worked...")
    hours <- fetch_eurostat_hours(country, start_period = start_period)
    if (is.null(hours)) message("Eurostat hours unavailable for ", country, " this run -- hours_worked stays NA.")
    join_concept(hours, "hours_worked", "EUROSTAT_NA", attr(hours, "source_col"))
  }

  message("Fetching the change in inventories (% of GDP) for ", country, "...")
  inventories <- fetch_inventory_change(country, start_period = start_period)
  if (is.null(inventories)) message("No inventory-change source for ", country, " -- inventory_change_to_gdp stays NA.")
  join_concept(inventories, "inventory_change_to_gdp", attr(inventories, "provider"),
               attr(inventories, "source_col"))

  message("Fetching total population for ", country, "...")
  population <- fetch_population(country, start_period = start_period)
  if (is.null(population)) {
    message("No quarterly population source for ", country,
            " -- population stays NA (see R/population.R for why it is not interpolated from annual data).")
  }
  join_concept(population, "population", attr(population, "provider"), attr(population, "source_col"))

  ## Only what is quarterly at source belongs here; anything else a
  ## fetcher returned alongside is dropped rather than left to collide
  ## with the monthly-derived column of the same name.
  keep <- intersect(names(panel), c("date", quarterly_labels))
  list(panel = dplyr::arrange(panel[, keep], .data$date),
       concept_source = concept_source[intersect(names(concept_source), quarterly_labels)],
       anchors = anchor_merged)
}
