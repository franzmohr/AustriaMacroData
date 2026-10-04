## The semantic layer over the output panels (R/semantic_layer.R). No
## network involved: the query tests run against a toy output directory.

test_that("every concept has exactly one semantics row, and nothing else does", {
  expect_setequal(concept_semantics$label, concept_dictionary$label)
  expect_equal(anyDuplicated(concept_semantics$label), 0L)
  expect_false(anyNA(concept_semantics))
  expect_true(all(nzchar(concept_semantics$title)))
  expect_true(all(nzchar(concept_semantics$synonyms)))
  expect_equal(anyDuplicated(concept_semantics$title), 0L)
  expect_true(all(concept_semantics$scope %in% c("country", "euro_area", "world")))
})

test_that("the concepts that are the same figure in every panel say so", {
  scope <- function(lbl) concept_semantics$scope[concept_semantics$label == lbl]
  expect_equal(scope("oil_price"), "world")
  expect_equal(scope("global_activity"), "world")
  expect_equal(scope("euro_area_household_net_worth_growth"), "euro_area")
})

test_that("every derived metric parses and rests on concepts that exist", {
  expect_equal(anyDuplicated(derived_metrics$name), 0L)
  expect_length(intersect(derived_metrics$name, concept_dictionary$label), 0)
  expect_false(anyNA(derived_metrics))
  for (m in derived_metrics$name) {
    expect_true(all(metric_inputs(m) %in% concept_dictionary$label), info = m)
    expect_true(all(metric_frequencies(m) %in% c("M", "Q")), info = m)
  }
  # A metric may use one defined ABOVE it, never below: amd_get()
  # evaluates them in table order.
  for (i in seq_len(nrow(derived_metrics))) {
    used <- all.vars(parse(text = derived_metrics$formula[i])[[1]])
    later <- derived_metrics$name[-seq_len(i)]
    expect_length(intersect(used, later), 0)
  }
})

test_that("a metric on a quarterly concept exists only quarterly", {
  expect_equal(metric_frequencies("inflation_yoy"), c("M", "Q"))
  expect_equal(metric_frequencies("real_gdp_growth_yoy"), "Q")
  expect_setequal(metric_inputs("real_short_rate"), c("short_term_rate", "cpi_index"))
})

test_that("transforms shift by periods and follow the FRED and EA-MD-QD codes", {
  x <- c(100, 110, 121)
  expect_equal(transform_series(x, "pct_change", 4), c(NA, 10, 10))
  expect_equal(transform_series(x, "diff", 4), c(NA, 10, 11))
  expect_equal(transform_series(x, "saar", 4), c(NA, 100 * (1.1^4 - 1), 100 * (1.1^4 - 1)))
  expect_equal(transform_series(1:13 + 0, "yoy", 12)[13], 100 * (13 / 1 - 1))
  codes <- list(tcode_fred = 5L, tcode_lt = 2L, tcode_ht = 3L)
  expect_equal(transform_series(x, "tcode_fred", 4, codes), c(NA, log(1.1), log(1.1)))
  expect_equal(transform_series(x, "tcode_lt", 4, codes), c(NA, 100 * log(1.1), 100 * log(1.1)))
  expect_equal(transform_series(x, "tcode_ht", 4, codes), c(NA, NA, 0))
  expect_error(transform_series(x, "tcode_fred", 4, NULL), "derived metrics")
  expect_error(transform_series(x, "nonsense", 4), "Unknown transform")
})

## A toy output directory: one country, a monthly CPI and rate, a
## quarterly GDP, with one month missing from the monthly file to check
## that lags count periods, not rows.
make_toy_output <- function() {
  dir <- tempfile("semantic_out")
  dir.create(dir)
  months <- seq(as.Date("2024-01-01"), as.Date("2025-12-01"), by = "month")
  cpi <- 100 * 1.002^(seq_along(months) - 1)
  monthly <- tibble::tibble(date = months, cpi_index = cpi, short_term_rate = 3, long_term_rate = 4)
  monthly <- monthly[monthly$date != as.Date("2025-03-01"), ]
  readr::write_csv(monthly, file.path(dir, "xxx_monthly_panel.csv"))
  quarters <- seq(as.Date("2024-01-01"), as.Date("2025-10-01"), by = "3 months")
  quarterly <- tibble::tibble(date = quarters, real_gdp = 1000 * 1.01^(seq_along(quarters) - 1),
                              population = 9000, cpi_index = NA_real_)
  readr::write_csv(quarterly, file.path(dir, "xxx_panel.csv"))
  readr::write_csv(tibble::tibble(
    label = c("cpi_index", "real_gdp", "population", "short_term_rate", "long_term_rate", "hours_worked"),
    frequency = c("M", "Q", "Q", "M", "M", "Q"),
    unit = c("index 2025=100", "EUR mn, chain-linked volume (2020), quarterly level", "thousand persons",
             "% p.a.", "% p.a.", "thousand hours"),
    provider = c("EUROSTAT", "EUROSTAT", "EUROSTAT", "ECB", "ECB", NA),
    key = c("k1", "k2", "k3", "k4", "k5", NA),
    first = c("2024-M01", "2024-Q1", "2024-Q1", "2024-M01", "2024-M01", NA),
    last = c("2025-M12", "2025-Q4", "2025-Q4", "2025-M12", "2025-M12", NA),
    n_obs = c(23, 8, 8, 23, 23, 0)
  ), file.path(dir, "xxx_metadata.csv"), na = "")
  dir
}

