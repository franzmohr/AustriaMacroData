## ---------------------------------------------------------------
## fred_mirror.R -- FRED's public mirror of OECD MEI / BIS series
## (industrial production, unemployment, CPI, interest rates,
## exchange rates, consumer confidence, house prices, retail sales
## volume, share prices). Plain fredgraph.csv downloads, no API key.
##
## STATUS: VERIFIED 2026-08-30 for DEU and USA (see README for the
## per-row status). Several of the original script's mnemonics were
## wrong and are corrected below; each correction was found by
## searching fred.stlouisfed.org's own series search, then confirmed
## with a live 200 response, not guessed again.
## ---------------------------------------------------------------

#' Fetch one FRED series via the public fredgraph.csv export (no API key)
get_fred_series <- function(fred_id) {
  url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=", fred_id)
  txt <- fetch_text(url)
  if (is.null(txt)) return(NULL)

  if (stringr::str_detect(txt, stringr::regex("<!DOCTYPE html|<html|Bad Request|series does not exist", ignore_case = TRUE))) {
    return(NULL)
  }

  df <- suppressWarnings(readr::read_csv(txt, show_col_types = FALSE))
  if (ncol(df) != 2) return(NULL)
  names(df) <- c("date", fred_id)
  df$date <- as.Date(df$date)
  df
}

