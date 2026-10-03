## safe_get()'s retry of transient failures (R/utils.R). httr::GET is
## replaced for the duration of each test, so no request leaves the machine.

with_mock_get <- function(responses, code) {
  calls <- 0L
  mock <- function(url, ...) {
    calls <<- calls + 1L
    r <- responses[[min(calls, length(responses))]]
    if (inherits(r, "error")) stop(r)
    structure(list(status_code = r, url = url, headers = list(), content = charToRaw("ok")),
              class = "response")
  }
  old <- options(austriamacrodata.retry_pause = 0)
  on.exit(options(old), add = TRUE)
  testthat::local_mocked_bindings(GET = mock, .package = "httr")
  force(code)
  calls
}

test_that("a 504 followed by a 200 is retried and succeeds", {
  out <- NULL
  calls <- with_mock_get(list(504L, 200L), out <- safe_get("https://example.org/x"))
  expect_equal(calls, 2L)
  expect_equal(httr::status_code(out), 200L)
})

test_that("a timeout is retried", {
  out <- NULL
  calls <- with_mock_get(list(simpleError("Timeout was reached"), 200L),
                         out <- safe_get("https://example.org/x"))
  expect_equal(calls, 2L)
  expect_false(is.null(out))
})

test_that("a 404 is not retried, since asking again cannot help", {
  calls <- with_mock_get(list(404L, 200L),
                         expect_warning(out <- safe_get("https://example.org/x"), "HTTP 404"))
  expect_equal(calls, 1L)
})

test_that("a persistent 503 gives up after the last attempt with a warning", {
  calls <- with_mock_get(list(503L), expect_warning(out <- safe_get("https://example.org/x", attempts = 3), "HTTP 503"))
  expect_equal(calls, 3L)
})