test_that("amd_get computes a year-on-year rate across a missing month", {
  dir <- make_toy_output()
  out <- amd_get("inflation_yoy", countries = "XXX", frequency = "M", from = "2025-M01", output_dir = dir)
  expect_equal(unique(out$series), "inflation_yoy")
  expect_equal(out$period[1], "2025-M01")
  # The first month kept still has its lag, from before `from`.
  expect_equal(out$value[1], 100 * (1.002^12 - 1))
  # The missing month is a row of NA, and the month after it is still
  # compared with the same month a year earlier, not with a row 12 back.
  expect_true(is.na(out$value[out$period == "2025-M03"]))
  expect_equal(out$value[out$period == "2025-M04"], 100 * (1.002^12 - 1))
})

test_that("amd_get warns when a monthly concept is quarterly-only for a country", {
  dir <- make_toy_output()
  md_path <- file.path(dir, "xxx_metadata.csv")
  md <- readr::read_csv(md_path, col_types = readr::cols(.default = "c"))
  md$frequency[md$label == "cpi_index"] <- "Q"
  readr::write_csv(md, md_path, na = "")
  expect_warning(amd_get("inflation_yoy", countries = "XXX", frequency = "M", output_dir = dir),
                 "XXX cpi_index.*frequency = 'Q'")
  expect_no_warning(amd_get("term_spread", countries = "XXX", frequency = "M", output_dir = dir))
})

test_that("amd_get evaluates metrics that rest on other metrics", {
  dir <- make_toy_output()
  out <- amd_get(c("real_short_rate", "term_spread"), countries = "XXX", frequency = "M",
                 from = "2025-01", to = "2025-02", output_dir = dir)
  expect_equal(out$value[out$series == "term_spread"], c(1, 1))
  expect_equal(out$value[out$series == "real_short_rate"], rep(3 - 100 * (1.002^12 - 1), 2))
})

test_that("amd_get names transformed columns in wide output", {
  dir <- make_toy_output()
  out <- amd_get("real_gdp", countries = "XXX", transform = "yoy", from = "2025", format = "wide",
                 output_dir = dir)
  expect_named(out, c("date", "period", "xxx_real_gdp__yoy"))
  expect_equal(out$xxx_real_gdp__yoy[1], 100 * (1.01^4 - 1))
})

test_that("amd_get refuses to guess a name or to interpolate a quarterly concept", {
  dir <- make_toy_output()
  expect_error(amd_get("inflation", countries = "XXX", output_dir = dir), "Did you mean.*inflation_yoy")
  expect_error(amd_get("real_gdp", countries = "XXX", frequency = "M", output_dir = dir), "never interpolated")
  expect_error(amd_get("real_gdp_growth_yoy", countries = "XXX", frequency = "M", output_dir = dir),
               "never interpolated")
  expect_error(amd_get("real_gdp", countries = "XXX", from = "last year", output_dir = dir), "Cannot read")
})

test_that("amd_search puts the obvious answer first", {
  top <- function(q) amd_search(q, n = 1)$name
  expect_equal(top("inflation"), "inflation_yoy")
  expect_equal(top("euribor"), "short_term_rate")
  expect_equal(top("GDPC1"), "real_gdp")
  expect_equal(top("real_gdp"), "real_gdp")
  expect_equal(top("house prices"), "house_price_real")
  expect_equal(top("yield curve"), "term_spread")
  expect_equal(nrow(amd_search("zzzz qqqq")), 0L)
})

test_that("write_semantic_layer writes a catalog that covers every concept", {
  dir <- make_toy_output()
  write_semantic_layer(dir)
  catalog <- jsonlite::fromJSON(file.path(dir, "semantic", "catalog.json"), simplifyVector = FALSE)
  expect_equal(length(catalog$concepts), nrow(concept_dictionary))
  expect_equal(length(catalog$derived_metrics), nrow(derived_metrics))
  expect_equal(catalog$countries[[1]]$code, "XXX")
  expect_equal(catalog$countries[[1]]$n_resolved, 5L)
  # Paths in the catalog are relative to the project, not this machine.
  expect_equal(catalog$countries[[1]]$files$quarterly_panel, "output/xxx_panel.csv")
  gdp <- Filter(function(c) c$label == "real_gdp", catalog$concepts)[[1]]
  expect_equal(gdp$availability[[1]]$provider, "EUROSTAT")
  expect_equal(gdp$availability[[1]]$unit, "EUR mn, chain-linked volume (2020), quarterly level")
  expect_true("gdp" %in% unlist(gdp$synonyms))

  avail <- readr::read_csv(file.path(dir, "semantic", "availability.csv"), show_col_types = FALSE)
  expect_equal(sum(!avail$resolved), 1L)
  concepts <- readr::read_csv(file.path(dir, "semantic", "concepts.csv"), show_col_types = FALSE)
  expect_equal(nrow(concepts), nrow(concept_dictionary))
})
