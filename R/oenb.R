## ---------------------------------------------------------------
## oenb.R -- Austrian series from the OeNB's own data service
##
## The Oesterreichische Nationalbank publishes its statistics through a
## web data service (https://www.oenb.at/isadataservice), the same one
## the `oenb` R package (github.com/franzmohr/oenb) wraps. The request
## here is the one that package's oenb_data() builds -- a data set
## ("hierid"), a position code ("pos") and a frequency -- but it goes
## through fetch_text() like every other request in this project, so the
## tests can stub it and no further package is needed. The response is a
## small XML document:
##
##   <OeNBData><data><dataSet pos="..." unitMult="6" ...>
##     <values><obs value="518" periode="2009-01"/> ...
##
## Two series, both Austria only:
##
##   mortgage_new_lending_oenb  data set 100140002, VDBMSKNWOHNBAU:
##       new loans (excluding revolving loans) to households for housing
##       purposes, EUR millions per month, from 2009-01. The OeNB's
##       monthly statistics, not the MIR sample: same concept as the ECB's
##       pure new loans (mortgage_new_lending), and over their overlap
##       since 2014-12 the monthly changes of the two correlate at 0.994,
##       but eight years longer.
##   mortgage_rate_oenb  data set 23, VDBZSBSZN10010: interest rate on
##       new business in loans to households for housing purposes, % p.a.,
##       from 1995-12. Over 2000-01 to date it is the ECB's mortgage_rate
##       (MIR A2C.R.A.2250.EUR.N) to the last decimal in every month
##       (checked 2026-10-03); the OeNB series adds 1995-12 to 1999-12,
##       which precede the harmonised MIR statistics.
##
## Both verified live on 2026-10-03 (2026-08: EUR 1,218mn; 3.61%).
## ---------------------------------------------------------------

oenb_series <- tibble::tribble(
  ~label,                       ~hierid,     ~pos,             ~aggregate, ~what,
  "mortgage_new_lending_oenb",  "100140002", "VDBMSKNWOHNBAU", "sum",      "new loans for housing purposes",
  "mortgage_rate_oenb",         "23",        "VDBZSBSZN10010", "mean",     "new-business rate on loans for housing purposes"
)

#' The OeNB data-service key of a concept, "<data set>/<position>", as the
#' source registries record it
oenb_key <- function(label) {
  row <- oenb_series[oenb_series$label == label, ]
  paste0(row$hierid, "/", row$pos)
}

#' Parse an OeNB data-service response into date + value
#'
#' Returns NULL when the document holds no observations (the service
#' answers an unknown position with an empty <data/> element, not an
#' HTTP error). Values are taken as published, in the unit the data set
#' states (unitMult is the power of ten of that unit, e.g. 6 for EUR
#' millions, and is NOT applied: the unit text already names it).
parse_oenb_data <- function(txt) {
  obs <- stringr::str_match_all(txt, "<obs\\s+([^>]*)/?>")[[1]][, 2]
  if (length(obs) == 0) return(NULL)
  attr_of <- function(a) stringr::str_match(obs, paste0("\\b", a, "=\"([^\"]*)\""))[, 2]
  tibble::tibble(period = attr_of("periode"), value = suppressWarnings(as.numeric(attr_of("value")))) %>%
    dplyr::filter(stringr::str_detect(.data$period, "^\\d{4}-\\d{2}$"), !is.na(.data$value)) %>%
    dplyr::transmute(date = as.Date(paste0(.data$period, "-01")), value = .data$value) %>%
    dplyr::distinct(.data$date, .keep_all = TRUE) %>%
    dplyr::arrange(.data$date)
}

#' Fetch one of the OeNB series above for Austria
#'
#' Returns NULL without a request for any country but Austria, and NULL
#' with a warning when the request fails or returns nothing. A flow
#' (`aggregate = "sum"`) is summed over complete quarters only, like
#' mortgage_new_lending; a rate is averaged.
fetch_oenb_series <- function(country3, label, start_period = "1995-Q1", frequency = "Q") {
  frequency <- check_frequency(frequency)
  row <- oenb_series[oenb_series$label == label, ]
  if (nrow(row) != 1) stop("Unknown OeNB concept: ", label)
  if (!identical(country3, "AUT")) return(NULL)

  url <- paste0("https://www.oenb.at/isadataservice/data?lang=EN&hierid=", row$hierid,
                "&pos=", row$pos, "&freq=M")
  txt <- fetch_text(url)
  if (is.null(txt)) {
    warning(sprintf("[%s] OeNB %s fetch failed -- verify manually at https://www.oenb.at/isadataservice/data?hierid=%s&pos=%s",
                    label, row$what, row$hierid, row$pos))
    return(NULL)
  }
  monthly <- parse_oenb_data(txt)
  if (is.null(monthly) || nrow(monthly) == 0) {
    warning(sprintf("[%s] OeNB returned no %s observations", label, row$what))
    return(NULL)
  }
  names(monthly)[2] <- label

  out <- if (identical(row$aggregate, "sum") && identical(frequency, "Q")) {
    monthly_to_quarterly_sum(monthly, label)
  } else {
    aggregate_to(monthly, label, frequency)
  }
  out %>% dplyr::filter(.data$date >= period_to_date(start_period))
}
