## ---------------------------------------------------------------
## global_activity.R -- Kilian's index of global real economic activity
##
## Like R/commodities.R's oil price, and unlike everything else in this
## project, what this fetches is not a country's own statistic: there is
## one world business cycle, so the series is identical in every
## country's panel. It earns a place in a national panel for the same
## reason the oil price does, and in fact for a sharper one -- the world
## oil price is not exogenous to world demand, so a panel that carries
## `oil_price` without a global activity control cannot tell an oil
## SUPPLY disturbance from an oil DEMAND one. Kilian (2009) is the paper
## that made that distinction, and this index is the variable it made it
## with.
##
## WHAT THE INDEX IS. Kilian (2009, American Economic Review 99(3),
## 1053-1069) builds it from dry cargo single-voyage ocean freight rates:
## bulk shipping is the one input that every traded industrial commodity
## needs, its supply is close to fixed at business-cycle frequencies, and
## its rates are quoted globally, so their common component tracks world
## industrial demand without having to aggregate national accounts that
## are published late, in different currencies and on different bases.
##
## IT IS SIGNED AND CENTRED ON ZERO. The index is expressed in percent
## deviations from a trend, so roughly half its observations are
## NEGATIVE (confirmed live: it ranges from -162 in February 2016 to +189
## in May 2008). This is why it carries the "deviation" plausibility
## category rather than "level", and it is the trap a user should be
## warned about before anything else: it must NOT be logged, and a
## quarter-over-quarter percent change of it is meaningless, because the
## denominator crosses zero. Use it in levels.
##
## SOURCE. FRED series IGREA, monthly from 1968-01, maintained by the
## Federal Reserve Bank of Dallas from Lutz Kilian's own construction.
## Monthly observations are averaged within the quarter, as R/commodities.R
## and R/fred_mirror.R do for every other monthly FRED source here.
##
## IT IS REVISED. The trend the index deviates from is re-estimated as
## the sample grows, so history changes between vintages -- more than for
## an ordinary published statistic and in a way that has no release
## calendar. A result that depends on the exact level of this series in
## some historical quarter should be treated with corresponding caution.
##
## THE ALTERNATIVES, AND WHY THIS ONE. Hamilton (2019, Journal of Applied
## Econometrics) argues the detrending is the wrong one and proposes world
## industrial production instead; Baumeister and Hamilton have published
## such a series, and the CPB World Trade Monitor publishes another. Both
## are defensible and neither is on FRED: they require scraping an Excel
## workbook from a research page with no stable schema, which is the kind
## of source this project only takes on when nothing else will do (see
## R/gpr.R, which does exactly that, and says why). IGREA is fetched here
## because it is the series the oil literature actually conditions on, it
## comes down the same well-tested FRED path as everything else, and a
## user who prefers Hamilton's measure can substitute it in one column.
## ---------------------------------------------------------------

global_activity_fred_id <- "IGREA"

#' Fetch Kilian's index of global real economic activity, quarterly
#'
#' The `country3` argument is accepted and ignored, exactly as in
#' R/commodities.R's `fetch_oil_price()`: it exists so the builder can
#' call this the way it calls every other concept fetcher.
fetch_global_activity <- function(country3 = NULL, label = "global_activity",
                                  start_period = "1960-Q1",
                                  fred_id = global_activity_fred_id,
                                  frequency = "Q") {
  df <- get_fred_series(fred_id)
  if (is.null(df)) {
    warning(sprintf("[%s] FRED fetch failed for %s", label, fred_id))
    return(NULL)
  }

  names(df)[2] <- label
  out <- aggregate_to(df, label, frequency)

  # A quarter whose months were all missing averages to NaN rather than
  # dropping out, and a NaN reaching the panel would be written to the CSV
  # as a value rather than as a gap.
  out[[label]][is.nan(out[[label]])] <- NA_real_
  out <- out[!is.na(out[[label]]), ]

  # Clipped like every other fetcher, so that one long series cannot
  # decide where the panel starts -- see fetch_oil_price() in
  # R/commodities.R and fetch_geopolitical_risk() in R/gpr.R.
  out <- out[out$date >= period_to_date(start_period), ]

  if (nrow(out) == 0) {
    warning(sprintf("[%s] %s returned no usable observations", label, fred_id))
    return(NULL)
  }

  attr(out, "source_col") <- fred_id
  out
}
