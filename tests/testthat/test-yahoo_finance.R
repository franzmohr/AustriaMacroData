## Fixture mirrors the real shape confirmed live against Yahoo Finance's
## /v8/finance/chart/ endpoint on 2026-08-30 for ticker "^ATX"
## (range=max&interval=1mo): timestamps in epoch seconds, close prices
## under indicators.quote[[1]].close, aligned by position.
yahoo_atx_fixture <- jsonlite::toJSON(list(
  chart = list(
    result = list(list(
      meta = list(currency = "EUR", symbol = "^ATX", exchangeName = "VIE"),
      timestamp = list(1735689600, 1738368000, 1740787200),
      indicators = list(quote = list(list(
        close = list(5613.4, 5900.1, 6100.2)
      )))
    )),
    error = NULL
  )
), auto_unbox = TRUE, null = "null")

yahoo_error_fixture <- jsonlite::toJSON(list(
  chart = list(result = NULL, error = list(code = "Not Found", description = "No data found, symbol may be delisted"))
), auto_unbox = TRUE, null = "null")

test_that("fetch_yahoo_finance_monthly parses a successful response into date/value", {
  with_mock_fetch_text(const_fetch_text(yahoo_atx_fixture), {
    out <- fetch_yahoo_finance_monthly("^ATX", "share_price_index")
  })
  expect_equal(names(out), c("date", "share_price_index"))
  expect_equal(out$share_price_index, c(5613.4, 5900.1, 6100.2))
  expect_true(all(format(out$date, "%d") == "01"))
})

test_that("fetch_yahoo_finance_monthly sends a browser-like User-Agent (default httr/curl UA gets HTTP 429 live)", {
  captured_headers <- NULL
  with_mock_fetch_text(function(url, ...) {
    args <- list(...)
    captured_headers <<- args
    yahoo_atx_fixture
  }, {
    fetch_yahoo_finance_monthly("^ATX", "share_price_index")
  })
  expect_true(length(captured_headers) > 0)
})

test_that("fetch_yahoo_finance_monthly warns and returns NULL when Yahoo reports an error", {
  with_mock_fetch_text(const_fetch_text(yahoo_error_fixture), {
    expect_warning(out <- fetch_yahoo_finance_monthly("^BOGUS", "share_price_index"), "no result")
  })
  expect_null(out)
})

test_that("fetch_yahoo_finance_monthly warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_yahoo_finance_monthly("^ATX", "share_price_index"), "Yahoo Finance fetch failed")
  })
  expect_null(out)
})

test_that("fetch_atx_quarterly averages monthly closes into quarters and filters by start_period", {
  with_mock_fetch_text(const_fetch_text(yahoo_atx_fixture), {
    out <- fetch_atx_quarterly(start_period = "1995-Q1")
  })
  expect_equal(names(out), c("date", "share_price_index"))
  ## all 3 fixture months (2025-01, 2025-02, 2025-03) fall in 2025-Q1
  expect_equal(nrow(out), 1)
  expect_equal(out$date, as.Date("2025-01-01"))
  expect_equal(out$share_price_index, mean(c(5613.4, 5900.1, 6100.2)))
})
