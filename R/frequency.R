## ---------------------------------------------------------------
## frequency.R -- one switch between a quarterly and a monthly panel
##
## Most of this project's sources are natively MONTHLY and were being
## averaged to quarters on the way in: the HICP, the EC business and
## consumer surveys, the ECB's interest rates, the geopolitical risk
## index, the world oil price, Kilian's activity index and most of the
## OECD MEI mirrors all publish every month. Two are daily (the ECB's
## CISS, the ATX). Only the national accounts, the BIS credit series and
## the government accounts are quarterly at source.
##
## So a monthly panel is mostly a matter of NOT aggregating, and the way
## to get one without a second copy of every parser is to make the
## aggregation step a parameter. Every fetcher that ended in
## `monthly_to_quarterly(x, label)` now ends in
## `aggregate_to(x, label, frequency)` and carries a `frequency`
## argument defaulting to "Q", so the quarterly builder is unchanged and
## the monthly one passes "M".
##
## WHAT "M" DOES, AND WHAT IT DOES NOT. It stamps every observation to
## the first of its month and averages within the month. For a source
## that is already monthly that is an identity beyond sorting; for a
## daily source it is the same simple within-period mean the quarterly
## path applies, one level down. What it never does is turn a quarterly
## source into a monthly one. There is no interpolation anywhere here:
## a concept that is published quarterly is absent from the monthly
## panel rather than spread across its months, because a quarterly
## number repeated or smoothed into three monthly ones is an invention
## that looks exactly like data.
## ---------------------------------------------------------------

supported_frequencies <- c("Q", "M")

#' Check a frequency argument and return it
#'
#' Called at the top of every fetcher that takes one, so that a typo is
#' refused where it was written rather than silently falling through to
#' quarterly -- which would produce a panel with three quarters of its
#' columns at one frequency and the rest at another, joined on a date
#' key that makes the mixture invisible.
check_frequency <- function(frequency) {
  if (!is.character(frequency) || length(frequency) != 1 ||
      is.na(frequency) || !frequency %in% supported_frequencies) {
    stop(sprintf("`frequency` must be one of %s, not %s.",
                 paste(sQuote(supported_frequencies), collapse = " or "),
                 if (is.character(frequency) && length(frequency) == 1)
                   sQuote(frequency) else "what was given"),
         call. = FALSE)
  }
  frequency
}

#' Collapse a daily or monthly series to month starts (simple mean)
#'
#' The monthly counterpart of `monthly_to_quarterly()` (R/fred_mirror.R).
monthly_to_monthly <- function(df, value_col) {
  df %>%
    dplyr::mutate(date = as.Date(sprintf("%s-%s-01", format(.data$date, "%Y"),
                                         format(.data$date, "%m")))) %>%
    dplyr::group_by(.data$date) %>%
    dplyr::summarise(!!value_col := mean(.data[[value_col]], na.rm = TRUE),
                     .groups = "drop")
}

#' Aggregate a sub-annual series to the panel's frequency
aggregate_to <- function(df, value_col, frequency = "Q") {
  check_frequency(frequency)
  if (identical(frequency, "M")) {
    monthly_to_monthly(df, value_col)
  } else {
    monthly_to_quarterly(df, value_col)
  }
}

#' Sum a monthly FLOW into quarters, keeping complete quarters only
#'
#' The counterpart of `monthly_to_quarterly()` for a series whose monthly
#' figures add up to the quarter's, such as a volume of new loans. A
#' quarter with fewer than three months is dropped rather than summed
#' over the months it has: the latest quarter is usually incomplete, and
#' a partial sum there would read as a collapse that never happened.
monthly_to_quarterly_sum <- function(df, value_col) {
  df %>%
    dplyr::filter(!is.na(.data[[value_col]])) %>%
    dplyr::mutate(
      year = as.integer(format(.data$date, "%Y")),
      q = (as.integer(format(.data$date, "%m")) - 1) %/% 3 + 1,
      month = format(.data$date, "%m"),
      date = as.Date(sprintf("%d-%02d-01", .data$year, (.data$q - 1) * 3 + 1))
    ) %>%
    dplyr::group_by(.data$date) %>%
    dplyr::summarise(n_months = dplyr::n_distinct(.data$month),
                     !!value_col := sum(.data[[value_col]]), .groups = "drop") %>%
    dplyr::filter(.data$n_months == 3) %>%
    dplyr::select("date", dplyr::all_of(value_col))
}

#' The default first period of a panel at a given frequency
#'
#' "1995-Q1" and "1995-M01" are the same instant, but a fetcher's
#' `start_period` has to be written in the form its frequency uses,
#' because `period_to_date()` reads the form rather than guessing.
default_start_period <- function(frequency = "Q", year = 1995) {
  check_frequency(frequency)
  if (identical(frequency, "M")) sprintf("%d-M01", year) else sprintf("%d-Q1", year)
}

#' Rewrite a period string into the form another frequency uses
#'
#' A quarterly start given to a monthly fetcher becomes the first month
#' of that quarter, and a monthly start given to a quarterly fetcher
#' becomes the quarter containing it. Anything already in the right form
#' is returned unchanged.
as_period <- function(period, frequency = "Q") {
  check_frequency(frequency)
  date <- period_to_date(period)
  if (any(is.na(date))) {
    stop(sprintf("`start_period` '%s' is neither 'YYYY-Qn' nor 'YYYY-Mnn'.", period),
         call. = FALSE)
  }
  date_to_period(date, frequency = frequency)
}
