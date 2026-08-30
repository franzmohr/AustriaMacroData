## Mocking helper for this script-based (non-package) project.
##
## Every network call in R/ goes through the single function
## `fetch_text()` (see R/utils.R). Tests never hit a live API: instead
## they temporarily replace `fetch_text` in the global environment with
## a stub that returns canned text, so the rest of each module's parsing
## logic runs for real against a fixture.
with_mock_fetch_text <- function(mock_fn, code) {
  old <- get("fetch_text", envir = .GlobalEnv)
  assign("fetch_text", mock_fn, envir = .GlobalEnv)
  on.exit(assign("fetch_text", old, envir = .GlobalEnv), add = TRUE)
  force(code)
}

## Convenience: always return the same fixed text regardless of URL/args
const_fetch_text <- function(text) function(url, ...) text

## Convenience: return NULL (simulating a failed request), like the real
## fetch_text() does on a network error or non-2xx status
failing_fetch_text <- function() function(url, ...) NULL

## Same three helpers, for `fetch_binary()` (R/ec_survey.R's zip download).
with_mock_fetch_binary <- function(mock_fn, code) {
  old <- get("fetch_binary", envir = .GlobalEnv)
  assign("fetch_binary", mock_fn, envir = .GlobalEnv)
  on.exit(assign("fetch_binary", old, envir = .GlobalEnv), add = TRUE)
  force(code)
}
const_fetch_binary <- function(bytes) function(url, ...) bytes
failing_fetch_binary <- function() function(url, ...) NULL
