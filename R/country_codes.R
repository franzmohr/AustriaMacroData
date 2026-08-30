## ---------------------------------------------------------------
## country_codes.R -- ISO-3166 alpha-3 (used by OECD/IMF) to FRED's
## 2-letter OECD-mirror country code. These are two different coding
## conventions from two different sources; mixing them up is a
## silent-failure trap noted in the original script and preserved
## here as an explicit, checked mapping rather than a string-slicing
## guess (alpha-3[1:2] is wrong for many countries, e.g. AUT -> "AU"
## would collide with Australia's real FRED code).
## ---------------------------------------------------------------

country_code_map <- tibble::tribble(
  ~country3, ~country2, ~country_name,
  "AUS", "AU", "Australia",
  "AUT", "AT", "Austria",
  "BEL", "BE", "Belgium",
  "CAN", "CA", "Canada",
  "CHE", "CH", "Switzerland",
  "CHL", "CL", "Chile",
  "COL", "CO", "Colombia",
  "CZE", "CZ", "Czechia",
  "DEU", "DE", "Germany",
  "DNK", "DK", "Denmark",
  "ESP", "ES", "Spain",
  "EST", "EE", "Estonia",
  "FIN", "FI", "Finland",
  "FRA", "FR", "France",
  "GBR", "GB", "United Kingdom",
  "GRC", "GR", "Greece",
  "HUN", "HU", "Hungary",
  "IRL", "IE", "Ireland",
  "ISL", "IS", "Iceland",
  "ISR", "IL", "Israel",
  "ITA", "IT", "Italy",
  "JPN", "JP", "Japan",
  "KOR", "KR", "South Korea",
  "LTU", "LT", "Lithuania",
  "LUX", "LU", "Luxembourg",
  "LVA", "LV", "Latvia",
  "MEX", "MX", "Mexico",
  "MLT", "MT", "Malta",
  "NLD", "NL", "Netherlands",
  "NOR", "NO", "Norway",
  "NZL", "NZ", "New Zealand",
  "POL", "PL", "Poland",
  "PRT", "PT", "Portugal",
  "SVK", "SK", "Slovakia",
  "SVN", "SI", "Slovenia",
  "SWE", "SE", "Sweden",
  "TUR", "TR", "Turkey",
  "USA", "US", "United States"
)

#' Look up the FRED 2-letter code for an ISO-3166 alpha-3 country code
#'
#' Returns NULL (with a warning) if not in the built-in table -- callers
#' should pass --fred-country2 explicitly for countries not listed here
#' rather than guessing.
lookup_country2 <- function(country3) {
  row <- country_code_map[country_code_map$country3 == country3, ]
  if (nrow(row) == 0) {
    warning(sprintf("No built-in FRED 2-letter code for '%s' -- pass --fred-country2 explicitly", country3))
    return(NA_character_)
  }
  row$country2[1]
}

## ---------------------------------------------------------------
## EU membership (27 states) -- used by R/ec_survey.R to decide whether
## the European Commission's own Business and Consumer Survey (a live,
## EU-specific source) should be tried for a given country. This is a
## narrower, DIFFERENT list from R/ecb.R's `euro_area_countries` (EU
## membership vs. euro currency union -- e.g. Sweden, Poland, Denmark are
## EU but not euro area).
## ---------------------------------------------------------------
eu_member_countries <- c(
  "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA",
  "DEU", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD",
  "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"
)

#' Look up the European Commission's 2-letter country code for its
#' Business and Consumer Survey column headers (e.g. "AT.CONS")
#'
#' Confirmed live 2026-08-30 against the actual survey file: identical to
#' the ISO-3166 alpha-2 / FRED 2-letter code used elsewhere in this
#' project for every EU member EXCEPT Greece, which the Commission's own
#' convention encodes as "EL" (not the ISO code "GR") -- confirmed by
#' finding "EL.CONS" (not "GR.CONS") in the file's column headers.
lookup_ec_country2 <- function(country3) {
  if (identical(country3, "GRC")) return("EL")
  lookup_country2(country3)
}