#' Additional FRED-QD-style groups, via FRED's OECD/BIS mirrors
##
## `id_template` uses "{cc2}" for FRED's 2-letter OECD-mirror country code
## and "{cc3}" for the ISO-3166 alpha-3 code (same value as the OECD/IMF
## `country` argument used elsewhere in this project).
##
## Corrections made on verification (original = the script's earlier guess):
##   industrial_production: PRINTO01{cc2}Q661S (404) -> {cc3}PROINDQISMEI
##   cpi_index:              CPALTT01{cc2}Q661S (404) -> CPALTT01{cc2}Q657N
##   consumer_confidence:    CSCICP03{cc2}Q460S (404, no quarterly series
##                           exists at OECD MEI) -> CSCICP03{cc2}M665S,
##                           monthly, averaged to quarterly by this module
##   retail_sales_volume:    SLRTTO01{cc2}Q189S (404) -> {cc3}SARTQISMEI
##                           (confirmed for DEU; NOT published for USA --
##                           genuine coverage gap, not a wrong code)
## Unchanged because they already verified correctly:
##   unemployment_rate, long_term_rate, fx_rate_to_usd, house_price_real,
##   share_price_index
##
## KNOWN ISSUE found 2026-08-30 while extending this table: `cpi_index`
## (CPALTT01{cc2}Q657N) and `consumer_confidence` (CSCICP03{cc2}M665S)
## both return real 200 responses, but their data stops in 2024 for DE
## (checked live) -- this whole OECD-MEI-mirror-via-FRED family appears to
## have been frozen when OECD migrated the legacy MEI dataflow to its new
## SDMX 3.0 system, and FRED's mirror was not updated to follow. A live
## fix would mean sourcing these from OECD's new CPI dataflow directly
## (the way R/oecd.R already does for QNA), which needs the same kind of
## live structure verification as oecd.R got -- not done here because
## OECD's own data endpoint (not just this FRED mirror) was rate-limiting
## this session's requests (HTTP 429) throughout this verification pass.
## Left as-is (better than nothing, but not "current") rather than
## papering over it; worth a follow-up once the rate limit clears.
##
## SECOND, DEEPER ISSUE found 2026-08-31 by `R/plausibility_checks.R`
## (this project's country-agnostic sanity-check layer, not a human
## re-reading this file): `cpi_index`'s FRED-mirror value
## (CPALTT01{cc2}Q657N) is itself a quarterly PERCENT CHANGE series, not
## the INDEX LEVEL its own name and its FRED-QD mnemonic (CPIAUCSL, a
## genuine level index) both imply -- confirmed directly against the raw
## series: values like 2.97, 1.31, 0.37 for 2022-2023 match real US
## quarterly inflation RATES almost exactly, not a CPI level (which
## should read roughly 25-30 for a 1950s observation on FRED-QD's own
## 1982-84=100 base, not 0-1). Every EU member state already gets a
## genuine level index via the Eurostat HICP override
## (`fetch_eurostat_hicp()`, R/eurostat.R); this only affects countries
## still on the FRED-mirror default (confirmed: the United States).
## NOT fixed here -- finding OECD's or FRED's actual CPI LEVEL mnemonic
## for non-EU countries needs the same live-verification treatment every
## other correction in this file got, which is a task in its own right
## (a good first task for a researcher extending this project -- see
## CONTRIBUTING.md). `R/plausibility_checks.R` categorizes `cpi_index`
## to tolerate both constructions rather than silently masking the
## finding.
##
## ADDED 2026-08-30 (4 new concepts, filling 2 groups that previously had
## nothing and enriching 2 that only had one representative concept),
## each confirmed with a real, CURRENT (2026-Q1/Q2) 200 response for both
## DE and US:
##   unit_labor_cost:              ULQEUL01{cc2}Q657S  (Earnings and Productivity --
##                                 previously unattempted; confirmed with a real, current
##                                 200 response for AT, DE, FR, GB AND US. NOTE: the
##                                 correct suffix is "Q657S", NOT "Q657N" -- an initial
##                                 implementation used Q657N (a plausible-looking but
##                                 wrong guess by analogy with cpi_index's suffix) and
##                                 got 404 for every country; caught by re-verifying the
##                                 exact string actually tested live, not by re-guessing.
##   short_term_rate:               IR3TIB01{cc2}Q156N  (3-month interbank rate; natural
##                                 pair to the existing long_term_rate)
##   real_effective_exchange_rate:  CCRETT01{cc2}Q661N  (better cross-country analog to
##                                 FRED-QD's trade-weighted dollar index than a bilateral
##                                 rate, since it works the same way for every country)
##   employment_rate:               LREM64TT{cc2}Q156S  (employment-to-population ratio,
##                                 ages 15-64; complements unemployment_rate)
## Two other candidates were checked and rejected as stale, not added:
## PPI (PIEAMP01/PIEATI01{cc2}Q661N, data stops 2022) and business
## confidence (BSCICP03{cc2}M665S, data stops 2024 -- same frozen-mirror
## issue as cpi_index/consumer_confidence above).
##
## ADDED 2026-09-14: world_uncertainty_index, WUI{cc3} -- FRED's mirror of
## the World Uncertainty Index of Ahir, Bloom and Furceri (2022). Unlike
## the OECD MEI family it is keyed by the ISO-3166 ALPHA-3 code (WUIAUT,
## WUIDEU, WUIUSA), confirmed with a real, current (2026-Q2) 200 response
## for all three. Its early quarters contain genuine zeros (WUIAUT reads
## 0 in 1963-Q4 and 1964-Q1), hence its own plausibility category.
other_groups <- tibble::tribble(
  ~fred_qd_group,                   ~label,                         ~id_template,         ~frequency, ~m_id_template,       ~source,
  "Industrial Production",          "industrial_production",         "{cc3}PROINDQISMEI",   "Q",  "{cc3}PROINDMISMEI",   "OECD MEI (via FRED)",
  "Employment and Unemployment",    "unemployment_rate",             "LRHUTTTT{cc2}Q156S",  "Q",  "LRHUTTTT{cc2}M156S",  "OECD MEI (via FRED)",
  # cpi_index has NO usable monthly mirror. CPALTT01{cc2}M657N exists and
  # returns data, but the OECD MEI suffix 657 is a GROWTH RATE, not an index:
  # confirmed live 2026-09-25, CPALTT01ATM657N runs -2.36 to 5.12 with 160
  # negative observations. Splicing that onto the HICP index produced a
  # monthly cpi_index reaching -377, which is how it was found. The monthly
  # panel therefore takes cpi_index from Eurostat's HICP or not at all.
  "Employment and Unemployment",    "employment_rate",               "LREM64TT{cc2}Q156S",  "Q",  NA,                    "OECD MEI (via FRED)",
  "Prices",                         "cpi_index",                     "CPALTT01{cc2}Q657N",  "Q",  NA,                     "OECD MEI (via FRED)",
  "Earnings and Productivity",      "unit_labor_cost",               "ULQEUL01{cc2}Q657S",  "Q",  NA,                    "OECD MEI (via FRED)",
  "Interest Rates",                 "long_term_rate",                "IRLTLT01{cc2}Q156N",  "Q",  "IRLTLT01{cc2}M156N",  "OECD MEI (via FRED)",
  "Interest Rates",                 "short_term_rate",               "IR3TIB01{cc2}Q156N",  "Q",  "IR3TIB01{cc2}M156N",  "OECD MEI (via FRED)",
  "Exchange Rates",                 "fx_rate_to_usd",                "CCUSMA02{cc2}Q618N",  "Q",  "CCUSMA02{cc2}M618N",  "OECD MEI (via FRED)",
  "Exchange Rates",                 "real_effective_exchange_rate",  "CCRETT01{cc2}Q661N",  "Q",  "CCRETT01{cc2}M661N",  "OECD MEI (via FRED)",
  "Other",                          "consumer_confidence",           "CSCICP03{cc2}M665S",  "M",  "CSCICP03{cc2}M665S",  "OECD MEI (via FRED)",
  "Housing",                        "house_price_real",              "Q{cc2}R628BIS",       "Q",  NA,                    "BIS Residential Property Prices (via FRED)",
  "Inventories, Orders, and Sales", "retail_sales_volume",           "{cc3}SARTQISMEI",     "Q",  "{cc3}SARTMISMEI",     "OECD MEI (via FRED)",
  "Stock Markets",                  "share_price_index",             "SPASTT01{cc2}Q661N",  "Q",  "SPASTT01{cc2}M661N",  "OECD MEI (via FRED)",
  "Other",                          "world_uncertainty_index",       "WUI{cc3}",            "Q",  NA,                    "World Uncertainty Index (via FRED)"
)

