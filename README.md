# AustriaMacroData

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

1. **A FRED-QD reference document** ([docs/FRED-QD_variables.tex](docs/FRED-QD_variables.tex),
   compiled to [docs/FRED-QD_variables.pdf](docs/FRED-QD_variables.pdf)) --
   every one of the 245 series in [FRED-Data.csv](FRED-Data.csv) (the actual
   downloaded FRED-QD file), grouped into the original 14 categories, with
   description, transformation code, and Stock-Watson (2012) factor-model
   flag. It also includes a table mapping each FRED-QD group to the source
   used (or not yet available) for Austria.
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
FRED-Data.csv               Raw FRED-QD download (US ground truth, 245 series)
fred_nipa_comparison.csv    Output of scripts/US-FRED-series.R (see below)

scripts/
  build_country_panel.R     Current CLI entrypoint -- see Usage below
  01-OECD-Codes.R           Austria-specific OECD QNA pulls (GDP, Consumption,
                             FixedInv, UnempRate); reads scripts/OECD-Codes.csv,
                             writes data/landing/ and data/bronze/
  OECD-Codes.csv            Series code -> OECD SDMX URL table used above
  01-ECB-Codes.R            Austria new mortgage-lending rate/volume via the
                             ECB's MIR dataset (experimental, mixed-frequency)
  02-AustriaQuarterly.R     Assembles data/bronze/ into one quarterly panel;
                             also holds (commented out) exploratory pulls for
                             national unemployment, consumer confidence, etc.
  US-FRED-series.R          Pulls raw US NIPA series directly from FRED, for
                             benchmarking against the OECD QNA equivalents

R/                          Fetcher library used by build_country_panel.R,
                             each module individually verified against its
                             live API (see header comments for verification
                             notes and corrections vs. earlier guesses)
  utils.R                   Shared HTTP/parsing helpers
  country_codes.R           ISO-3166 alpha-3 <-> FRED's 2-letter country code
  oecd.R                    OECD Quarterly National Accounts (SDMX)
  imf.R                     IMF National Economic Accounts (fallback source)
  bis.R                     BIS Credit to the Non-Financial Sector (SDMX)
  ecb.R                     ECB Quarterly Sector Accounts (household net worth)
  fred_mirror.R             FRED's public mirror of OECD MEI / BIS series
                             (industrial production, unemployment, CPI, rates,
                             exchange rates, consumer confidence, house prices,
                             retail sales, share prices)
  fred_qd_validation.R      Downloads the real FRED-QD file and validates
                             OECD-sourced US series against it

build_country_nipa_dataset.R  Original single-file prototype, superseded by
                             scripts/build_country_panel.R + R/. Kept for
                             history; its guessed API keys/dimension orders
                             are documented and corrected in the R/ module
                             header comments.

tests/testthat/              Unit tests (HTTP mocked, offline-safe) plus one
                             opt-in test file that hits the real APIs

data/
  landing/                   Raw SDMX CSV downloads (gitignored)
  bronze/                    Cleaned PERIOD + value CSVs (gitignored)
  silver/                    Reserved for a further-joined layer (currently empty)

output/                      Example output of build_country_panel.R:
                             <country>_nipa.csv + <country>_coverage.json
                             (checked in for AUT, DEU and USA as worked examples)

docs/
  FRED-QD_variables.tex/.pdf  (see above)
  data_sources.csv           The data-sources registry -- see below

renv.lock, renv/, .Rprofile  renv-managed R dependency environment, pinned
                             for R/, scripts/build_country_panel.R and tests/
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

The source hierarchy per run is: OECD QNA anchors (GDP, consumption,
government spending, investment, exports, imports, disposable income) with
an IMF QNEA fallback where OECD has no data, then BIS credit, then ECB
household net worth (euro-area aggregate only), then FRED's OECD-MEI/BIS
mirror for industrial production, unemployment, house prices, CPI, long
rates, consumer confidence, and share prices. See
[output/aut_coverage.json](output/aut_coverage.json),
[output/deu_coverage.json](output/deu_coverage.json) and
[output/usa_coverage.json](output/usa_coverage.json) for what actually
resolves in practice, and `docs/FRED-QD_variables.pdf`'s mapping table for
the Austria-specific picture.

**Every `<country>_nipa.csv` has the same 24 columns, in the same order**
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

## Data-sources registry

[docs/data_sources.csv](docs/data_sources.csv) is a long-format table --
`country, variable, provider, key, comment` -- with one row per (country,
concept) pair the CLI has actually resolved or attempted, across every
country it has been run for so far (USA, DEU, AUT). It is rewritten
incrementally: running the CLI for a new country adds that country's 24
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

