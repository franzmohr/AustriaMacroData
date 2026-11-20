#!/usr/bin/env Rscript
## ---------------------------------------------------------------
## uncertainty_gdp_memo.R -- reproduces the regressions behind the memo
## "Survey Uncertainty and GDP Growth".
##
## THE QUESTION: the EC Business and Consumer Survey now asks firms and
## households how hard they find it to PREDICT their situation, next to
## the long-standing questions about how they JUDGE it. Both answers are
## available for the same respondents in the same month, and they move
## together closely (within-country correlation -0.69 on this sample).
## Does the uncertainty question carry any information about real
## activity that the confidence indicators do not already carry?
##
## THE ANSWER, AND WHY THE HORIZON IS THE WHOLE STORY:
##   - SAME quarter: no. Adding uncertainty to confidence moves R^2 from
##     0.372 to 0.375; the incremental F is 0.17 (p = 0.68).
##   - ONE quarter ahead: yes, and the ordering reverses. Lagged
##     uncertainty alone explains 0.384 against 0.234 for lagged
##     confidence, and in the joint model uncertainty keeps its
##     coefficient (t = -3.00) while confidence loses its (t = 0.42);
##     the incremental F is 8.97 (p = 0.005).
## So "uncertainty adds nothing" is a true statement about NOWCASTING
## and a false one about FORECASTING, on this sample.
##
## WHAT THIS SCRIPT NEEDS: dplyr, readr and readxl on the library path
## (this project dropped renv in commit 7c8468b, so there is no lockfile
## to restore any more -- install them however you normally would), plus
## output/aut_panel.csv and output/deu_panel.csv, which must already have
## been built by scripts/build_panels.R. The uncertainty side is fetched
## live via R/ec_survey.R's fetch_ec_uncertainty_indicator() and cached in
## data/landing/ like every other EC survey archive.
##
## RUN IT WITH --vanilla. The tracked .Rprofile still does
## source("renv/activate.R"), and that file was deleted with renv, so a
## plain `Rscript` aborts at startup in this directory (AGENTS.md
## documents the same workaround for scripts/query.R).
##
## ONE SPECIFICATION CHOICE WORTH KNOWING ABOUT: the confidence side is
## read from the panels, where it is SEASONALLY ADJUSTED at source; the
## uncertainty archive is published non-seasonally-adjusted only (see
## R/ec_survey.R's uncertainty section). Austria shows no detectable
## seasonality in the raw uncertainty series, so the mismatch does not
## drive anything here, but it is the first thing to vary if these
## numbers ever need defending.
##
##   Rscript --vanilla scripts/uncertainty_gdp_memo.R
## ---------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
})

for (f in list.files("R", full.names = TRUE, pattern = "\\.R$")) source(f)

countries    <- c(AT = "AUT", DE = "DEU")
surveys      <- c("INDU", "SERV", "CONS", "RETA", "BUIL")
start_period <- "2019-Q1"

## Confidence indicators already in the panel, one per survey, in the
## same order as `surveys` -- the confidence counterpart of exactly the
## five uncertainty balances fetched below, so the two composites average
## the same five surveys and nothing else.
confidence_cols <- c("industrial_confidence", "services_confidence",
                     "consumer_confidence", "retail_confidence",
                     "construction_confidence")

## ---------------------------------------------------------------
## 1. Uncertainty: five survey balances per country, quarterly
## ---------------------------------------------------------------
fetch_country_uncertainty <- function(cc2, country3) {
  per_survey <- lapply(surveys, function(s) {
    df <- fetch_ec_uncertainty_indicator(country3, label = "unc", survey = s,
                                         start_period = start_period)
    if (is.null(df)) return(NULL)
    df$survey <- s
    df
  })
  per_survey <- Filter(Negate(is.null), per_survey)
  if (length(per_survey) == 0) {
    stop("No uncertainty series resolved for ", country3, call. = FALSE)
  }
  bind_rows(per_survey) %>%
    group_by(.data$date) %>%
    ## `n_surveys` is kept so the sample can require ALL FIVE surveys:
    ## the question entered the surveys at different dates in different
    ## countries, and a composite silently averaging three surveys in
    ## one quarter and five in the next is not the same variable.
    summarise(unc = mean(.data$unc), n_surveys = dplyr::n(), .groups = "drop") %>%
    mutate(country = cc2)
}

message("Fetching EC uncertainty balances...")
uncertainty <- bind_rows(lapply(names(countries), function(cc2)
  fetch_country_uncertainty(cc2, countries[[cc2]])))