#' Average a monthly series up to quarterly (calendar quarters, simple mean)
monthly_to_quarterly <- function(df, value_col) {
  df %>%
    dplyr::mutate(
      year = as.integer(format(.data$date, "%Y")),
      q = (as.integer(format(.data$date, "%m")) - 1) %/% 3 + 1,
      date = as.Date(sprintf("%d-%02d-01", .data$year, (.data$q - 1) * 3 + 1))
    ) %>%
    dplyr::group_by(.data$date) %>%
    dplyr::summarise(!!value_col := mean(.data[[value_col]], na.rm = TRUE), .groups = "drop")
}

fetch_other_group_series <- function(id_template, source_frequency, cc2, cc3, label,
                                      fred_qd_group, source, frequency = "Q") {
  fred_id <- id_template
  fred_id <- stringr::str_replace(fred_id, stringr::fixed("{cc2}"), cc2)
  fred_id <- stringr::str_replace(fred_id, stringr::fixed("{cc3}"), cc3)

  df <- get_fred_series(fred_id)
  if (is.null(df)) {
    warning(sprintf(
      "[%s / %s] '%s' not found. Search for the right mnemonic at: https://fred.stlouisfed.org/search?st=%s",
      label, source, fred_id, utils::URLencode(paste(fred_qd_group, cc3))
    ))
    return(NULL)
  }

  # A monthly panel is only ever handed a monthly mnemonic, so the series is
  # stamped to month starts and otherwise left alone. A quarterly panel
  # averages a monthly source down and takes a quarterly one as it comes.
  if (identical(frequency, "M")) {
    df <- aggregate_to(df, fred_id, "M")
  } else if (identical(source_frequency, "M")) {
    df <- aggregate_to(df, fred_id, "Q")
  }

  names(df)[2] <- label
  df
}

