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
