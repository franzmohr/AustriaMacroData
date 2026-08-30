## Sources the project's R/ modules before running any test.
##
## testthat::test_dir()/test_file() change the working directory to
## tests/testthat/ while sourcing setup*.R files (confirmed live: a
## plain "R" relative path here silently finds zero files and every
## test fails with "object not found", with no error at the sourcing
## step itself) -- so the R/ directory is located relative to this
## file's own directory instead of relying on getwd().
##
## Sourced explicitly into .GlobalEnv (not the ephemeral environment
## testthat runs setup.R in) so that both the test files and
## helper-mocks.R's get()/assign() on `fetch_text` can see them.
for (.f in list.files("../../R", full.names = TRUE, pattern = "\\.R$")) source(.f, local = .GlobalEnv)
rm(.f)
