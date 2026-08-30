## Fixture text below mirrors the real shape confirmed live against
## sdmx.oecd.org on 2026-08-30 (OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA,
## format=csvfilewithlabels): STRUCTURE/... columns, then TIME_PERIOD,
## OBS_VALUE among others.
oecd_gdp_fixture <- paste(
  "STRUCTURE,STRUCTURE_ID,ACTION,FREQ,REF_AREA,SECTOR,TRANSACTION,TIME_PERIOD,OBS_VALUE,UNIT_MEASURE",
  "DATAFLOW,OECD.SDD.NAD:DSD_NAMAIN1@DF_QNA(1.1),I,Q,DEU,S1,B1GQ,2020-Q1,858000,XDC",
  "DATAFLOW,OECD.SDD.NAD:DSD_NAMAIN1@DF_QNA(1.1),I,Q,DEU,S1,B1GQ,2020-Q2,777000,XDC",
  sep = "\n"
)

test_that("fetch_oecd_series parses a successful response into period/value", {
  with_mock_fetch_text(const_fetch_text(oecd_gdp_fixture), {
    out <- fetch_oecd_series("DEU", "S1", "", "B1GQ", "real_gdp")
  })
  expect_equal(names(out), c("period", "real_gdp"))
  expect_equal(out$real_gdp, c(858000, 777000))
})

test_that("fetch_oecd_series warns and returns NULL on NoResultsFound (e.g. household disposable income for most countries)", {
  with_mock_fetch_text(const_fetch_text("NoResultsFound"), {
    expect_warning(out <- fetch_oecd_series("DEU", "S14", "S1", "B6G", "real_household_disposable_income"),
                    "no observations")
  })
  expect_null(out)
})

test_that("fetch_oecd_series warns and returns NULL when the request fails outright", {
  with_mock_fetch_text(failing_fetch_text(), {
    expect_warning(out <- fetch_oecd_series("DEU", "S1", "", "B1GQ", "real_gdp"), "OECD fetch failed")
  })
  expect_null(out)
})

test_that("fetch_oecd_series never throws, even on a malformed response", {
  with_mock_fetch_text(const_fetch_text("not,valid\nheaders\nat,all,mismatched,columns"), {
    expect_warning(out <- fetch_oecd_series("DEU", "S1", "", "B1GQ", "real_gdp"))
  })
  expect_null(out)
})

test_that("build_oecd_qna_key matches the verified DF_QNA dimension order", {
  key <- build_oecd_qna_key("DEU", "S1", "", "B1GQ")
  ## FREQ.ADJUSTMENT.REF_AREA.SECTOR.COUNTERPART_SECTOR.TRANSACTION.
  ## INSTR_ASSET.ACTIVITY.EXPENDITURE.UNIT_MEASURE.PRICE_BASE.
  ## TRANSFORMATION.TABLE_IDENTIFIER (13 segments, verified order)
  expect_equal(key, "Q.Y.DEU.S1..B1GQ....XDC.LR..T0102")
})

test_that("fetch_oecd_anchors merges multiple concepts into one wide tibble by period", {
  responses <- list(
    real_gdp = oecd_gdp_fixture,
    disp_income = "NoResultsFound"
  )
  mock <- function(url, ...) {
    if (grepl("DF_QNA_INC_SAV", url, fixed = TRUE)) responses$disp_income else responses$real_gdp
  }
  with_mock_fetch_text(mock, {
    out <- fetch_oecd_anchors("DEU", start_period = "2020-Q1")
  })
  expect_true("period" %in% names(out))
  expect_true("real_gdp" %in% names(out))
  ## disposable income correctly absent (NoResultsFound), not silently zero
  expect_false("real_household_disposable_income" %in% names(out))
})
