## ---------------------------------------------------------------
## dummies.R -- dummy variables for dated policy events
##
## A separate dataset from the panels, because a dummy is not a
## measurement: it is the researcher's statement that something happened
## on a date, and it belongs beside the data rather than among them. Each
## event is one row of `policy_events`, with the source that dates it, and
## the monthly and quarterly dummy files are generated from that table, so
## a date is authored in exactly one place.
##
## Two kinds of dummy:
##   "step"     1 in every month the measure is in force, from `start` to
##              `end` (NA end: still in force). In a quarterly file it is
##              the SHARE of the quarter's months in force -- KIM-V took
##              effect on 1 August 2022, so 2022-Q3 reads 2/3 -- which is
##              the within-quarter average every stock and rate in the
##              quarterly panel is formed by.
##   "impulse"  1 in the month of a one-off event (an announcement), and 1
##              in the quarter containing it.
##
## AUSTRIA: the borrower-based measures for residential real estate
## lending (Kreditinstitute-Immobilienfinanzierungsmaßnahmen-Verordnung,
## KIM-V), the event that matters most for loans for house purchase.
## Dates confirmed on 2026-10-03 against:
##   - the FMA's notification to the ESRB of 13 June 2024 (limits since
##     2022: LTV 90%, DSTI 40%, maturity 35 years; the April 2023
##     amendments; the merged exemption bucket from 1 July 2024; end date
##     30 June 2025)
##     https://www.esrb.europa.eu/pub/pdf/other/Esrb.notification240613_BBMs_AT~037e4af1e2.en.pdf
##   - WKO, "KIM-Verordnung wird 2025 auslaufen" (in force since 1 August
##     2022; expired on 30 June 2025 on the FMSG's recommendation)
##     https://www.wko.at/bank-versicherung/kim-verordnung-wird-2025-auslaufen
## GERMANY: no borrower-based measures, but a capital-based one aimed at the
## same lending -- BaFin's sectoral systemic risk buffer on loans secured by
## residential real estate, ordered from 1 April 2022 and binding in full from
## 1 February 2023 at 2%, lowered to 1% from 1 May 2025. Dates confirmed on
## 2026-10-03 against DBRS Morningstar's summary of BaFin's decision and the
## Bundesbank's statement on the reduction (sources in the table). Germany is
## the natural control for KIM-V -- same ECB rates, no borrower-based limits --
## and this is the one German measure that would contaminate it.
##
## The FMSG recommendation the regulation implements dates from December
## 2021; only the month is confirmed, which is all a monthly dummy needs.
## Lending between the announcement and August 2022 may have been pulled
## forward, which is what the announcement impulse is for.
## ---------------------------------------------------------------

policy_events <- tibble::tribble(
  ~country, ~name,                          ~type,     ~start,       ~end,         ~description,                                                                                                                                                         ~source,
  "AUT",    "kimv_announcement",            "impulse", "2021-12-01", NA,           "FMSG recommends legally binding borrower-based measures for residential real estate lending, which the FMA implements as KIM-V.",                                    "https://www.wko.at/oe/bank-versicherung/newsline-dezember-2022.pdf",
  "AUT",    "kimv",                         "step",    "2022-08-01", "2025-06-30", "KIM-V in force: LTV at most 90% (20% exemption), DSTI at most 40% (10%), maturity at most 35 years (5%) for new residential real estate loans to households.", "https://www.esrb.europa.eu/pub/pdf/other/Esrb.notification240613_BBMs_AT~037e4af1e2.en.pdf",
  "AUT",    "kimv_bridging_exemption",      "step",    "2023-04-01", "2025-06-30", "KIM-V amendment: bridging loans and non-repayable government grants excluded; de minimis threshold for couples raised to EUR 100,000.",                     "https://www.esrb.europa.eu/pub/pdf/other/Esrb.notification240613_BBMs_AT~037e4af1e2.en.pdf",
  "AUT",    "kimv_single_exemption_bucket", "step",    "2024-07-01", "2025-06-30", "KIM-V amendment: the separate exemption buckets merged into one institution-specific bucket of 20% of new lending volume.",                                "https://www.esrb.europa.eu/pub/pdf/other/Esrb.notification240613_BBMs_AT~037e4af1e2.en.pdf",
  "DEU",    "syrb_rre_order",               "impulse", "2022-04-01", NA,           "BaFin orders a sectoral systemic risk buffer of 2% of risk-weighted assets on loans secured by residential real estate, to be met in full from 1 February 2023.",    "https://dbrs.morningstar.com/research/391754/bafin-introduces-countercyclical-and-sectoral-systemic-risk-buffer",
  "DEU",    "syrb_rre",                     "step",    "2023-02-01", NA,           "Sectoral systemic risk buffer on residential real estate loans binding (2% until April 2025, 1% from May 2025; see syrb_rre_cut).",                               "https://dbrs.morningstar.com/research/391754/bafin-introduces-countercyclical-and-sectoral-systemic-risk-buffer",
  "DEU",    "syrb_rre_cut",                 "step",    "2025-05-01", NA,           "BaFin lowers the sectoral systemic risk buffer on residential real estate loans from 2% to 1%.",                                                                   "https://www.bundesbank.de/de/aufgaben/themen/ausschuss-fuer-finanzstabilitaet-begruesst-die-entscheidung-der-bundesanstalt-fuer-finanzdienstleistungsaufsicht-den-sektoralen-systemrisikopuffer-auf-1-zu-senken-956564"
) %>%
  dplyr::mutate(start = as.Date(.data$start), end = as.Date(.data$end))

#' Monthly dummies for one country's events over a range of months
#'
#' Returns a tibble with `date` (month starts from `from` to `to`) and one
#' column per event, or NULL if the country has no events.
make_monthly_dummies <- function(country, from, to, events = policy_events) {
  ev <- events[events$country == country, ]
  if (nrow(ev) == 0) return(NULL)
  months <- seq(as.Date(format(from, "%Y-%m-01")), as.Date(format(to, "%Y-%m-01")), by = "month")
  out <- tibble::tibble(date = months)
  for (i in seq_len(nrow(ev))) {
    first <- as.Date(format(ev$start[i], "%Y-%m-01"))
    out[[ev$name[i]]] <- if (identical(ev$type[i], "impulse")) {
      as.numeric(months == first)
    } else {
      last <- if (is.na(ev$end[i])) as.Date("9999-12-01") else as.Date(format(ev$end[i], "%Y-%m-01"))
      as.numeric(months >= first & months <= last)
    }
  }
  out
}

#' Quarterly dummies from monthly ones: the share of the quarter's months
#' a step is in force, and 1 for a quarter containing an impulse
make_quarterly_dummies <- function(monthly, events = policy_events) {
  if (is.null(monthly)) return(NULL)
  cols <- setdiff(names(monthly), "date")
  type <- events$type[match(cols, events$name)]
  monthly %>%
    dplyr::mutate(date = quarter_start(.data$date)) %>%
    dplyr::group_by(.data$date) %>%
    dplyr::summarise(
      dplyr::across(dplyr::all_of(cols[type == "step"]), mean),
      dplyr::across(dplyr::all_of(cols[type == "impulse"]), max),
      .groups = "drop"
    ) %>%
    dplyr::select("date", dplyr::all_of(cols))
}