## ---------------------------------------------------------------
## 2. GDP growth and confidence: the project's own quarterly panels
## ---------------------------------------------------------------
read_panel <- function(cc2) {
  path <- file.path("output", paste0(tolower(countries[[cc2]]), "_panel.csv"))
  if (!file.exists(path)) {
    stop(path, " not found -- run Rscript --vanilla scripts/build_panels.R --country ",
         countries[[cc2]], " first", call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE) %>%
    arrange(.data$date) %>%
    transmute(
      country = cc2,
      date    = .data$date,
      ## q/q log growth in percent; real_gdp is a chain-linked volume level
      g       = c(NA_real_, 100 * diff(log(.data$real_gdp))),
      ## rowMeans with na.rm = FALSE on purpose: a quarter missing any one
      ## confidence indicator drops out, matching the all-five rule above
      cof     = rowMeans(across(all_of(confidence_cols)), na.rm = FALSE)
    )
}

panels <- bind_rows(lapply(names(countries), read_panel))

## ---------------------------------------------------------------
## 3. The estimation sample
## ---------------------------------------------------------------
d <- uncertainty %>%
  inner_join(panels, by = c("country", "date")) %>%
  filter(.data$n_surveys == length(surveys),
         !is.na(.data$g), !is.na(.data$unc), !is.na(.data$cof)) %>%
  arrange(.data$country, .data$date)

## Lag by CALENDAR QUARTER, never by row position. Germany has one
## isolated early quarter (2019-Q2) before its sample proper begins in
## 2021-Q2; a positional lag would hand 2021-Q2 the uncertainty reading
## from two years earlier and call it "last quarter".
d <- d %>%
  mutate(qi = as.integer(format(.data$date, "%Y")) * 4 +
              (as.integer(format(.data$date, "%m")) - 1) %/% 3)
prev <- match(paste(d$country, d$qi - 1), paste(d$country, d$qi))
d$unc_lag <- ifelse(is.na(prev), NA_real_, d$unc[prev])
d$cof_lag <- ifelse(is.na(prev), NA_real_, d$cof[prev])

message(sprintf("Sample: %d country-quarters (%s)", nrow(d),
                paste(sprintf("%s %d", names(countries),
                              tapply(d$g, d$country, length)[names(countries)]),
                      collapse = ", ")))
message(sprintf("Correlation of confidence and uncertainty: %.3f overall, %.3f within country",
                cor(d$cof, d$unc),
                cor(d$cof - ave(d$cof, d$country), d$unc - ave(d$unc, d$country))))

## ---------------------------------------------------------------
## 4. Three nested specifications, at two horizons
## ---------------------------------------------------------------
## Both regressors are standardised over the estimation sample so the
## coefficients are directly comparable to each other; country fixed
## effects absorb the two countries' different mean growth rates.
estimate <- function(dat, u, c_, label) {
  dat <- dat[complete.cases(dat$g, dat[[u]], dat[[c_]]), ]
  dat$U <- as.numeric(scale(dat[[u]]))
  dat$C <- as.numeric(scale(dat[[c_]]))

  fits <- list(
    `confidence only`  = lm(g ~ factor(country) + C, dat),
    `uncertainty only` = lm(g ~ factor(country) + U, dat),
    `both`             = lm(g ~ factor(country) + C + U, dat)
  )
  incr <- anova(fits[["confidence only"]], fits[["both"]])

  cat(sprintf("\n=== %s (n = %d) ===\n", label, nrow(dat)))
  cat(sprintf("%-18s %18s %18s %8s %9s\n",
              "specification", "confidence", "uncertainty", "R2", "adj. R2"))
  for (nm in names(fits)) {
    co <- summary(fits[[nm]])$coefficients
    f <- function(v) if (v %in% rownames(co))
      sprintf("%6.2f (t=%5.2f)", co[v, 1], co[v, 3]) else "        --        "
    cat(sprintf("%-18s %18s %18s %8.3f %9.3f\n", nm, f("C"), f("U"),
                summary(fits[[nm]])$r.squared, summary(fits[[nm]])$adj.r.squared))
  }
  cat(sprintf("adding uncertainty to confidence: F(%d, %d) = %.2f, p = %.3f\n",
              incr$Df[2], fits[["both"]]$df.residual, incr$F[2], incr$`Pr(>F)`[2]))
  invisible(fits)
}

estimate(d, "unc", "cof", "Same quarter")
estimate(d, "unc_lag", "cof_lag", "One quarter ahead")

## ---------------------------------------------------------------
## 5. Does the one-quarter-ahead result survive the obvious objections?
## ---------------------------------------------------------------
## The window is short and contains one dominant episode, so the result
## is worth only as much as its robustness checks. Each line re-estimates
## the joint lagged model on a different subset.
cat("\n=== One quarter ahead: robustness ===\n")
cat(sprintf("%-28s %4s %18s %18s %8s %8s\n",
            "subset", "n", "confidence", "uncertainty", "R2", "incr. p"))
robust <- function(label, dat) {
  dat <- dat[complete.cases(dat$g, dat$unc_lag, dat$cof_lag), ]
  if (nrow(dat) < 12) { cat(sprintf("%-28s %4d  too few observations\n", label, nrow(dat))); return(invisible()) }
  dat$U <- as.numeric(scale(dat$unc_lag))
  dat$C <- as.numeric(scale(dat$cof_lag))
  fe <- length(unique(dat$country)) > 1
  rhs <- if (fe) "factor(country) + " else ""
  f1 <- lm(as.formula(paste0("g ~ ", rhs, "C")), dat)
  f3 <- lm(as.formula(paste0("g ~ ", rhs, "C + U")), dat)
  co <- summary(f3)$coefficients
  incr <- anova(f1, f3)
  cat(sprintf("%-28s %4d %18s %18s %8.3f %8.3f\n", label, nrow(dat),
              sprintf("%6.2f (t=%5.2f)", co["C", 1], co["C", 3]),
              sprintf("%6.2f (t=%5.2f)", co["U", 1], co["U", 3]),
              summary(f3)$r.squared, incr$`Pr(>F)`[2]))
}
robust("all quarters",            d)
robust("excl. 2022",              filter(d, format(.data$date, "%Y") != "2022"))
robust("excl. |growth| > 3%",     filter(d, abs(.data$g) <= 3))
robust("Austria only",            filter(d, .data$country == "AT"))
robust("Germany only",            filter(d, .data$country == "DE"))

cat("\nSee docs/ and the memo for how to read these.\n")
