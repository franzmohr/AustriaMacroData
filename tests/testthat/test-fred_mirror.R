fred_quarterly_fixture <- paste(
  "observation_date,IRLTLT01DEQ156N",
  "2020-01-01,-0.19",
  "2020-04-01,-0.34",
  sep = "\n"
)

fred_monthly_fixture <- paste(
  "observation_date,CSCICP03DEM665S",
  "2020-01-01,100.1",
  "2020-02-01,99.8",
  "2020-03-01,98.2",
  "2020-04-01,95.0",
  sep = "\n"
)

fred_not_found_fixture <- "<!DOCTYPE html><html><head></head><body>Bad Request</body></html>"

test_that("get_fred_series parses a real fredgraph.csv response", {
  with_mock_fetch_text(const_fetch_text(fred_quarterly_fixture), {
    out <- get_fred_series("IRLTLT01DEQ156N")
  })
  expect_equal(names(out), c("date", "IRLTLT01DEQ156N"))
  expect_equal(out$IRLTLT01DEQ156N, c(-0.19, -0.34))
  expect_s3_class(out$date, "Date")
})

test_that("get_fred_series returns NULL for an unknown mnemonic (FRED serves an HTML 404 page)", {
  with_mock_fetch_text(const_fetch_text(fred_not_found_fixture), {
    out <- get_fred_series("NOT_A_REAL_SERIES_ID")
  })
  expect_null(out)
})

test_that("monthly_to_quarterly averages 3 months into one quarterly observation", {
  df <- get_fred_series <- NULL
  with_mock_fetch_text(const_fetch_text(fred_monthly_fixture), {
    raw <- get_fred_series("CSCICP03DEM665S")
  })
  out <- monthly_to_quarterly(raw, "CSCICP03DEM665S")
  expect_equal(nrow(out), 2)
  expect_equal(out$date, as.Date(c("2020-01-01", "2020-04-01")))
  expect_equal(out$CSCICP03DEM665S[1], mean(c(100.1, 99.8, 98.2)))
  expect_equal(out$CSCICP03DEM665S[2], 95.0)
})

test_that("fetch_other_group_series substitutes {cc2} and {cc3} placeholders correctly", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; fred_quarterly_fixture }
  with_mock_fetch_text(mock, {
    fetch_other_group_series("IRLTLT01{cc2}Q156N", "Q", "DE", "DEU", "long_term_rate",
                              "Interest Rates", "OECD MEI (via FRED)")
  })
  expect_match(captured_url, "IRLTLT01DEQ156N", fixed = TRUE)
})

test_that("fetch_other_group_series applies monthly-to-quarterly aggregation only when frequency is M", {
  with_mock_fetch_text(const_fetch_text(fred_monthly_fixture), {
    out <- fetch_other_group_series("CSCICP03{cc2}M665S", "M", "DE", "DEU", "consumer_confidence",
                                     "Other", "OECD MEI (via FRED)")
  })
  expect_equal(nrow(out), 2)
  expect_equal(names(out), c("date", "consumer_confidence"))
})

test_that("fetch_other_group_series warns with a search URL when a mnemonic 404s", {
  with_mock_fetch_text(const_fetch_text(fred_not_found_fixture), {
    expect_warning(
      out <- fetch_other_group_series("USASARTQISMEI", "Q", "US", "USA", "retail_sales_volume",
                                       "Inventories, Orders, and Sales", "OECD MEI (via FRED)"),
      "fred.stlouisfed.org/search"
    )
  })
  expect_null(out)
})

test_that("other_groups table has one row per FRED-QD group it targets, each with an id_template placeholder", {
  expect_true(all(grepl("\\{cc2\\}|\\{cc3\\}", other_groups$id_template)))
  expect_true(all(other_groups$frequency %in% c("Q", "M")))
})
