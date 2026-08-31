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
                             anchor-concept source for EU member states;
                             also HICP (cpi_index + 4 sub-categories) and
                             labour productivity/ULC overrides
  oecd.R                    OECD Quarterly National Accounts (SDMX) -- anchor
                             concepts not covered by Eurostat, or for non-EU
                             countries
  imf.R                     IMF National Economic Accounts (fallback source,
                             after Eurostat/OECD)
  bis.R                     BIS Credit to the Non-Financial Sector (SDMX) --
                             fetches ALL countries at once per sector
                             (P/H/N/G: private, households, corporations,
                             general government), cached in data/landing/
  ecb.R                     ECB Quarterly Sector Accounts (household net
                             worth, euro-area aggregate), MFI Interest
                             Rate Statistics (mortgage rate, genuinely
                             country-specific, euro-area members), and MFI
                             Balance Sheet Items (household mortgage loans
                             outstanding, a different ECB dataflow entirely)
  ec_survey.R                European Commission Business and Consumer
                             Survey -- PREFERRED consumer-confidence source
                             for EU member states (fresher than the FRED
                             mirror below), plus 6 further per-country
                             sentiment indicators (economic sentiment,
                             industrial/services/retail/construction
                             confidence, employment expectations); the
                             monthly archive covers every EU country and
                             all 7 indicators at once, cached in data/landing/
  gpr.R                     Geopolitical Risk (GPR) Index (Caldara and
                             Iacoviello, 2022) -- country-specific for 44
                             countries, global index otherwise; downloaded
                             directly from the authors' own data file,
                             cached in data/landing/ (works for every
                             country, not just the EU)
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
                             for the 245 - 38 FRED-QD series not yet
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
Rscript scripts/build_country_panel.R --country AUT
Rscript scripts/build_country_panel.R --country USA --validate
```

| Option | Default | Description |
|---|---|---|
| `--country` | *(required)* | ISO-3166 alpha-3 code, e.g. `AUT`, `DEU`, `USA` |
| `--start-period` | `1960-Q1` | First quarter to fetch (`YYYY-Qn`) -- OECD QNA has Austrian real GDP back to 1960-Q1 (confirmed live); concepts with no data this far back are simply `NA` before their own start, per the canonical-schema design |
| `--fred-country2` | looked up | FRED's 2-letter OECD-mirror code, for countries not in `R/country_codes.R` |
| `--validate` | off | Cross-check OECD-sourced series against the real FRED-QD file (USA only, since it's the only series with published ground truth) |
| `--output-dir` | `output` | Where to write `<country>_nipa.csv` and `<country>_coverage.json` |
| `--fred-qd-vintage` | `2026-07` | FRED-QD monthly vintage to validate against (`YYYY-MM`) |

The source hierarchy per run, most-preferred first:
1. **Anchor NIPA concepts** (GDP, consumption, government spending,
   investment, exports, imports, disposable income): **Eurostat**, preferred
   for EU member states (a closer conceptual match for household
   consumption than OECD, see [Data-sources registry](#data-sources-registry)
   below), is EXTENDED with **OECD QNA** rather than only consulted where
   Eurostat resolved nothing -- Eurostat's own data for Austria starts at
   1995-Q1, but OECD QNA covers the same concepts back to 1960-Q1, so OECD
   fills in every period Eurostat doesn't cover (`splice_prefer()` in
   `R/utils.R`, which also rescales OECD's contribution to match
   Eurostat's level at the point they meet -- see Known issues below for
   why that rescaling is necessary) instead of that history being
   silently dropped. **IMF QNEA** is the final fallback for whatever
   neither source has at all.
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

**Every `<country>_nipa.csv` has the same 38 columns, in the same order**
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
incrementally: running the CLI for a new country adds that country's 38
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

For every other country, `provider` is one of `EUROSTAT`, `EUROSTAT_HICP`,
`EUROSTAT_ULC`, `OECD_QNA`, `IMF_QNEA`, `BIS_WSTC`, `ECB_QSA_PUB`, `ECB_MIR`,
`ECB_BSI`, `GPR`, `FRED_MIRROR`, `EC_BCS` or `YAHOO_FINANCE`; `key` is the
exact identifier used (a Eurostat/OECD sector-transaction pair, an IMF
indicator code, a BIS `TC_BORROWERS` sector code, an ECB dataflow key, a
fully-resolved FRED mnemonic, an EC survey country code, or a ticker), and
`comment` explains any known conceptual gap between that source and the
US/FRED-QD definition (e.g. "OECD sector S1M is total-economy consumption,
broader than FRED-QD's household-only PCE") or, if the concept wasn't
resolved for that country, why. Note that for EU-member anchor concepts the
`EUROSTAT` row's own `key` records the OECD-sourced pre-1995 extension
inline (e.g. `namq_10_gdp:B1GQ (extended pre-1995 with level-spliced
OECD_QNA:S1.B1GQ)`) rather than splitting it into a separate `OECD_QNA` row
-- `splice_prefer()` merges the two into one column, so one row is the
accurate unit of documentation; `OECD_QNA` only appears as the `provider`
value on its own for a non-EU country with no Eurostat coverage at all.

Seven deliberate per-country/per-group source overrides, all preferring a
fresher or more conceptually faithful primary source over the generic
FRED-mirror default (plus two brand-new categories of concepts with no
FRED-mirror default to override in the first place -- HICP sub-categories
and EC survey/geopolitical-risk concepts):
- **EU member states**: anchor NIPA concepts from Eurostat (not OECD) where
  available, consumer confidence from the EC's own Business and
  Consumer Survey, and the consumer price index from Eurostat's HICP
  (not the FRED mirror, which is frozen for both -- see Known issues
  below).
- **EU member states, where Eurostat publishes an index-level series for
  it**: unit labor cost from Eurostat's labour productivity/ULC dataflow,
  hours-based like FRED-QD's own construction -- not a staleness fix like
  the two above (the FRED-mirror proxy is current), but a closer
  conceptual match than its employment-based %-change construction.
  Confirmed available for Austria; confirmed **absent** for Germany
  (which keeps the FRED-mirror value) -- unlike the other three overrides
  here, this one can genuinely fail per-country even for an EU member.
- **Euro-area members**: mortgage rate from the ECB's own MFI Interest Rate
  Statistics (there is no FRED-mirror equivalent to fall back to).
- **Euro-area members**: household mortgage loans (outstanding stock, EUR
  millions) from a *second* ECB dataflow, MFI Balance Sheet Items (BSI) --
  the natural stock counterpart to the mortgage-rate override above.
  BSI and MIR are both ECB MFI statistics about the same loans but use
  completely different dimension codes; the working key was found by
  searching the ECB Data Portal's own published series list, not by
  guessing from MIR's key by analogy (which returned a structurally
  valid zero-observation response even for the simplest case).
- **Austria specifically**: share price index from the ATX (Austria's own
  benchmark index) via Yahoo Finance, not the generic OECD "all shares"
  proxy.
- **EU member states, new concepts**: four HICP sub-categories (core,
  food, energy, services) -- the same verified Eurostat HICP dataflow
  used for `cpi_index` generalizes to any COICOP code, so these were a
  small marginal addition once that fetcher existed.
- **EU member states, new concepts**: six further EC Business and
  Consumer Survey indicators, using the same archive already fetched for
  `consumer_confidence`, generalized to accept any of its seven
  per-country columns. Two were prioritized for documented predictive
  power: the **Economic Sentiment Indicator** (`economic_sentiment_indicator`,
  DG ECFIN's own flagship composite, empirically validated to track and
  lead euro-area GDP growth) and **Industrial Confidence**
  (`industrial_confidence`, one of the archive's oldest series and a
  standard OECD Composite-Leading-Indicator input). A third,
  **Employment Expectations** (`employment_expectations`), is DG ECFIN's
  own purpose-built leading indicator for employment turning points. The
  remaining three -- services, retail, and construction confidence --
  are the archive's other standard sentiment sub-indices, added as a
  low-cost extension once the fetcher was generalized.
- **Every country, new concept**: geopolitical risk (`geopolitical_risk`)
  from Caldara and Iacoviello's (2022) GPR index -- downloaded directly
  from the authors' own published data file. Genuinely country-specific
  for the 44 countries the source covers (confirmed: includes Germany and
  the United States); falls back to the source's own global index for
  every other country (confirmed: Austria is **not** among the 44 --
  watch out for "GPRC_AUS", which is Australia, not Austria, the same
  2-vs-3-letter code collision this project's own country-code table
  exists to prevent elsewhere).

## Candidate indicators (proposed, unverified)

The 38 implemented concepts are representative anchors, not a 1:1
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
handful of the highest-value candidates (government debt, building
permits, labour productivity/ULC) had their Eurostat dataflow's
*existence* confirmed live, but no candidate's exact dimension key has
been tested the way every row in `data_sources.csv` has (the CPI-staleness
fix that used to be listed here has since been fully implemented --
see the `cpi_index` row in the Coverage table and Known issues below).
Treat every row as a starting point for the same live-verification process
`R/eurostat.R`, `R/ecb.R` etc. went through, not as ready to use.

Regenerate with `python docs/generate_candidate_indicators.py` (parses
`docs/Mohr_AUSTRIA-QD.tex` for the 245-series catalog and joins it
against a hand-built annotation table in the same script) after adding new
concepts to `concept_group_map` or updating the annotations.

A few standout candidates worth prioritizing:
- **Eurostat HICP's finer COICOP breakdown** (`prc_hicp_midx` -- the
  overall `cpi_index` fix and four sub-categories, `core_cpi_index`/
  `food_price_index`/`energy_price_index`/`services_price_index`, are
  already implemented -- see the Coverage table above) could supply
  Austrian counterparts to most of FRED-QD's remaining PCE/CPI
  sub-category price indices (apparel, transport, health, and the
  various all-items-less-X variants).
- **Eurostat labour productivity and ULC** (`namq_10_lp_ulc`, already used
  for the Austria-specific `unit_labor_cost` upgrade above) also carries
  sector-specific output-per-hour and unit-labor-cost series -- a direct
  source for FRED-QD's `OPHMFG`/`OPHNFB`/`OPHPBS`/`ULCBS`/`ULCMFG`
  candidates, which this project doesn't yet track at all.
- **ECB MFI Balance Sheet Items (BSI)** -- the household house-purchase
  loans variant is already implemented as `household_mortgage_loans` (see
  the Coverage table above). Its confirmed `BS_ITEM=A22T` key is the
  template for the remaining purpose/sector breakdowns: `BS_ITEM=A21T`
  ("Credit for consumption"), by direct analogy, is the natural next
  candidate for `CONSUMERx`.

`GFDEGDQ188S` (government debt, % of GDP) is no longer a candidate here --
it's implemented as `government_debt_to_gdp` via BIS's `WS_TC` general-
government sector (see the Coverage table above), not the Eurostat
Maastricht-debt dataflow originally proposed for it, since BIS's dataflow
was already verified, already cached, and covers non-EU countries too.
`GFDEBTNx` (the same concept as a real-dollar level rather than a % of
GDP) remains a genuine gap: BIS only publishes the ratio.

### Cross-checked against EA-MD-QD

[EA-MD-QD](https://doi.org/10.5281/zenodo.10514667) (Barigozzi and Lissona,
2024; documented in detail by
[Barigozzi, Lissona and Tonni, 2026](https://arxiv.org/abs/2410.05082)) is a
1,136-series euro-area dataset that already covers Austria, live-verified
and Austria-specific by construction. Its own published Table 1 was used as
a second opinion on this project's candidate list:
- It **confirms** four previously `LOW`-confidence, unverified candidates:
  Austria-specific household total financial assets/liabilities (`HHASS`/
  `HHLB`) and the non-financial-corporation equivalents (`NFCASS`/`NFCLB`)
  are genuinely published per country, not just for the euro area as this
  project's own live testing had found for the analogous ECB series --
  those four rows are now `HIGH` confidence in
  `candidate_indicators_austria.csv`.
- It also surfaces **eight concepts with no FRED-QD equivalent at all**
  (a household savings rate, household/corporate investment and profit
  shares, a semi-durable-goods consumption category, a real effective
  exchange rate, per-worker labour productivity, and sector-specific
  confidence balances), each confirmed available for Austria and cataloged
  separately in
  [docs/candidate_indicators_ea_md_qd.csv](docs/candidate_indicators_ea_md_qd.csv)
  since they fall outside FRED-QD's 245-series scope.

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

38 concepts across all 14 FRED-QD groups (started at 18 concepts / 12
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
| Industrial Production | Industrial confidence indicator | **EC Business and Consumer Survey** (`AT.INDU`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent. Documented leading-indicator value (OECD Composite Leading Indicators input) |
| Employment and Unemployment | Unemployment rate | OECD MEI via FRED (`LRHUTTTT{cc}Q156S`) | Verified -- AUT + DEU + USA |
| Employment and Unemployment | Employment rate (15-64) | OECD MEI via FRED (`LREM64TT{cc}Q156S`) | Verified -- AUT + DEU + USA; no direct FRED-QD equivalent |
| Employment and Unemployment | Employment expectations indicator | **EC Business and Consumer Survey** (`AT.EEI`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent. DG ECFIN's own purpose-built leading indicator for employment turning points |
| Housing | Real house price index | BIS via FRED (`Q{cc}R628BIS`) | Verified -- AUT + DEU + USA |
| Housing | Construction confidence indicator | **EC Business and Consumer Survey** (`AT.BUIL`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent |
| Inventories, Orders, and Sales | Retail sales volume (proxy) | OECD MEI via FRED (`{cc3}SARTQISMEI`) | Verified for AUT + DEU; **not published for USA** (genuine gap, not a bad code) |
| Inventories, Orders, and Sales | Retail confidence indicator | **EC Business and Consumer Survey** (`AT.RETA`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent |
| Inventories, Orders, and Sales | Manufacturers' new orders/inventories | -- | Re-checked 2026-08-30: no cross-country equivalent exists (US Census Bureau-specific concept); deliberately not attempted |
| Prices | CPI index | **Eurostat HICP** `prc_hicp_midx` (EU members, live/current), else OECD MEI via FRED (`CPALTT01{cc}Q657N`, stale) | Verified -- AUT + DEU via Eurostat HICP (current through 2025-Q4, ~2 years fresher than the stale FRED mirror, which stops at 2023-Q4 for AT); USA via the stale FRED mirror (no EU HICP equivalent for non-EU countries) |
| Prices | Core, food, energy, services CPI sub-indices | **Eurostat HICP** `prc_hicp_midx`, COICOP=`TOT_X_NRG_FOOD`/`CP01`/`NRG`/`SERV` | Verified -- AUT + DEU only; EU-only by construction, no FRED-mirror equivalent for any of the four |
| Earnings and Productivity | Unit labor cost | **Eurostat labour productivity/ULC** `namq_10_lp_ulc` (EU members, where an index-level series is published), else OECD MEI via FRED (`ULQEUL01{cc}Q657S`) | Verified -- AUT via Eurostat (hours-based index, matching FRED-QD's ULCNFB construction); DEU + USA via the OECD-mirror proxy (employment-based % change, confirmed absent in index form for Germany) |
| Interest Rates | Long-term interest rate | OECD MEI via FRED (`IRLTLT01{cc}Q156N`) | Verified -- AUT + DEU + USA |
| Interest Rates | Short-term (3-month interbank) rate | OECD MEI via FRED (`IR3TIB01{cc}Q156N`) | Verified -- AUT + DEU + USA |
| Interest Rates | Mortgage rate (new business, loans to households) | **ECB** `MIR` (euro-area members) | Verified -- AUT + DE, genuinely country-specific; no source for non-euro-area countries (incl. USA -- FRED-QD's own MORTGAGE30US is US-specific too) |
| Money and Credit | Credit to private non-financial sector, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=P` (all countries in one bulk pull, cached) | Verified -- AUT + DE + US |
| Money and Credit | Household mortgage loans, outstanding stock (EUR millions) | **ECB** `BSI` (euro-area members) | Verified -- AUT (EUR 133.0bn) + DE (EUR 1,658.4bn) as of 2026-07; pairs with the mortgage-rate row above (same loan category, different ECB dataflow entirely); no source for non-euro-area countries |
| Household Balance Sheets | Household net worth (growth rate) | ECB `QSA_PUB` | Verified, but **euro-area aggregate only** -- no per-country series exists (see below) |
| Household Balance Sheets | Household credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=H` | Verified -- AUT + DE + US; **country-specific**, unlike the ECB series above |
| Non-Household Balance Sheets | Nonfinancial-corporation credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=N` | Verified -- AUT + DE + US |
| Non-Household Balance Sheets | Government debt (BIS "credit to general government"), % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=G` | Verified -- AUT + DE + US; genuinely cross-country (not EU-only), unlike most other overrides in this project -- FRED-QD's GFDEGDQ188S is US federal debt only, this is all levels of government combined |
| Exchange Rates | FX rate to USD | OECD MEI via FRED (`CCUSMA02{cc}Q618N`) | Verified -- AUT + DEU; not applicable to USA itself |
| Exchange Rates | Real effective exchange rate | OECD MEI via FRED (`CCRETT01{cc}Q661N`) | Verified -- AUT + DEU + USA |
| Other | Consumer confidence | **EC Business and Consumer Survey** (EU members, live/current), else OECD MEI via FRED (`CSCICP03{cc}M665S`, stale) | Verified -- AUT + DEU via EC survey (current through 2026-Q3); USA via the stale FRED mirror (no EU-survey equivalent exists for non-EU countries) |
| Other | Economic sentiment indicator | **EC Business and Consumer Survey** (`AT.ESI`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent. DG ECFIN's flagship composite, empirically validated to track/lead euro-area GDP growth |
| Other | Services confidence indicator | **EC Business and Consumer Survey** (`AT.SERV`) | Verified -- AUT + DEU only; EU-only, no FRED-mirror equivalent |
| Other | Geopolitical risk | **GPR Index** (Caldara-Iacoviello), country-specific for 44 countries, else the global index | Verified -- DEU + USA via their own country-specific series; AUT via the global index (confirmed absent from the 44); genuinely cross-country, no FRED-QD equivalent |
| Stock Markets | Share price index | **ATX via Yahoo Finance** (Austria specifically), else OECD MEI via FRED (`SPASTT01{cc}Q661N`) | Verified -- AUT via Yahoo Finance (current through 2026-Q3); DEU + USA via the OECD-mirror proxy |

### Known issues

- **A ~4x level discontinuity in the anchor NIPA concepts' pre-1995
  history was found and fixed 2026-08-31**, by this project's own
  plausibility checks (`R/plausibility_checks.R`, see below) -- not by
  the pre-existing `--validate` flag, which is blind to this class of
  error. Root cause: OECD QNA's table (T0102, used for every anchor
  concept) only offers `TRANSFORMATION="LA"` ("Annual levels", i.e. the
  quarterly series expressed at an annualized rate), confirmed live by
  querying `TRANSFORMATION="N"` ("Non transformed data") and getting a
  clean `NoRecordsFound` for both a 1990s and a 2020s period -- there is
  no non-annualized quarterly variant of this OECD table at all.
  Eurostat's `namq_10_gdp` reports true (non-annualized) quarterly
  levels, so the naive merge (`merge_prefer()`) was combining
  differently-scaled values in one column, producing a ~75% level jump
  at the exact quarter each anchor concept's source switches from OECD
  to Eurostat (1994-Q4 to 1995-Q1 for Austria). This was invisible to
  `--validate` because that flag only ever compares GROWTH RATES, and
  annualizing barely changes a growth rate. Fixed by `splice_prefer()`
  (`R/utils.R`), which rescales OECD's contribution to match Eurostat's
  level at their one real overlap point before coalescing, preserving
  OECD's own valid quarter-to-quarter dynamics while correcting its
  absolute scale. See `splice_prefer()`'s header comment for the full
  account, including the exact before/after values.
- **`cpi_index`'s FRED-mirror default is itself a percent-change series,
  not an index level**, discovered the same way on 2026-08-31: the raw
  `CPALTT01{cc2}Q657N` series returns values like 2.97, 1.31, 0.37 for
  2022-2023 -- real US quarterly inflation RATES, not a CPI level (which
  should read roughly 25-30 for a 1950s observation on FRED-QD's own
  1982-84=100 base). EU member states already get a genuine level index
  via the Eurostat HICP override; this only affects non-EU countries
  still on the FRED-mirror default (confirmed: the United States). Not
  fixed yet -- finding the actual CPI level mnemonic for non-EU
  countries is flagged as a good first task in [CONTRIBUTING.md](CONTRIBUTING.md); in the
  meantime `R/plausibility_checks.R` categorizes `cpi_index` to tolerate
  both constructions rather than mask the finding.
- **`cpi_index`'s FRED-mirror source is stale, and for EU member states is
  now overridden.** The OECD-MEI-mirror-via-FRED series (`CPALTT01{cc}Q657N`)
  returns a real HTTP 200 response, but that data stops at 2023-Q4 for
  Austria (checked live 2026-08-30) -- this series appears to have been
  frozen when OECD migrated its legacy MEI dataflow to a new SDMX 3.0
  system, and FRED's mirror was never updated to follow. PPI and business
  confidence were checked as alternates while extending this table and
  rejected outright for the same reason (PPI stops in 2022). For EU member
  states this is now fixed the same way `consumer_confidence` was: an
  override to Eurostat's own HICP dataflow (`prc_hicp_midx`, see
  `R/eurostat.R`), confirmed live to extend to 2025-Q4 for Austria. Non-EU
  countries (incl. the USA) still get the stale FRED-mirror value -- no
  EU-equivalent primary source exists for them.
- **OECD's data endpoint rate-limits under moderate request volume.**
  Building all three example country panels back-to-back reliably
  triggered `HTTP 429` on at least one of them; the IMF QNEA fallback
  absorbs this gracefully (a 429'd OECD anchor still resolves via IMF), so
  panels stay usable, but don't expect to loop over many countries quickly
  without hitting it. Note that OECD QNA is now queried for all 7 anchor
  concepts on every EU-country run, not only ones Eurostat resolved
  nothing for -- a deliberate trade for the extended pre-1995 history
  `splice_prefer()` provides (see Usage above), made explicit here rather
  than silently reverted to the leaner but shallower-history behavior.
- **Yahoo Finance requires a browser-like User-Agent.** Confirmed live: the
  default httr/curl User-Agent gets `HTTP 429` from
  `query2.finance.yahoo.com`, while a Chrome UA string succeeds
  immediately and repeatedly -- this is IP+UA filtering, not a real
  request-volume rate limit. `R/yahoo_finance.R` always sends one.

### Plausibility checks (a verification layer with no ground truth needed)

`--validate` (above) only works for the United States, since FRED-QD is
the only real published ground truth this project has access to. Every
other country -- including Austria itself -- has no analogous file to
compare against. `R/plausibility_checks.R` closes that gap: after every
run, it checks each resolved concept's own values for (1) a
plausible sign/range for its measurement type (rate, survey balance,
growth rate, or level/index), and (2) for levels/indices, no
implausible quarter-over-quarter jump (a heuristic threshold, tuned to
catch units/decimal/sector errors while tolerating genuine volatility --
confirmed live not to false-flag real crisis-era spikes in Austria's
`geopolitical_risk` series). Results are written into
`<country>_coverage.json`'s new `plausibility_checks` array and
summarized on the console (`PASS`/`FLAG`/`NO_DATA`/`TOO_SHORT` counts,
plus the detail for every `FLAG`). It needs no ground truth at all, so
it runs identically for AUT, DEU, USA, or any new country added later --
see [CONTRIBUTING.md](CONTRIBUTING.md) for how to use it when adding one.
This is exactly what caught both discoveries above on its first live run.

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
  project's current 38) rather than forcing it into `<country>_nipa.csv`.

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

## Contributing

Want to add another EU country? See [CONTRIBUTING.md](CONTRIBUTING.md) --
a checklist covering the country-code tables that need a new entry, running
the CLI, reading `<country>_coverage.json`, and verifying the result (there
is no published ground truth outside the US, so this leans on the
plausibility checks above plus manual spot-checks). It also names a
concrete, ready-made first task: `cpi_index`'s non-EU default is a
percent-change series mislabeled as a level (see Known issues above).

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
