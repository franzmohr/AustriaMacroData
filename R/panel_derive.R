## ---------------------------------------------------------------
## panel_derive.R -- the quarterly panel, derived from one fetch at each
## concept's native frequency
##
## EA-MD-QD's arrangement (Barigozzi, Lissona and Tonni): every series is
## held once, at the frequency its source publishes it, and the quarterly
## view is made from the monthly one by a rule per series -- flows are
## summed over the quarter, everything else is averaged. Nothing is ever
## interpolated: a quarterly concept is absent from the monthly panel.
##
## Two panels come out of it, kept apart rather than stacked on one
## monthly date index:
##   <cc>_monthly_panel.csv  FRED-MD style: the monthly concepts
##   <cc>_panel.csv          FRED-QD style: quarterly concepts, plus the
##                           monthly concepts aggregated to quarters
## and <cc>_metadata.csv carries the codes, units and sources that
## FRED-MD/QD keep in header rows, without putting anything but data
## into the data files.
## ---------------------------------------------------------------

#' Quarter start of each date
quarter_start <- function(date) {
  as.Date(sprintf("%s-%02d-01", format(date, "%Y"),
                  (as.integer(format(date, "%m")) - 1) %/% 3 * 3 + 1))
}

#' Aggregate the monthly concepts of a panel to quarters, each by its own
#' `aggregation` rule in `concept_dictionary`
#'
#' "mean" averages whatever months of the quarter are observed, as every
#' fetcher's quarterly path always has -- so the current quarter carries
#' the average of its months so far, as it did before. "sum" totals
#' complete quarters only (`monthly_to_quarterly_sum()`), since a partial
#' sum is not an estimate of the quarter but a fraction of it.
to_quarterly <- function(monthly_panel, labels = setdiff(names(monthly_panel), "date"),
                         dictionary = concept_dictionary) {
  rule <- dictionary$aggregation[match(labels, dictionary$label)]
  rule[is.na(rule)] <- "mean"
  out <- tibble::tibble(date = as.Date(character(0)))
  for (i in seq_along(labels)) {
    lbl <- labels[i]
    one <- monthly_panel[!is.na(monthly_panel[[lbl]]), c("date", lbl)]
    if (nrow(one) == 0) next
    q <- if (identical(rule[i], "sum")) {
      monthly_to_quarterly_sum(one, lbl)
    } else {
      monthly_to_quarterly(one, lbl)
    }
    out <- dplyr::full_join(out, q, by = "date")
  }
  dplyr::arrange(out, .data$date)
}

#' The unit of one concept as the source that resolved it publishes it
#'
#' `source` is the concept's `concept_source` entry (NULL if it did not
#' resolve). A `unit` the fetcher recorded there comes first; then the
#' provider's row in `concept_source_units`; then concept_metadata's
#' unit, which is written for euro-area members. `{currency}`, and
#' "national currency" in the dictionary's own units, become the
#' country's ISO 4217 code where it is known.
source_unit <- function(label, source, country = NA_character_,
                        dictionary = concept_dictionary, units = concept_source_units) {
  unit <- source$unit %||% {
    by_provider <- units$unit[units$label == label & units$provider %in% source$provider]
    if (length(by_provider) == 1) by_provider else dictionary$unit[dictionary$label == label]
  }
  currency <- if (is.na(country)) NA_character_ else lookup_currency(country)
  if (is.na(currency)) return(sub("{currency}", "national currency", unit, fixed = TRUE))
  unit <- sub("{currency}", currency, unit, fixed = TRUE)
  sub("national currency", currency, unit, fixed = TRUE)
}

#' One metadata row per concept: what it is, how it is published, how to
#' transform it and where it came from
#'
#' `panels` is a list with one panel per native frequency, `M` and `Q`;
#' each concept's first and last observed periods and its number of
#' observations are read from the panel of its own `frequency`, so a
#' monthly concept is counted in months, not in the quarters derived
#' from them. `frequency` overrides the dictionary's for this country, as
#' a named vector: a monthly concept the country has only a quarterly
#' series of is "Q" here (see fetch_quarterly_fallbacks()). `unit` is
#' the unit of the source that resolved for `country` (source_unit()), so
#' it differs across countries where their sources do.
series_metadata <- function(panels, concept_source, dictionary = concept_dictionary,
                            frequency = character(0), country = NA_character_) {
  freq_of <- function(lbl) {
    if (lbl %in% names(frequency)) frequency[[lbl]] else dictionary$frequency[dictionary$label == lbl]
  }
  native <- function(lbl) {
    panel <- panels[[freq_of(lbl)]]
    if (is.null(panel) || !lbl %in% names(panel)) return(as.Date(character(0)))
    panel$date[!is.na(panel[[lbl]])]
  }
  span <- function(lbl, f) {
    x <- native(lbl)
    if (length(x) == 0) return(NA_character_)
    date_to_period(f(x), freq_of(lbl))
  }
  dictionary %>%
    dplyr::transmute(
      label = .data$label,
      fred_qd_group = .data$fred_qd_group,
      frequency = purrr::map_chr(.data$label, freq_of),
      aggregation = .data$aggregation,
      unit = purrr::map_chr(.data$label, ~ source_unit(.x, concept_source[[.x]], country, dictionary)),
      sa = .data$sa,
      class = .data$class,
      tcode_fred = .data$tcode_fred,
      tcode_lt = .data$tcode_lt,
      tcode_ht = .data$tcode_ht,
      fred_qd_mnemonic = .data$fred_qd_mnemonic,
      provider = purrr::map_chr(.data$label, ~ concept_source[[.x]]$provider %||% NA_character_),
      key = purrr::map_chr(.data$label, ~ concept_source[[.x]]$key %||% NA_character_),
      first = purrr::map_chr(.data$label, ~ span(.x, min)),
      last = purrr::map_chr(.data$label, ~ span(.x, max)),
      n_obs = purrr::map_int(.data$label, ~ length(native(.x)))
    )
}
