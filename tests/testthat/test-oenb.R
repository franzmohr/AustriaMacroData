## Fixture: the shape of a real OeNB data-service response, confirmed live
## on 2026-10-03 (data set 100140002, VDBMSKNWOHNBAU), values as published.
## 2026-Q3 is incomplete (July and August only).
oenb_fixture <- paste(
  '<OeNBData>',
  '  <data>',
  '    <dataSet pos="VDBMSKNWOHNBAU" posTitle="New loans (excl revolving loans) for housing purposes" attr1="AT" freq="M" unitMult="6" unitText="in millions Euro">',
  '      <values>',
  '        <obs value="1873" periode="2026-04"/>',
  '        <obs value="1699" periode="2026-05"/>',
  '        <obs value="2107" periode="2026-06"/>',
  '        <obs value="1321" periode="2026-07"/>',
  '        <obs value="1218" periode="2026-08"/>',
  '      </values>',
  '    </dataSet>',
  '  </data>',
  '</OeNBData>',
  sep = "\n"
)
oenb_empty_fixture <- "<OeNBData>\n  <data/>\n</OeNBData>"

test_that("fetch_oenb_series requests the data set and position of the concept", {
  captured_url <- NULL
  mock <- function(url, ...) { captured_url <<- url; oenb_fixture }
  with_mock_fetch_text(mock, fetch_oenb_series("AUT", "mortgage_new_lending_oenb", frequency = "M"))
  expect_match(captured_url, "isadataservice/data?lang=EN&hierid=100140002&pos=VDBMSKNWOHNBAU&freq=M", fixed = TRUE)
  with_mock_fetch_text(mock, fetch_oenb_series("AUT", "mortgage_rate_oenb", frequency = "M"))
  expect_match(captured_url, "hierid=23&pos=VDBZSBSZN10010", fixed = TRUE)
})

test_that("fetch_oenb_series keeps every month in a monthly panel", {
  with_mock_fetch_text(const_fetch_text(oenb_fixture), {
    out <- fetch_oenb_series("AUT", "mortgage_new_lending_oenb", start_period = "2026-M01", frequency = "M")
  })
  expect_equal(names(out), c("date", "mortgage_new_lending_oenb"))
  expect_equal(out$date, seq(as.Date("2026-04-01"), as.Date("2026-08-01"), by = "month"))
  expect_equal(out$mortgage_new_lending_oenb, c(1873, 1699, 2107, 1321, 1218))
})

test_that("fetch_oenb_series SUMS complete quarters of the flow and averages the rate", {
  with_mock_fetch_text(const_fetch_text(oenb_fixture), {
    flow <- fetch_oenb_series("AUT", "mortgage_new_lending_oenb", start_period = "2026-Q1")
    rate <- fetch_oenb_series("AUT", "mortgage_rate_oenb", start_period = "2026-Q1")
  })
  expect_equal(flow$date, as.Date("2026-04-01"))
  expect_equal(flow$mortgage_new_lending_oenb, 1873 + 1699 + 2107)
  expect_equal(rate$mortgage_rate_oenb[rate$date == as.Date("2026-04-01")], mean(c(1873, 1699, 2107)))
})

test_that("fetch_oenb_series skips every country but Austria without a request", {
  called <- FALSE
  mock <- function(url, ...) { called <<- TRUE; oenb_fixture }
  with_mock_fetch_text(mock, out <- fetch_oenb_series("DEU", "mortgage_new_lending_oenb"))
  expect_null(out)
  expect_false(called)
})

test_that("fetch_oenb_series warns and returns NULL on a failed or empty response", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(a <- fetch_oenb_series("AUT", "mortgage_rate_oenb"), "fetch failed")
  })
  with_mock_fetch_text(const_fetch_text(oenb_empty_fixture), {
    expect_warning(b <- fetch_oenb_series("AUT", "mortgage_rate_oenb"), "no new-business rate")
  })
  expect_null(a); expect_null(b)
})

test_that("oenb_key gives the data set and position for the source registry", {
  expect_equal(oenb_key("mortgage_new_lending_oenb"), "100140002/VDBMSKNWOHNBAU")
  expect_equal(oenb_key("mortgage_rate_oenb"), "23/VDBZSBSZN10010")
})
