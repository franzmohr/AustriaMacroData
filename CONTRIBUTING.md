# Contributing: adding a new EU country

This project builds a FRED-QD-style quarterly macro panel one country at a
time (`AUT` is the reference implementation; `DEU` and `USA` exist as
comparison/validation countries). This guide is a checklist for extending
it to another EU member state, plus how to verify the result once you have
one, since — unlike the United States — there is no published ground-truth
file to compare a new country's panel against.

If you only want to *run* the tool for a country that's already wired up,
see the `Rscript scripts/build_country_panel.R --help` usage in
[README.md](README.md) instead; this document is about adding a country
that isn't there yet.

## To-do list

- [ ] **Confirm the country is in the built-in code tables.** Check
  [R/country_codes.R](R/country_codes.R):
  - `country_code_map` needs a row (`country3`, `country2`, `country_name`)
    — the ISO-3166 alpha-3 code and FRED's 2-letter OECD-mirror code are
    *different conventions*; do not derive one from the other by slicing
    (e.g. `AUT[1:2]` would collide with Australia's real FRED code `AU`).
    Most EU/EEA/OECD members are already listed; if yours isn't, add it
    (and set `--fred-country2` explicitly on the CLI the first time, to
    confirm your guess against a live 200 response before adding it to the
    table permanently).
  - `eu_member_countries` (same file) gates the European Commission
    Business and Consumer Survey source (`R/ec_survey.R`) and the
    Eurostat-HICP CPI override. Add your country's alpha-3 code here if
    it's an EU member.
  - `euro_area_countries` in [R/ecb.R](R/ecb.R) is a **separate, narrower**
    list (only countries using the euro) that gates ECB-sourced concepts
    (household net worth, household mortgage loans, etc.). Do not assume
    EU membership implies euro-area membership (Sweden, Poland, Denmark
    are EU but not euro area) — check which list actually applies to each
    source before adding your country to it.
  - Watch for FRED's own 2-vs-3-letter country-code collisions (documented
    in `R/gpr.R`'s header) when wiring any *new* FRED-mirror series — this
    project has already been bitten once by exactly this trap.

- [ ] **Run the panel builder for your country:**
  ```bash
  Rscript scripts/build_country_panel.R --country XXX --start-period 1960-Q1
  ```
  Read the console output carefully. `warning()` calls are expected and
  informative (they name the exact failing key/mnemonic), not noise —
  every one of them means one concept did not resolve from its primary
  source and either fell back to a secondary source or is `NA` for your
  country.

- [ ] **Read `output/<country>_coverage.json`.** It has five sections:
  `resolved` (which source actually answered for each concept, and its
  exact key), `skipped` (concepts with no data for this country, and why),
  `groups_not_attempted`, and `plausibility_checks` (see next section).
  Cross-check `resolved` against what you expect: if a concept you know
  should exist for your country shows up in `skipped`, that is the first
  place to dig — usually a wrong SDMX dimension value, not a genuine data
  gap. [R/oecd.R](R/oecd.R), [R/eurostat.R](R/eurostat.R),
  [R/ecb.R](R/ecb.R), and [R/bis.R](R/bis.R) each have header comments
  documenting the *live-verification* methodology this project follows for
  confirming a dataflow/key actually works before wiring it in — follow
  the same pattern (query the API's own structure/codelist endpoint, then
  confirm a real non-empty response for at least one other country) for
  any new key you add or change, rather than guessing by analogy.

- [ ] **Add your country's rows to `docs/data_sources.csv`** if you make
  any country-specific source decision (an override, a fallback, a
  concept that needs a different key shape for your country than the
  default template). This file is the single documentation surface for
  "what source backs this number, and how does it conceptually differ
  from the US/FRED-QD definition" — see [README.md](README.md) and
  Section 3 of the working paper
  ([docs/Mohr_AUSTRIA-QD.pdf](docs/Mohr_AUSTRIA-QD.pdf)) for its exact
  schema (`country`, `variable`, `provider`, `key`, `comment`).

- [ ] **Run the test suite** (`Rscript -e "testthat::test_dir('tests/testthat')"`)
  to confirm you haven't broken anything for the existing countries. Add
  new unit tests for any new fetch function you write, following the
  existing `test-*.R` files' pattern of mocking the HTTP layer
  (`helper-mocks.R`'s `with_mock_fetch_text()`) rather than hitting the
  live API in tests.

- [ ] **Update README.md's country-coverage notes** if your country's
  panel has a structurally different set of `NA` concepts than AUT/DEU
  (e.g. a non-euro-area EU country will be missing the euro-area-only
  concepts by construction — see the working paper's Known Limitations
  §5 for the existing account of this pattern).

## Verifying a new country's panel: no ground truth needed

FRED-QD itself is the only published ground truth this project has, and it
only covers the United States — that's what `--validate` checks against
(`R/fred_qd_validation.R`), and it's why `--validate` silently does nothing
for any other `--country`. For a genuinely new country there is no
equivalent file to diff against, so verification has to happen a different
way:

1. **Run the automated plausibility checks — they run automatically, every
   time.** `R/plausibility_checks.R` checks every resolved concept against
   its own known measurement type (percentage/ratio, survey balance or
   sentiment index, quarterly growth rate, or level/index) using bounds
   and a quarter-over-quarter jump heuristic that need no external
   reference file at all — just the panel itself. Results land in two
   places after every run:
   - **The console summary**, e.g. `Plausibility checks: 36 PASS, 2 FLAG,
     0 NO_DATA/TOO_SHORT`, followed by one line per `FLAG` naming the
     concept and the reason.
   - **`output/<country>_coverage.json`'s `plausibility_checks` array** —
     one entry per concept, with `label`, `category`, `status`
     (`PASS`/`FLAG`/`NO_DATA`/`TOO_SHORT`), and a human-readable `detail`
     string.

   Treat a `FLAG` as a prioritized to-do item, not proof of an error, and
   a `PASS` as "nothing obviously wrong," not proof of correctness — these
   are deliberately loose, heuristic bounds (see the file's own header
   comment for the full rationale). **This is not hypothetical**: on its
   first live run, this exact check caught a real, previously-unknown ~75%
   level discontinuity in all six NIPA anchor concepts (Eurostat's
   quarterly levels were being coalesced with OECD's *annualized-rate*
   levels at the two sources' 1995 handoff, with no rescaling) — a bug
   invisible to `--validate`'s growth-rate-only comparison, because
   annualizing a series barely changes its period-over-period % growth.
   See Section 2.2/2.6 of the working paper for the full account, and
   [R/utils.R](R/utils.R)'s `splice_prefer()` for the fix.

2. **When a concept `FLAG`s, trace it back through `docs/data_sources.csv`**
   to the exact `(provider, key)` pair that produced it, then re-verify
   that key *live* against the source's own API — the same methodology
   every existing module in `R/` already documents in its own header
   comment (query the structure/codelist endpoint first, then confirm a
   real non-empty, current response). Common root causes, in rough order
   of likelihood: a wrong SDMX dimension (sector, unit, or price-base code
   picking a related-but-different series), a units mismatch (millions
   vs. billions, or a level vs. a % change — see the `cpi_index` example
   below), or a stale/frozen mirror (some FRED-via-OECD-MEI mirrors were
   found, live, to have stopped updating — see `R/fred_mirror.R`'s header).

3. **Spot-check a handful of concepts by hand against a value you can
   independently confirm** — this project's own habit throughout
   development, and still worth doing for at least 2–3 concepts per new
   country even after the plausibility checks pass, since the automated
   checks are heuristic range/jump bounds, not a correctness certificate.
   Good candidates: `real_gdp` or `unemployment_rate` for a recent quarter
   (check against your country's national statistics office or a quick
   search of the source agency's own published headline figure), and
   `government_debt_to_gdp` (BIS/Eurostat both publish this as a
   well-known, easily-cross-checked number).

4. **A concrete first task**, ready-made from this project's own not-yet-fixed
   findings: `cpi_index`'s FRED-mirror default (`CPALTT01{cc2}Q657N`,
   used for any country not on the Eurostat-HICP override — i.e. non-EU
   countries, or an EU country before you've added the override) was found
   live to be a quarterly **percent-change** series, not the index level
   its own FRED-QD mnemonic (`CPIAUCSL`) implies. It doesn't `FLAG` today
   only because `R/plausibility_checks.R` deliberately categorizes
   `cpi_index` into a wide, sign-agnostic bucket that tolerates *both*
   constructions at once — see that file's inline comment for exactly why.
   Finding OECD's or FRED's actual CPI **level** mnemonic for a non-EU
   country (or confirming the Eurostat HICP override is correct for a new
   EU country) and fixing this properly is a self-contained, well-scoped
   task: see [R/fred_mirror.R](R/fred_mirror.R)'s header comment for the
   full diagnostic trail (the exact values that gave it away, and why),
   and Known Limitations item 7 in the working paper.

## Style this project expects from any change

- **Verify live, don't guess by analogy.** Nearly every module header
  comment in `R/` documents a mnemonic or dimension value that looked
  plausible but was wrong, and how the correct one was actually confirmed
  (a real, current, non-empty API response — not just an HTTP 200, since
  some sources return a syntactically valid but semantically empty or
  stale response for an unsupported query).
- **Document what was found and fixed, not just what works.** When you
  discover a real error in an existing source (like the two above), fix it
  *and* leave a comment recording what was wrong and how you found it —
  this project follows FRED-QD's own convention of not letting a fix
  quietly erase the record that an error existed in a previously-published
  vintage of the data.
- **Prefer fixing a wrong key over adding a workaround.** If a concept
  resolves to the wrong series, correct the key; don't special-case around
  bad data if a real fix is findable.
