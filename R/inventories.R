## ---------------------------------------------------------------
## inventories.R -- change in inventories, in percent of GDP
##
## The one expenditure component of GDP the panel was missing beside
## consumption, government consumption, fixed investment, exports and
## imports. Inventory swings are small on average and large at turning
## points, which is exactly when a model most needs them.
##
## WHY A SHARE OF GDP AND NOT A REAL LEVEL LIKE THE OTHER COMPONENTS.
## Eurostat publishes no chain-linked volume for changes in inventories
## (confirmed live 2026-09-26: namq_10_gdp returns nothing for
## Q.CLV20_MEUR.SCA.P52.AT or for P52_P53). That is by design rather than
## a gap: the series is a signed flow that crosses zero, and chain-linked
## volumes are not additive, so a "real change in inventories" in
## chain-linked euro is hard to interpret (the BEA does publish one in
## chained dollars, with exactly that warning). What Eurostat does
## publish is the nominal change as a percent of nominal GDP -- and that
## is also exactly what FRED-QD carries for the United States
## (A014RE1Q156NBEA, "Shares of GDP: change in private inventories"), so
## the concept matches its FRED-QD reference in construction and not
## just in spirit.
##
## SOURCE HIERARCHY.
## 1. Eurostat namq_10_gdp, UNIT=PC_GDP, S_ADJ=SCA, NA_ITEM=P52 (changes
##    in inventories, EXCLUDING acquisitions less disposals of valuables,
##    P53, which FRED-QD's series excludes too). VERIFIED live 2026-09-26:
##    Austria 1995-Q1 to 2026-Q2, range -1.8 to 4.1; Germany 1991-Q1 to
##    2026-Q2, range -1.6 to 1.8. Same dimension order as the real
##    anchors, so this goes through R/eurostat.R's
##    `fetch_eurostat_series()` with only the unit changed.
## 2. A country's own series via FRED, from the explicit table
##    `national_inventory_change` below: the United States only, FRED-QD's
##    own A014RE1Q156NBEA.
## Anything else resolves to NA.
##
## Eurostat's P52 covers inventories of all sectors, while FRED-QD's is
## PRIVATE inventories only; government inventories are small, so the
## difference is one of definition more than of magnitude.
## ---------------------------------------------------------------

eurostat_inventory_na_item <- "P52"
eurostat_inventory_unit <- "PC_GDP"

national_inventory_change <- tibble::tribble(
  ~country3, ~fred_id,
  "USA",     "A014RE1Q156NBEA"
)

#' Fetch the change in inventories (% of GDP) for one EU country
fetch_eurostat_inventory_change <- function(country3, label = "inventory_change_to_gdp",
                                            s_adj = "SCA", start_period = "1960-Q1") {
  if (!country3 %in% eu_member_countries) return(NULL)
  geo <- lookup_ec_country2(country3)
  if (is.null(geo) || is.na(geo)) return(NULL)

  out <- fetch_eurostat_series(geo, eurostat_inventory_na_item, label,
                               s_adj = s_adj, unit = eurostat_inventory_unit,
                               start_period = start_period)
  if (is.null(out)) return(NULL)

  out <- out %>%
    dplyr::mutate(date = period_to_date(.data$period)) %>%
    dplyr::select("date", dplyr::all_of(label)) %>%
    dplyr::filter(!is.na(.data[[label]])) %>%
    dplyr::arrange(.data$date)
  if (nrow(out) == 0) return(NULL)

  attr(out, "source_col") <- paste("namq_10_gdp:Q", eurostat_inventory_unit, s_adj,
                                   eurostat_inventory_na_item, geo, sep = ".")
  attr(out, "provider") <- "EUROSTAT"
  out
}

#' Fetch a country's own inventory-change share from FRED, or NULL
fetch_national_inventory_change <- function(country3, label = "inventory_change_to_gdp",
                                            start_period = "1960-Q1") {
  row <- national_inventory_change[national_inventory_change$country3 == country3, ]
  if (nrow(row) != 1) return(NULL)

  df <- get_fred_series(row$fred_id[1])
  if (is.null(df)) {
    warning(sprintf("[%s] FRED fetch failed for %s", label, row$fred_id[1]))
    return(NULL)
  }

  names(df)[2] <- label
  out <- df[!is.na(df[[label]]) & df$date >= period_to_date(start_period), ]
  if (nrow(out) == 0) {
    warning(sprintf("[%s] %s returned no usable observations", label, row$fred_id[1]))
    return(NULL)
  }

  attr(out, "source_col") <- row$fred_id[1]
  attr(out, "provider") <- "FRED"
  out
}

#' Fetch the change in inventories as a percent of GDP, quarterly
#'
#' Eurostat for EU members, then `national_inventory_change`; NULL
#' otherwise. Carries `provider` and `source_col` attributes.
fetch_inventory_change <- function(country3, label = "inventory_change_to_gdp",
                                   start_period = "1960-Q1") {
  fetch_eurostat_inventory_change(country3, label = label, start_period = start_period) %||%
    fetch_national_inventory_change(country3, label = label, start_period = start_period)
}