#' Fetch all "other groups" concepts for one country from FRED's mirrors
#'
#' `fred_country2` is FRED's 2-letter OECD-mirror code (e.g. "DE"),
#' `country3` is the ISO-3166 alpha-3 code (e.g. "DEU") also used for
#' OECD/IMF. These are DIFFERENT coding conventions from different
#' sources -- do not swap them.
fetch_other_groups <- function(fred_country2, country3, frequency = "Q", labels = NULL) {
  check_frequency(frequency)

  # Not every OECD MEI concept has a monthly counterpart, and the ones that
  # do not are dropped here rather than fetched and discarded: a quarterly
  # series joined into a monthly panel would sit on the first month of each
  # quarter with two gaps after it, which looks like a reporting lag rather
  # than a frequency mismatch. `m_id_template` is NA for those -- confirmed
  # against real 404s from FRED for employment_rate (LREM64TT..M156S),
  # unit_labor_cost (ULQEUL01..M657S) and house_price_real (M..R628BIS),
  # and world_uncertainty_index is published quarterly at source.
  wanted <- if (identical(frequency, "M")) {
    dplyr::filter(other_groups, !is.na(.data$m_id_template))
  } else {
    other_groups
  }
  ## `labels` restricts the fetch to some concepts -- scripts/build_panels.R
  ## asks the quarterly mirrors only for the concepts that are quarterly at
  ## source, the rest coming from the monthly panel.
  if (!is.null(labels)) wanted <- dplyr::filter(wanted, .data$label %in% labels)
  templates <- if (identical(frequency, "M")) wanted$m_id_template else wanted$id_template

  results <- purrr::pmap(
    list(templates, wanted$frequency, wanted$label, wanted$fred_qd_group, wanted$source),
    function(id_template, source_frequency, label, fred_qd_group, source) {
      fetch_other_group_series(id_template, source_frequency, fred_country2, country3,
                                label, fred_qd_group, source, frequency = frequency)
    }
  )
  names(results) <- wanted$label
  purrr::compact(results)
}

## ---------------------------------------------------------------
## A national consumer price INDEX, for countries with no Eurostat HICP
##
## The OECD MEI family has no index-valued CPI mirror at all. What it
## has is CPALTT01{cc2}{freq}657N, a period-on-period GROWTH RATE
## (confirmed live 2026-09-25: CPALTT01ATM657N runs -2.36 to 5.12 with
## 160 negative observations), and CPALTT01{cc2}M659N, a year-on-year
## growth rate. The index-shaped mnemonic one would expect by analogy
## with the other OECD MEI series, CPALTT01{cc2}M661N, does not exist --
## confirmed by real 404s for AT, DE and US alike.
##
## That left `cpi_index` holding an index level for EU members, from the
## Eurostat HICP override, and a percent change for everyone else. Both
## constructions were accommodated by giving the concept a plausibility
## category wide enough for both, which is documented and tested -- but
## a column that is one statistic for some countries and another for the
## rest is not a column anyone can write cross-country code against, and
## docs/data_sources.csv has always documented the intended US source as
## the INDEX, CPIAUCSL. The panel now matches its own documentation.
##
## This is deliberately a small, explicit, per-country table rather than
## a template. There is no cross-country convention to exploit: each
## national statistical office's index reaches FRED under its own
## mnemonic, base year and seasonal-adjustment choice, and guessing one
## from a country code is how a plausible-looking wrong series gets into
## a panel. A country not listed here, and not covered by the Eurostat
## HICP, resolves to NA -- which is the honest answer and is visible in
## the coverage report, where a mislabelled series would not be.
national_cpi_index <- tibble::tribble(
  ~country3, ~fred_id,    ~note,
  "USA",     "CPIAUCSL",  "Consumer Price Index for All Urban Consumers: All Items in U.S. City Average, index 1982-1984 = 100, seasonally adjusted, monthly from 1947-01. This is FRED-QD's own cpi_index series, which docs/data_sources.csv already names as the US reference."
)

#' Fetch a country's own consumer price index from FRED, or NULL
#'
#' The last-resort route for `cpi_index`, tried only where the Eurostat
#' HICP does not apply. `frequency` says what the panel wants; the
#' source is monthly and is averaged down for a quarterly panel, as
#' every other monthly FRED source here is.
fetch_national_cpi_index <- function(country3, label = "cpi_index",
                                     start_period = "1960-Q1",
                                     frequency = "Q") {
  check_frequency(frequency)
  row <- national_cpi_index[national_cpi_index$country3 == country3, ]
  if (nrow(row) != 1) return(NULL)

  df <- get_fred_series(row$fred_id[1])
  if (is.null(df)) {
    warning(sprintf("[%s] FRED fetch failed for %s", label, row$fred_id[1]))
    return(NULL)
  }

  names(df)[2] <- label
  out <- aggregate_to(df, label, frequency)
  out[[label]][is.nan(out[[label]])] <- NA_real_
  out <- out[!is.na(out[[label]]), ]
  out <- out[out$date >= period_to_date(start_period), ]

  if (nrow(out) == 0) {
    warning(sprintf("[%s] %s returned no usable observations", label, row$fred_id[1]))
    return(NULL)
  }

  attr(out, "source_col") <- row$fred_id[1]
  out
}
