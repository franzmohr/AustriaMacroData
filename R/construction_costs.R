## ---------------------------------------------------------------
## construction_costs.R -- construction costs and construction prices
## for new residential buildings
##
## Two concepts, both monthly where the source publishes them monthly:
##
##   construction_cost_index       what it costs a builder to put up a
##                                 new residential building (materials
##                                 and labour), Eurostat indic_bt COST
##   construction_producer_prices  what the builder charges for it,
##                                 Eurostat indic_bt PRC_PRR
##
## EU members: Eurostat's short-term statistics, sts_copi_m (monthly) and
## sts_copi_q (quarterly), residential buildings except residences for
## communities (CPA_F41001_X_410014), index 2021 = 100, not seasonally
## adjusted -- NSA is the only adjustment published. Key order, confirmed
## live 2026-10-04: freq.indic_bt.cpa2_1.s_adj.unit.geo. Coverage then:
##
##   Austria  monthly, both indicators, 1990-01 to 2026-08
##   Germany  quarterly ONLY: costs from 2000-Q1, prices from 1970-Q1,
##            both to 2026-Q2; sts_copi_m has no German rows
##
## So these are monthly concepts with a quarterly fallback: a country
## with no monthly series has its quarterly one in the quarterly panel
## and nothing in the monthly panel (scripts/build_panels.R,
## fetch_quarterly_fallbacks() in R/panel_quarterly.R).
##
## USA: the cost index only, from FRED's copy of the BLS producer price
## index for inputs to residential construction, goods (WPUIP2311001,
## monthly, NSA, June 1986 = 100, from 1986-06). Narrower than Eurostat's
## COST: it prices materials and excludes labour. The US has no published
## counterpart to PRC_PRR on a comparable footing, so that concept is NA.
## ---------------------------------------------------------------

construction_cost_concepts <- tibble::tribble(
  ~label,                          ~indic_bt,  ~fred_id,
  "construction_cost_index",       "COST",     "WPUIP2311001",
  "construction_producer_prices",  "PRC_PRR",  NA_character_
)

construction_cpa <- "CPA_F41001_X_410014"

#' The Eurostat sts_copi key of one indicator for one country
construction_index_key <- function(indic_bt, geo, frequency) {
  paste(frequency, indic_bt, construction_cpa, "NSA", "I21", geo, sep = ".")
}

#' Fetch a construction cost or price index for one country at one
#' frequency
#'
#' EU members from Eurostat at that frequency -- NULL where Eurostat has
#' no series at it, so that the caller can try the other -- the USA's
#' cost index from FRED (averaged to quarters for "Q"), NULL otherwise.
#' The result carries the source key in attr(, "source_col") and the
#' provider in attr(, "provider").
fetch_construction_index <- function(country3, label, start_period = "1990-M01",
                                     frequency = "M") {
  frequency <- check_frequency(frequency)
  row <- construction_cost_concepts[construction_cost_concepts$label == label, ]
  if (nrow(row) != 1) stop("Unknown construction concept: ", label)

  if (country3 %in% eu_member_countries) {
    geo <- lookup_ec_country2(country3)
    if (is.na(geo)) return(NULL)
    key <- construction_index_key(row$indic_bt, geo, frequency)
    out <- fetch_eurostat_sts_key(sts_dataflow("sts_copi", frequency), key, label,
                                  start_period, frequency)
    if (is.null(out)) return(NULL)
    attr(out, "provider") <- "EUROSTAT_STS"
    return(out)
  }

  if (identical(country3, "USA") && !is.na(row$fred_id)) {
    monthly <- get_fred_series(row$fred_id)
    if (is.null(monthly)) {
      warning(sprintf("[%s] FRED fetch failed for %s", label, row$fred_id))
      return(NULL)
    }
    names(monthly) <- c("date", label)
    out <- aggregate_to(monthly, label, frequency)
    out <- out[!is.na(out[[label]]) & out$date >= period_to_date(start_period), ]
    if (nrow(out) == 0) return(NULL)
    attr(out, "source_col") <- paste0(row$fred_id, if (identical(frequency, "Q")) " (quarterly average)" else "")
    attr(out, "provider") <- "FRED"
    return(out)
  }

  NULL
}