For every other country, `provider` is one of `OECD_QNA`, `IMF_QNEA`,
`BIS_WSTC`, `ECB_QSA_PUB` or `FRED_MIRROR`, `key` is the exact identifier
used (an OECD sector.transaction pair, an IMF indicator code, a BIS
`TC_BORROWERS` sector code, or a fully-resolved FRED mnemonic), and
`comment` explains any known conceptual gap between that source and the
US/FRED-QD definition (e.g. "OECD sector S1M is total-economy consumption,
broader than FRED-QD's household-only PCE") or, if the concept wasn't
resolved for that country, why.

## Setup

This project uses [renv](https://rstudio.github.io/renv/) for dependency
management (`.Rprofile` activates it automatically for any R session opened
in this directory). To install the pinned dependencies:

```r
renv::restore()
```

`renv.lock` covers `R/`, `scripts/build_country_panel.R` and `tests/` --
the new, tested system. It does **not** cover `arrow`, `ecb`, `psych`,
`usethis`, `imfapi` or `stringdist`, which appear only in the pre-existing
Austria-specific scripts (`scripts/01-ECB-Codes.R`, `scripts/02-AustriaQuarterly.R`)
or in commented-out/reference code in `build_country_nipa_dataset.R`.
Install those separately (`install.packages(c("arrow", "ecb", "psych", "usethis"))`)
if you need to run those specific files.

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

24 concepts across all 14 FRED-QD groups (up from 18 concepts / 12 groups
in the first verification pass on 2026-08-30 -- the additions below were
found and verified the same day, see `R/fred_mirror.R` and `R/bis.R`
header comments for the full trail, including one mnemonic that was
initially mistranscribed as `...Q657N` instead of the verified `...Q657S`
and caught by re-testing the exact string, not by re-guessing). The
authoritative, per-country version of this table is
[docs/data_sources.csv](docs/data_sources.csv); this is a summary.

| FRED-QD Group | Concept(s) | Source | Status |
|---|---|---|---|
| Output and Income | Real GDP, household consumption, govt. consumption, GFCF, exports, imports | OECD QNA (`DF_QNA`) | Verified -- real 200 responses, AUT + DEU + USA |
| Output and Income | Household disposable income | OECD `DF_QNA_INC_SAV`, IMF QNEA fallback | Verified absent for USA/DEU/FRA/GBR/AUT; available for 11 smaller economies only (see below) |
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
| Money and Credit | Credit to private non-financial sector, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=P` | Verified -- AUT + DE + US |
| Household Balance Sheets | Household net worth (growth rate) | ECB `QSA_PUB` | Verified, but **euro-area aggregate only** -- no per-country series exists (see below) |
| Household Balance Sheets | Household credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=H` | Verified -- AUT + DE + US; **country-specific**, unlike the ECB series above |
| Non-Household Balance Sheets | Nonfinancial-corporation credit, % of GDP | BIS `WS_TC` v2.0, `TC_BORROWERS=N` | Verified -- AUT + DE + US |
| Exchange Rates | FX rate to USD | OECD MEI via FRED (`CCUSMA02{cc}Q618N`) | Verified -- AUT + DEU; not applicable to USA itself |
| Exchange Rates | Real effective exchange rate | OECD MEI via FRED (`CCRETT01{cc}Q661N`) | Verified -- AUT + DEU + USA |
| Other | Consumer confidence | OECD MEI via FRED (`CSCICP03{cc}M665S`, monthly, averaged to quarterly) | Verified, but **stale**: data stops ~2024 for DE -- see Known issues below |
| Stock Markets | Share price index | OECD MEI via FRED (`SPASTT01{cc}Q661N`) | Verified -- AUT + DEU + USA |

### Known issues

- **`cpi_index` and `consumer_confidence` are stale.** Both return real
  HTTP 200 responses with real historical data, but that data stops around
  2024 for DE (checked live 2026-08-30) -- this whole OECD-MEI-mirror-via-
  FRED family appears to have been frozen when OECD migrated its legacy
  MEI dataflow to a new SDMX 3.0 system, and FRED's mirror was never
  updated to follow. Two other candidates (PPI, business confidence) were
  checked while extending this table and rejected outright for the same
  reason (PPI stops in 2022). A real fix means sourcing these from OECD's
  new CPI dataflow directly, the way `R/oecd.R` already does for QNA --
  not done yet because OECD's own data endpoint (not just this FRED
  mirror) was intermittently rate-limiting (`HTTP 429`) this session's
  requests throughout this verification pass. Left as-is rather than
  papered over; a good next task once the rate limit is no longer a
  factor.
- **OECD's data endpoint rate-limits under moderate request volume.**
  Building all three example country panels back-to-back reliably
  triggered `HTTP 429` on at least one of them; `R/oecd.R`'s IMF QNEA
  fallback absorbs this gracefully (a 429'd OECD anchor still resolves via
  IMF), so panels stay usable, but don't expect to loop over many
  countries quickly without hitting it.

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
