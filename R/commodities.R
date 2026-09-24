## ---------------------------------------------------------------
## commodities.R -- world commodity prices
##
## Unlike every other source module here, what this fetches is not a
## country's own statistic. A barrel of crude has one world price, so the
## series is identical in every country's panel, the way
## R/gpr.R's global fallback index is for countries the Caldara-Iacoviello
## source does not cover separately. It earns a place in a national panel
## anyway: for a small open economy the world oil price is the classic
## exogenous supply shifter, and a VAR that wants to say anything about
## imported inflation needs it in the system rather than assumed away.
##
## SOURCE CHOICE. FRED carries three candidates and they are not
## interchangeable:
##
##   WTISPLC        Spot Crude Oil Price: West Texas Intermediate,
##                  USD/barrel, monthly, 1946-01 onwards. The longest
##                  history of the three, and the benchmark the
##                  high-frequency geopolitical-risk literature prices
##                  its event windows against.
##   POILBREUSDM    IMF Global price of Brent Crude, USD/barrel, monthly,
##                  1990-01 onwards. The better "world" concept -- Brent
##                  is the marker for roughly two-thirds of internationally
##                  traded crude and for European refiners in particular --
##                  but it starts 44 years later.
##   DCOILWTICO     Daily WTI, Cushing. Same concept as WTISPLC at a
##                  frequency this panel has no use for.
##
## WTISPLC is used, for its history: a quarterly panel that begins in 1955
## should not acquire a concept that cannot start before 1990. Brent is
## available by passing `fred_id = "POILBREUSDM"`, and the two are within
## a few dollars of each other for most of their overlap -- the notable
## exception being 2011-2014, when the US shale glut and the Cushing
## bottleneck opened a WTI discount of up to 25 dollars.
##
## The series is nominal and in US dollars. It is left that way rather
## than deflated or converted, because which deflator and which exchange
## rate belong in front of it is the user's modelling decision, and the
## panel already carries `cpi_index` and `fx_rate_to_usd` to make either.
## ---------------------------------------------------------------

oil_price_fred_id <- "WTISPLC"

#' Fetch the world crude oil price as a quarterly series
#'
#' Monthly observations averaged within the quarter, which is what
#' R/fred_mirror.R does for every other monthly FRED source here.
#'
#' The `country3` argument is accepted and ignored: it exists so that the
#' builder can call this the way it calls every other concept fetcher,
#' and so that the signature keeps its shape if a country-specific import
#' price ever replaces the world price for some panel.
fetch_oil_price <- function(country3 = NULL, label = "oil_price",
                            start_period = "1960-Q1",
                            fred_id = oil_price_fred_id) {
  df <- get_fred_series(fred_id)
  if (is.null(df)) {
    warning(sprintf("[%s] FRED fetch failed for %s", label, fred_id))
    return(NULL)
  }

  names(df)[2] <- label
  out <- monthly_to_quarterly(df, label)

  # A quarter whose months were all missing averages to NaN rather than
  # dropping out, and a NaN reaching the panel would be written to the CSV
  # as a value rather than as a gap.
  out[[label]][is.nan(out[[label]])] <- NA_real_
  out <- out[!is.na(out[[label]]), ]

  # WTISPLC begins in 1946, earlier than any other concept here and
  # earlier than the builder's default start. Clipped like every other
  # fetcher, so that one long series cannot decide where the panel
  # starts -- see fetch_geopolitical_risk() in R/gpr.R, which does the
  # same for the same reason.
  out <- out[out$date >= period_to_date(start_period), ]

  if (nrow(out) == 0) {
    warning(sprintf("[%s] %s returned no usable observations", label, fred_id))
    return(NULL)
  }

  attr(out, "source_col") <- fred_id
  out
}
