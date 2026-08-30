# AustriaMacroData

[![Monthly data update](https://github.com/franzmohr/AustriaMacroData/actions/workflows/monthly-update.yml/badge.svg)](https://github.com/franzmohr/AustriaMacroData/actions/workflows/monthly-update.yml)
[![Last commit](https://img.shields.io/github/last-commit/franzmohr/AustriaMacroData)](https://github.com/franzmohr/AustriaMacroData/commits/main)
[![Data update frequency](https://img.shields.io/badge/data-monthly-blue)](.github/workflows/monthly-update.yml)
[![R](https://img.shields.io/badge/R-4.6.1-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/franzmohr)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/franzmohr)

Tools for building a [FRED-QD](https://research.stlouisfed.org/econ/mccracken/fred-databases/)-style
quarterly macroeconomic panel for Austria (and, more generally, any OECD or
IMF-covered country), plus reference documentation for the FRED-QD series
set itself.

FRED-QD (McCracken and Ng, 2020) is a 245-series quarterly panel of U.S.
macroeconomic data grouped into 14 categories (Output and Income, Industrial
Production, Employment and Unemployment, Housing, ...). Most of its series
are built from U.S.-specific micro sources (Census Bureau, BLS establishment
surveys, detailed BEA NIPA tables) with no direct equivalent elsewhere, so
this project does not try to replicate FRED-QD one-for-one. Instead it pulls
the closest available concept for a given country from international
sources -- OECD, IMF, BIS, ECB, and FRED's own mirror of OECD/BIS series --
and reports transparently, concept by concept, what could and could not be
resolved.

## Three things live here

1. **A technical report** ([docs/Mohr_AUSTRIA-QD.tex](docs/Mohr_AUSTRIA-QD.tex),
   compiled to [docs/Mohr_AUSTRIA-QD.pdf](docs/Mohr_AUSTRIA-QD.pdf)) --
   a working-paper-style writeup, modeled on
   [McCracken and Ng (2020)](https://doi.org/10.20955/wp.2020.005), of how
   this Austrian counterpart dataset is constructed: concept taxonomy,
   source hierarchy, verification methodology, update cadence, known
   limitations, and future work. Appendix A reproduces all 245 series of
   the actual FRED-QD file, grouped into the original 14 categories, with
   description, transformation code, and Stock-Watson (2012) factor-model
   flag; Appendix B is the Austria source mapping, regenerated fresh from
   `docs/data_sources.csv` every time the report is rebuilt (via
   [docs/generate_technical_report.py](docs/generate_technical_report.py),
   `python docs/generate_technical_report.py`), so it cannot drift out of
   sync with what the CLI actually resolved. (The raw `FRED-Data.csv`
   Appendix A was generated from is no longer kept in the repo --
   regenerate from a fresh FRED-QD download if that catalog ever needs
   re-deriving from scratch.)
2. **A country-panel builder** ([scripts/build_country_panel.R](scripts/build_country_panel.R)
   plus the [R/](R) module library) -- a command-line tool that fetches a
   FRED-QD-style panel for one country at a time and writes both the data
   and a coverage report documenting where each concept came from.
3. **A data-sources registry** ([docs/data_sources.csv](docs/data_sources.csv))
   -- the single documentation table for "what source backs this number,
   and how does it conceptually differ from the US/FRED-QD definition,"
   across every country the CLI has been run for. See
   [Data-sources registry](#data-sources-registry) below.

## Repository layout

```
scripts/
  build_country_panel.R     Current CLI entrypoint -- see Usage below
  update_monthly.R          Rebuilds AUT/DEU/USA and archives a dated vintage
                             into output/vintages/; run by the CI job below

R/                          Fetcher library used by build_country_panel.R,
                             each module individually verified against its
                             live API (see header comments for verification
                             notes and corrections vs. earlier guesses)
  utils.R                   Shared HTTP/parsing helpers (incl. fetch_text,
                             fetch_binary)
  country_codes.R           ISO-3166 alpha-3 <-> FRED 2-letter country code;
                             EU membership (`eu_member_countries`) and the
                             Commission's own 2-letter codes (Greece = "EL")
  eurostat.R                Eurostat Quarterly National Accounts -- PREFERRED
                             anchor-concept source for EU member states
  oecd.R                    OECD Quarterly National Accounts (SDMX) -- anchor
                             concepts not covered by Eurostat, or for non-EU
                             countries
  imf.R                     IMF National Economic Accounts (fallback source,
                             after Eurostat/OECD)
  bis.R                     BIS Credit to the Non-Financial Sector (SDMX) --
                             fetches ALL countries at once per sector
                             (P/H/N), cached in data/landing/
  ecb.R                     ECB Quarterly Sector Accounts (household net
                             worth, euro-area aggregate) and MFI Interest
                             Rate Statistics (mortgage rate, genuinely
                             country-specific, euro-area members)
  ec_survey.R                European Commission Business and Consumer
                             Survey -- PREFERRED consumer-confidence source
                             for EU member states (fresher than the FRED
                             mirror below); the monthly archive covers every
                             EU country at once and is cached in data/landing/
  yahoo_finance.R            ATX (Austrian Traded Index) via Yahoo Finance --
                             PREFERRED share_price_index source for Austria
                             specifically (its own benchmark index, not a
                             generic proxy)
  fred_mirror.R             FRED's public mirror of OECD MEI / BIS series --
                             the fallback for everything above, and the only
                             source for countries/concepts none of the
                             EU/Austria-specific sources cover
  fred_qd_validation.R      Downloads the real FRED-QD file and validates
                             OECD-sourced US series against it

tests/testthat/              Unit tests (HTTP mocked, offline-safe) plus one
                             opt-in test file that hits the real APIs

data/
  landing/                   Cached bulk downloads (gitignored, manual-refresh
                             convention -- delete a file to force a re-fetch):
                             bis_credit_{P,H,N}.csv (BIS, all countries),
                             ec_bcs_main_indicators_<YYMM>.xlsx (EC survey,
                             all EU countries)
  bronze/                    Reserved for a cleaned-data layer (currently empty)
  silver/                    Reserved for a further-joined layer (currently empty)

output/                      Output of build_country_panel.R, checked into
                             git and refreshed monthly by CI (see below):
                             <country>_nipa.csv + <country>_coverage.json for
                             AUT, DEU and USA, plus vintages/ (dated archive)

.github/workflows/
  monthly-update.yml         Scheduled CI job (1st of every month) -- runs
                             scripts/update_monthly.R and commits output/ back

docs/
  Mohr_AUSTRIA-QD.tex/.pdf  Technical report (see above)
  generate_technical_report.py  Rebuilds the report above from
                             Mohr_AUSTRIA-QD.tex's own Appendix A tables
                             + a fresh read of data_sources.csv
  data_sources.csv           The data-sources registry -- see below
  candidate_indicators_austria.csv  Proposed (UNVERIFIED) Austrian sources
                             for the 245 - 25 FRED-QD series not yet
                             implemented -- see below
  generate_candidate_indicators.py  Regenerates the file above from
                             docs/Mohr_AUSTRIA-QD.tex + a hand-built
                             annotation table; run with
                             `python docs/generate_candidate_indicators.py`

renv.lock, renv/, .Rprofile  renv-managed R dependency environment, pinned
                             for R/, scripts/ and tests/
```

## Usage

```bash
Rscript scripts/build_country_panel.R --country AUT --start-period 1995-Q1
Rscript scripts/build_country_panel.R --country USA --validate
```

| Option | Default | Description |
|---|---|---|
| `--country` | *(required)* | ISO-3166 alpha-3 code, e.g. `AUT`, `DEU`, `USA` |
| `--start-period` | `1995-Q1` | First quarter to fetch (`YYYY-Qn`) |
| `--fred-country2` | looked up | FRED's 2-letter OECD-mirror code, for countries not in `R/country_codes.R` |
| `--validate` | off | Cross-check OECD-sourced series against the real FRED-QD file (USA only, since it's the only series with published ground truth) |
| `--output-dir` | `output` | Where to write `<country>_nipa.csv` and `<country>_coverage.json` |
| `--fred-qd-vintage` | `2026-07` | FRED-QD monthly vintage to validate against (`YYYY-MM`) |

The source hierarchy per run, most-preferred first:
1. **Anchor NIPA concepts** (GDP, consumption, government spending,
   investment, exports, imports, disposable income): **Eurostat** first for
   EU member states (a closer conceptual match for household consumption
   than OECD, see [Data-sources registry](#data-sources-registry) below),
   then **OECD QNA** for whatever Eurostat didn't resolve, then **IMF QNEA**
   for whatever's still missing.
2. **Money and Credit / balance sheets**: **BIS** credit-to-GDP (private
   sector, households, nonfinancial corporations -- all genuinely
   country-specific), plus **ECB** household net worth (euro-area aggregate
   only) and mortgage rate (genuinely country-specific, euro-area members).
3. **Everything else** (industrial production, unemployment, house prices,
   CPI, interest rates, exchange rates, share prices): **FRED's OECD-MEI/BIS
   mirror**, EXCEPT two deliberate overrides where a fresher or more
   specific primary source exists: consumer confidence for EU member states
   (**EC Business and Consumer Survey**, see `R/ec_survey.R`) and the share
   price index for Austria specifically (**ATX via Yahoo Finance**, see
   `R/yahoo_finance.R`).

See [output/aut_coverage.json](output/aut_coverage.json),
[output/deu_coverage.json](output/deu_coverage.json) and
[output/usa_coverage.json](output/usa_coverage.json) for what actually
resolves in practice per run, and
[docs/data_sources.csv](docs/data_sources.csv) for the exact provider/key
used for every (country, concept) pair across all runs so far.

**Every `<country>_nipa.csv` has the same 25 columns, in the same order**
(`date` plus one column per concept in `concept_group_map`, see
[scripts/build_country_panel.R](scripts/build_country_panel.R)), regardless
of which concepts actually resolved for that country -- a concept that
could not be resolved is still present as an all-NA column rather than
missing from the file. This is deliberate: the point of routing every
country through the same FRED-QD-style concept labels is that switching
`--country` should be the *only* thing that changes between two runs, so
downstream code can load `aut_nipa.csv` and `deu_nipa.csv` (or any other
country's file) with the same column-handling logic. Compare
[output/aut_nipa.csv](output/aut_nipa.csv),
[output/deu_nipa.csv](output/deu_nipa.csv) and
[output/usa_nipa.csv](output/usa_nipa.csv): same header, same column order,
different data (and different NAs, per each file's coverage report).

## Automated updates

[.github/workflows/monthly-update.yml](.github/workflows/monthly-update.yml)
runs [scripts/update_monthly.R](scripts/update_monthly.R) at 06:00 UTC on the
1st of every month (also triggerable manually from the Actions tab via
`workflow_dispatch`), the same way FRED-QD itself is republished monthly.
Each run:

1. Rebuilds `output/<country>_nipa.csv` + `_coverage.json` for AUT, DEU and
   USA via `scripts/build_country_panel.R`, overwriting the "latest" files.
2. Archives a dated copy of both into `output/vintages/`, e.g.
   `output/vintages/aut_nipa_2026-09.csv` -- a monthly vintage history, not
   just a single always-overwritten snapshot.
3. Commits and pushes `output/` back to `main` if anything changed, as
   `github-actions[bot]`.

To add or remove a country from the schedule, edit the `countries` vector at
the top of `scripts/update_monthly.R`. To change the schedule, edit the
`cron` line in the workflow file (5-field crontab syntax, UTC).

## Data-sources registry

[docs/data_sources.csv](docs/data_sources.csv) is a long-format table --
`country, variable, provider, key, comment` -- with one row per (country,
concept) pair the CLI has actually resolved or attempted, across every
country it has been run for so far (USA, DEU, AUT). It is rewritten
incrementally: running the CLI for a new country adds that country's 25
rows without touching any other country's; running it again for an
existing country replaces just that country's rows.

The `USA` rows are the odd one out on purpose: they always hold the real
FRED-QD mnemonic for each concept (`provider = FRED_QD`, or `NONE` where no
FRED-QD series exists for that concept -- explained in `comment`), because
FRED-QD itself is the ground truth every other country's row is
approximating. They come from a fixed reference table in
`build_country_panel.R`, not from a live `--country USA` run through the
international sources -- that run's own OECD/IMF/BIS/FRED-mirror
resolutions are still visible in `output/usa_coverage.json` as a
cross-check, not a substitute for the ground truth.

For every other country, `provider` is one of `EUROSTAT`, `OECD_QNA`,
`IMF_QNEA`, `BIS_WSTC`, `ECB_QSA_PUB`, `ECB_MIR`, `FRED_MIRROR`, `EC_BCS` or
`YAHOO_FINANCE`; `key` is the exact identifier used (a Eurostat/OECD
sector-transaction pair, an IMF indicator code, a BIS `TC_BORROWERS` sector
code, a fully-resolved FRED mnemonic, an EC survey country code, or a
ticker), and `comment` explains any known conceptual gap between that
source and the US/FRED-QD definition (e.g. "OECD sector S1M is
total-economy consumption, broader than FRED-QD's household-only PCE") or,
if the concept wasn't resolved for that country, why.

Three deliberate per-country/per-group source overrides, all preferring a
fresher or more specific primary source over the generic FRED-mirror
default:
- **EU member states**: anchor NIPA concepts from Eurostat (not OECD) where
  available, and consumer confidence from the EC's own Business and
  Consumer Survey (not the FRED mirror, which is frozen -- see Known
  issues below).
- **Euro-area members**: mortgage rate from the ECB's own MFI Interest Rate
  Statistics (there is no FRED-mirror equivalent to fall back to).
- **Austria specifically**: share price index from the ATX (Austria's own
  benchmark index) via Yahoo Finance, not the generic OECD "all shares"
  proxy.

## Candidate indicators (proposed, unverified)

The 25 implemented concepts are representative anchors, not a 1:1
replication of FRED-QD's 245 series (see Overview above -- most of those
245 are U.S.-specific and have no cross-country equivalent at all).
[docs/candidate_indicators_austria.csv](docs/candidate_indicators_austria.csv)
goes through **every one of the 245** and proposes, for each, either an
Austrian/Eurostat/ECB candidate source, a `DERIVABLE` note (computable from
series already implemented, e.g. export/import shares of GDP), or
`NO_EQUIVALENT` with the reason (e.g. the US federal/state/local government
employment split has no EU statistical analog). Columns: `fred_qd_mnemonic,
fred_qd_group, fred_qd_description, status, candidate_source, confidence,
note`.

**This is a research proposal, not a verified registry** -- unlike
[docs/data_sources.csv](docs/data_sources.csv), which only ever contains a
source after `scripts/build_country_panel.R` has actually fetched real
data from it. `confidence` (`HIGH`/`MEDIUM`/`LOW`) reflects how sure this
pass is that the named Eurostat/ECB/OECD dataset exists in roughly that
form, based on domain knowledge of those agencies' data products -- a
handful of the highest-value candidates (the CPI-staleness fix, government
debt, building permits, labour productivity/ULC) had their Eurostat
dataflow's *existence* confirmed live, but no candidate's exact
dimension key has been tested the way every row in `data_sources.csv` has.
Treat every row as a starting point for the same live-verification process
`R/eurostat.R`, `R/ecb.R` etc. went through, not as ready to use.

Regenerate with `python docs/generate_candidate_indicators.py` (parses
`docs/Mohr_AUSTRIA-QD.tex` for the 245-series catalog and joins it
against a hand-built annotation table in the same script) after adding new
concepts to `concept_group_map` or updating the annotations.

A few standout candidates worth prioritizing:
- **Eurostat HICP** (`prc_hicp_midx`) could fix `cpi_index`'s known
  staleness (see Known issues below) -- and, via its COICOP breakdown,
  supply Austrian counterparts to most of FRED-QD's 20 PCE/CPI
  sub-category price indices.
- **Eurostat labour productivity and ULC** (`namq_10_lp_ulc`) is a direct
  quarterly dataset for exactly this concept -- a candidate upgrade for
  `unit_labor_cost`, which currently uses an OECD-mirror proxy.
- **ECB MFI Balance Sheet Items (BSI)** looks like the same country-specific
  statistical family as the already-implemented `mortgage_rate` (MIR) --
  worth checking for loans-by-purpose series analogous to FRED-QD's
  `BUSLOANSx`/`CONSUMERx`/`REALLNx`.
- **Eurostat quarterly government debt** (`gov_10q_ggdebt`) is a
  well-established EU series that should be a straightforward win for
  `GFDEGDQ188S`/`GFDEBTNx`.

## Setup

This project uses [renv](https://rstudio.github.io/renv/) for dependency
management (`.Rprofile` activates it automatically for any R session opened
in this directory). To install the pinned dependencies:

```r
renv::restore()
```

`renv.lock` covers everything `R/`, `scripts/` and `tests/` actually use,
including `readxl`/`writexl` (added for `R/ec_survey.R`'s Excel-based EC
survey archive and its test fixture).

## Testing

```r
testthat::test_dir("tests/testthat")
```

The default suite mocks all HTTP calls (`tests/testthat/helper-mocks.R`), so
it runs fully offline. `tests/testthat/test-integration.R` hits the real
OECD/IMF/BIS/ECB/FRED APIs and is skipped unless opted into explicitly:

```bash
AUSTRIAMACRODATA_RUN_INTEGRATION=true Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Verification

Every source below was checked against its own live API on 2026-08-30 --
structure/codelist queries where relevant, then real data pulls for Germany
(DEU/DE) and the US (USA/US) -- not re-guessed from `build_country_nipa_dataset.R`'s
original comments. Two real bugs were found this way and fixed (not just
"made the warning go away"):

- **OECD**: the prototype's guessed dataflow (`DSD_NAMAIN10@DF_TABLE1_EXPENDITURE`,
  12-segment key) turned out to have a real but different structure than
  guessed. Rather than debug a second untested dataflow, `R/oecd.R` reuses
  `DSD_NAMAIN1@DF_QNA`, the dataflow `scripts/01-OECD-Codes.R` had already
  hand-verified for Austria, and extends its confirmed 13-segment key
  (`FREQ.ADJUSTMENT.REF_AREA.SECTOR.COUNTERPART_SECTOR.TRANSACTION.INSTR_ASSET.ACTIVITY.EXPENDITURE.UNIT_MEASURE.PRICE_BASE.TRANSFORMATION.TABLE_IDENTIFIER`)
  to the other 5 anchor concepts. All 6 (GDP, household consumption,
  government consumption, GFCF, exports, imports) return real HTTP 200 data
  for both DEU and USA. Household disposable income does not: OECD's
  quarterly disposable-income dataflow (`DF_QNA_INC_SAV`) publishes it for
  only 11 countries (AUS, BRA, CAN, CHL, EST, GRC, HUN, LTU, LUX, LVA, ZAF),
  confirmed via zero-observation responses for USA, DEU, FRA, GBR and AUT
  specifically -- a checked absence, not a guess.
- **IMF**: the prototype's dataflow ID `NEA` no longer exists (IMF's March
  2025 platform restructuring renamed it to `QNEA`, agency `IMF.STA`,
  version `7.0.0`), and its indicator codes are standard SNA transaction
  codes (`B1GQ`, `P3_S1M`, ...), not the legacy IFS-style mnemonics
  (`NGDP_R`, `NCP_R`, ...) guessed originally. Separately, the `imfapi`
  CRAN package (v0.1.2) the prototype depended on is **confirmed broken**:
  `imf_get_dataflows()` throws `Indexing out of bounds` while parsing IMF's
  ~220-dataflow catalog (at least one entry has no `description` field),
  crashing every call to `imf_get()` regardless of which dataflow or
  indicator is requested -- reproduced live, not inferred. `R/imf.R` calls
  IMF's SDMX 3.0 API directly via `httr` instead, bypassing the broken
  wrapper.
- **FRED mirror**: of 9 mnemonic families guessed, 5 were wrong and are
  corrected in `R/fred_mirror.R` (industrial production, CPI, consumer
  confidence, retail sales; unemployment, long-term rates, FX, house prices
  and share prices were already correct). Consumer confidence has no
  quarterly OECD MEI series at all -- only monthly -- so it's fetched
  monthly and averaged to quarterly in code.
- **BIS**: the dataflow version was wrong (`1.0`, should be `2.0`) and the
  guessed 8-dimension key bore no resemblance to the real 7-dimension one
  (`FREQ.BORROWERS_CTY.TC_BORROWERS.TC_LENDERS.VALUATION.UNIT_TYPE.TC_ADJUST`,
  confirmed via the dataflow's own DSD). The fixed key returns real data
  for both DE and US.
- **ECB**: the deepest correction. The prototype assumed household net
  worth would be available *per country* for euro-area members. Live
  verification found the opposite: the real dataflow (`ECB.DISS:QSA_PUB`,
  not plain `ECB:QSA` as guessed) publishes this concept **only** for the
  euro-area aggregate (`REF_AREA=I8`) -- individual member countries (DE,
  AT, FR, ...) return zero observations, confirmed by listing the
  dataflow's actual series keys. `R/ecb.R` returns the euro-area aggregate,
  explicitly labeled `euro_area_household_net_worth_growth` (not e.g.
  `deu_household_net_worth`), for any euro-area country, so callers can't
  mistake it for a country-specific figure.
- **The FRED-QD validation logic itself had a bug**: the prototype's
  `format(date, "%Y-Q%q")` doesn't work -- R's `format.Date()` has no `%q`
  (quarter) specifier, so it silently emitted `"2020-Qq"` instead of
  `"2020-Q1"` for every date, breaking the join between OECD-sourced series
  and the real FRED-QD file. This would have made the validation block
  report `NO_DATA`/garbage for every concept while still "running without
  erroring" -- exactly the failure mode this project exists to catch.
  Fixed with a real `date_to_period()` helper (`R/utils.R`), covered by
  `tests/testthat/test-fred_qd_validation.R`.

### FRED-QD group coverage

25 concepts across all 14 FRED-QD groups (started at 18 concepts / 12
groups on 2026-08-30; grew via several same-day extension passes -- see
`R/fred_mirror.R`, `R/bis.R`, `R/eurostat.R`, `R/ecb.R`, `R/ec_survey.R`
and `R/yahoo_finance.R` header comments for the full trail, including one
mnemonic that was initially mistranscribed as `...Q657N` instead of the
verified `...Q657S`, caught by re-testing the exact string rather than
re-guessing). The authoritative, per-country version of this table is
[docs/data_sources.csv](docs/data_sources.csv); this is a summary, and
shows the PREFERRED source where an EU/euro-area/Austria-specific
override exists -- see the fallback chain earlier in this README.

| FRED-QD Group | Concept(s) | Source | Status |
|---|---|---|---|
| Output and Income | Real GDP, household consumption, govt. consumption, GFCF, exports, imports | **Eurostat** `namq_10_gdp` (EU members), else OECD QNA `DF_QNA` | Verified -- real current (2026-Q2) data, AUT + DEU via Eurostat, USA via OECD |
| Output and Income | Household disposable income | OECD `DF_QNA_INC_SAV`, IMF QNEA fallback | Verified absent for USA/DEU/FRA/GBR/AUT (checked against Eurostat too: no valid quarterly NA_ITEM either); available for 11 smaller economies only (see below) |
| Industrial Production | Industrial production index | OECD MEI via FRED (`{cc3}PROINDQISMEI`) | Verified -- AUT + DEU + USA |
| Employment and Unemployment | Unemployment rate | OECD MEI via FRED (`LRHUTTTT{cc}Q156S`) | Verified -- AUT + DEU + USA |
| Employment and Unemployment | Employment rate (15-64) | OECD MEI via FRED (`LREM64TT{cc}Q156S`) | Verified -- AUT + DEU + USA; no direct FRED-QD equivalent |
| Housing | Real house price index | BIS via FRED (`Q{cc}R628BIS`) | Verified -- AUT + DEU + USA |
| Inventories, Orders, and Sales | Retail sales volume (proxy) | OECD MEI via FRED (`{cc3}SARTQISMEI`) | Verified for AUT + DEU; **not published for USA** (genuine gap, not a bad code) |
| Inventories, Orders, and Sales | Manufacturers' new orders/inventories | -- | Re-checked 2026-08-30: no cross-country equivalent exists (US Census Bureau-specific concept); deliberately not attempted |
| Prices | CPI index | OECD MEI via FRED (`CPALTT01{cc}Q657N`) | Verified, but **stale**: real 200 response, data stops ~2024 for DE -- see Known issues below |
| Earnings and Productivity | Unit labor cost (employment-based, % change) | OECD MEI via FRED (`ULQEUL01{cc}Q657S`) | Verified -- AUT + DEU + USA; FRED-QD's ULCNFB is a related but differently-constructed index |
| Interest Rates | Long-term interest rate | OECD MEI via FRED (`IRLTLT01{cc}Q156N`) | Verified -- AUT + DEU + USA |
| Interest Rates | Short-term (3-month interbank) rate | OECD MEI via FRED (`IR3TIB01{cc}Q156N`) | Verified -- AUT + DEU + USA |
| Interest Rates | Mortgage rate (new business, loans to households) | **ECB** `MIR` (euro-area members) | Verified -- AUT + DE, genuinely country-specific; no source for non-euro-area countries (incl. USA -- FRED-QD's own MORTGAGE30US is US-specific too) |
| Money and Credit | Credit to private non-financial sector, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=P` (all countries in one bulk pull, cached) | Verified -- AUT + DE + US |
| Household Balance Sheets | Household net worth (growth rate) | ECB `QSA_PUB` | Verified, but **euro-area aggregate only** -- no per-country series exists (see below) |
| Household Balance Sheets | Household credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=H` | Verified -- AUT + DE + US; **country-specific**, unlike the ECB series above |
| Non-Household Balance Sheets | Nonfinancial-corporation credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=N` | Verified -- AUT + DE + US |
| Exchange Rates | FX rate to USD | OECD MEI via FRED (`CCUSMA02{cc}Q618N`) | Verified -- AUT + DEU; not applicable to USA itself |
| Exchange Rates | Real effective exchange rate | OECD MEI via FRED (`CCRETT01{cc}Q661N`) | Verified -- AUT + DEU + USA |
| Other | Consumer confidence | **EC Business and Consumer Survey** (EU members, live/current), else OECD MEI via FRED (`CSCICP03{cc}M665S`, stale) | Verified -- AUT + DEU via EC survey (current through 2026-Q3); USA via the stale FRED mirror (no EU-survey equivalent exists for non-EU countries) |
| Stock Markets | Share price index | **ATX via Yahoo Finance** (Austria specifically), else OECD MEI via FRED (`SPASTT01{cc}Q661N`) | Verified -- AUT via Yahoo Finance (current through 2026-Q3); DEU + USA via the OECD-mirror proxy |

### Known issues

- **`cpi_index` is stale for every country** (no primary-source override
  exists for it yet, unlike consumer confidence). It returns a real HTTP
  200 response with real historical data, but that data stops around 2024
  for DE (checked live 2026-08-30) -- this OECD-MEI-mirror-via-FRED series
  appears to have been frozen when OECD migrated its legacy MEI dataflow
  to a new SDMX 3.0 system, and FRED's mirror was never updated to follow.
  PPI and business confidence were checked as alternates while extending
  this table and rejected outright for the same reason (PPI stops in
  2022). `consumer_confidence` had the identical problem but is now fixed
  for EU member states via the EC Business and Consumer Survey override
  (`R/ec_survey.R`) -- CPI needs the same treatment, sourcing from OECD's
  or Eurostat's own current CPI dataflow directly (the way `R/oecd.R` /
  `R/eurostat.R` already do for QNA), not done yet. A good next task.
- **OECD's data endpoint rate-limits under moderate request volume.**
  Building all three example country panels back-to-back reliably
  triggered `HTTP 429` on at least one of them; the IMF QNEA fallback
  absorbs this gracefully (a 429'd OECD anchor still resolves via IMF), so
  panels stay usable, but don't expect to loop over many countries quickly
  without hitting it. The Eurostat-first ordering for EU countries also
  helps here indirectly, since it means OECD is asked for fewer anchor
  concepts per EU-country run (typically just the 1 Eurostat doesn't
  cover) than before.
- **Yahoo Finance requires a browser-like User-Agent.** Confirmed live: the
  default httr/curl User-Agent gets `HTTP 429` from
  `query2.finance.yahoo.com`, while a Chrome UA string succeeds
  immediately and repeatedly -- this is IP+UA filtering, not a real
  request-volume rate limit. `R/yahoo_finance.R` always sends one.

### Evaluated, not integrated

- **AMECO** (the European Commission's annual macro-economic database) was
  considered as an additional source. Confirmed via its own reference
  metadata: it is **annual only**, updated twice a year alongside the
  Commission's Spring/Autumn forecasts -- there is no quarterly frequency
  to fetch, at all, for any series. That's a genuine architecture mismatch
  with this project's quarterly panel (FRED-QD itself is quarterly for the
  same reason AMECO-style annual fiscal series aren't in it), not a gap to
  paper over with quarter-repeated annual values. Worth revisiting as a
  SEPARATE annual output file (fiscal balance, potential output, output
  gap, etc. -- concepts genuinely absent from both FRED-QD and this
  project's current 25) rather than forcing it into `<country>_nipa.csv`.

### Non-goals (deliberate, carried over from the original script)

- No cross-country source exists for FRED-QD's US-specific manufacturers'
  new orders, BLS sector-output indices, or federal/state government
  splits -- not attempted, by design.
- The original prototype's fuzzy-matching extension (`suggest_matches()` /
  `adjudicate_with_claude()`, for going beyond the 7 anchor concepts using
  string similarity + an optional LLM call) was not ported into `R/oecd.R`.
  It's exploratory/untested machinery beyond what this verification pass
  covers; `build_country_nipa_dataset.R` is kept as-is if you want to reuse
  it manually.

## License

The code in this repository ([LICENSE](LICENSE)) is MIT licensed. That
covers the fetchers, the CLI tool, and the documentation generators --
it does **not** extend to the data itself. Every number in `output/` and
`data/` originates from a third-party source (OECD, Eurostat, ECB, BIS,
IMF, FRED, the European Commission's Business and Consumer Survey, Yahoo
Finance) and remains subject to that source's own terms of use; this
project cannot grant rights over data it does not own. Check the relevant
provider's terms before redistributing `output/*.csv` or `data/landing/*`
beyond your own use.
