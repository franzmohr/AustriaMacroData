## Fixture mirrors the real shape confirmed live against
## matteoiacoviello.com's own published data file on 2026-08-30: a
## "month" column plus a global "GPR" column and one "GPRC_<ISO3>"
## column per country with its own index (confirmed absent for Austria,
## present for Germany and the United States). Built with `writexl`
## (which only writes `.xlsx`) rather than checked in as a binary
## fixture -- this is fine specifically because `gpr_landing_path()`
## uses an extension-less cache filename, so `readxl::read_excel()`
## content-sniffs the format instead of assuming `.xls` from the name
## (see R/gpr.R's header for why an `.xls`-named `.xlsx` fixture would
## otherwise fail to parse).
build_gpr_fixture_bytes <- function() {
  skip_if_not_installed("writexl")
  tmp <- tempfile(fileext = ".dat")
  on.exit(unlink(tmp), add = TRUE)

  df <- data.frame(
    month = as.Date(c("2026-04-01", "2026-05-01", "2026-06-01")),
    GPR = c(252.1, 204.3, 180.5),
    GPRC_DEU = c(0.979, 0.796, 0.630),
    GPRC_USA = c(6.69, 5.30, 4.60),
    var_name = c(NA, NA, NA),
    var_label = c(NA, NA, NA)
  )
  writexl::write_xlsx(list(Sheet1 = df), tmp)
  readBin(tmp, "raw", file.info(tmp)$size)
}

test_that("fetch_gpr_bulk downloads, caches (extension-less), and parses the workbook", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)
  bytes <- build_gpr_fixture_bytes()

  with_mock_fetch_binary(const_fetch_binary(bytes), {
    out <- fetch_gpr_bulk(landing_dir = landing_dir)
  })
  expect_true(all(c("date", "GPR", "GPRC_DEU", "GPRC_USA") %in% names(out)))
  expect_equal(nrow(out), 3)
  expect_true(file.exists(gpr_landing_path(landing_dir)))
  expect_false(grepl("\\.xlsx?$", gpr_landing_path(landing_dir)))
})

test_that("fetch_gpr_bulk reads from the cache on a second call, without hitting the network again", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)
  bytes <- build_gpr_fixture_bytes()

  with_mock_fetch_binary(const_fetch_binary(bytes), {
    fetch_gpr_bulk(landing_dir = landing_dir)
  })

  called <- FALSE
  with_mock_fetch_binary(function(url, ...) { called <<- TRUE; NULL }, {
    out <- fetch_gpr_bulk(landing_dir = landing_dir)
  })
  expect_false(called)
  expect_equal(nrow(out), 3)
})

test_that("fetch_gpr_bulk warns and returns NULL when the request fails outright", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)

  with_mock_fetch_binary(failing_fetch_binary(), {
    expect_warning(out <- fetch_gpr_bulk(landing_dir = landing_dir), "GPR data fetch failed")
  })
  expect_null(out)
})

test_that("fetch_geopolitical_risk uses the country-specific column when one exists", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)
  bytes <- build_gpr_fixture_bytes()

  with_mock_fetch_binary(const_fetch_binary(bytes), {
    out <- fetch_geopolitical_risk("DEU", start_period = "2026-Q2", landing_dir = landing_dir)
  })
  expect_equal(names(out), c("date", "geopolitical_risk"))
  expect_equal(out$date, as.Date("2026-04-01"))
  expect_equal(out$geopolitical_risk, mean(c(0.979, 0.796, 0.630)))
})

test_that("fetch_geopolitical_risk falls back to the global GPR column when no country-specific one exists", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)
  bytes <- build_gpr_fixture_bytes()

  with_mock_fetch_binary(const_fetch_binary(bytes), {
    out <- fetch_geopolitical_risk("AUT", start_period = "2026-Q2", landing_dir = landing_dir)
  })
  expect_equal(names(out), c("date", "geopolitical_risk"))
  expect_equal(out$geopolitical_risk, mean(c(252.1, 204.3, 180.5)))
})

test_that("fetch_geopolitical_risk never confuses GPRC_AUS (Australia) with Austria", {
  landing_dir <- tempfile()
  on.exit(unlink(landing_dir, recursive = TRUE), add = TRUE)
  tmp <- tempfile(fileext = ".dat")
  on.exit(unlink(tmp), add = TRUE)
  df <- data.frame(
    month = as.Date(c("2026-05-01", "2026-06-01")),
    GPR = c(204.3, 180.5),
    GPRC_AUS = c(999, 999)
  )
  writexl::write_xlsx(list(Sheet1 = df), tmp)
  bytes <- readBin(tmp, "raw", file.info(tmp)$size)

  with_mock_fetch_binary(const_fetch_binary(bytes), {
    out <- fetch_geopolitical_risk("AUT", start_period = "2026-Q2", landing_dir = landing_dir)
  })
  ## Must fall back to the global GPR column (204.3/180.5), NOT read
  ## GPRC_AUS's 999 as if it were Austria's own series.
  expect_equal(out$geopolitical_risk, mean(c(204.3, 180.5)))
})
