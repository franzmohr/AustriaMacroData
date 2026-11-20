# An SDMX pipeline: bronze, silver, gold

Status: design, not yet implemented. Written 20 November 2026. This document
covers the whole pipeline. The silver layer's capture of SDMX answers is
described in more detail in [sdmx_silver_layer.md](sdmx_silver_layer.md).
The artefacts it declares are in [`registry/`](../registry/).

## Goal

The repository should serve two kinds of users from one build:

- People who chart and read numbers. They want a long table with one row per
  observation, with names in English and German, and an Excel file with the
  date it was made.
- People who run statistical analysis. They want the FRED-QD- and
  FRED-MD-style panels as they are today, plus parquet and SDMX-CSV files
  whose every number can be traced to the series it came from.

## The rule

Every layer follows SDMX as far as SDMX goes. Where it does not go, this
project declares its own artefacts the way SDMX would. When choosing an
artefact, the order of preference is:

1. **The source's own SDMX structure, unchanged**: its dataflow and version,
   its dimension and attribute IDs, and its codes.
2. **The SDMX cross-domain concepts and codelists**:
   `SDMX:CROSS_DOMAIN_CONCEPTS(2.0)` and the `SDMX:CL_*` codelists.
3. **An artefact under this project's own agency, `AMD`.** It is built as
   SDMX builds one: a versioned dataflow, a data structure with dimensions in a
   fixed order, a time dimension, a measure and attributes, concepts in
   `AMD:AMD_CONCEPTS(1.0)`, and codelists `AMD:CL_<CONCEPT>(1.0)` with
   upper-case codes, `_Z` for not applicable, `_T` for total and `_X` for
   unspecified. An invented artefact reuses a cross-domain concept wherever one
   fits. Every invented artefact is declared in the registry, and the code
   validates against it.

### What the SDMX Global Registry actually holds

I checked this against `registry.sdmx.org` on 20 November 2026, and three
assumptions turned out to be wrong:

| Expected | What exists | Consequence |
|---|---|---|
| `SDMX:CL_ADJUSTMENT` | No such codelist under the SDMX agency. The cross-domain concept `ADJUSTMENT` exists but is uncoded, while `SEASONAL_ADJUST` is coded by `SDMX:CL_SEASONAL_ADJUST(1.0)` (N, S, W, Y, T, …). | The dimension is called `ADJUSTMENT` (concept `SDMX:CROSS_DOMAIN_CONCEPTS(2.0).ADJUSTMENT`) and coded by `SDMX:CL_SEASONAL_ADJUST(1.0)`. The ECB's `ECB:CL_ADJUSTMENT(1.0)` uses the same letters for N, S, W and Y. Eurostat's `s_adj` maps as NSA→N, SA→S, CA→W, SCA→Y. |
| `SOURCE_AGENCY` as a cross-domain concept | Not one of the 229 cross-domain concepts. The ECB declares it, as `ECB:ECB_CONCEPTS(1.0).SOURCE_AGENCY`. | Rule 2 has nothing, so the ECB's concept is reused rather than an AMD one invented. Its codes are in `AMD:CL_SOURCE_AGENCY(1.0)`, and each code is the publisher's SDMX agency ID where it has one. |
| U2 and B0 in `SDMX:CL_AREA` | `SDMX:CL_AREA(2.0.1)` has ISO alpha-2 countries and numeric M49 groups only: `098` euro area, `097` EU, `001` world. U2 and B0 are the ECB's codes (`ECB:CL_AREA(1.0)`), which also has `I9` (EA20, fixed composition), `B6` (EU27_2020, fixed), `W0` (world) and `W1` (**rest of** the world). The BIS's `BIS:CL_AREA(1.0)` (101 codes) has `XM` euro area and `XW` world, but no EU and no fixed compositions. | Decided on 20 November 2026: ISO conventions as far as they go. `REF_AREA` uses `AMD:CL_AREA(1.0)`, which extends `SDMX:CL_AREA(2.0.1)`, whose 266 alpha-2 codes are ISO 3166-1, with the codes ISO 3166-1 reserves for the EU (`EU`) and the euro area (`EZ`). ISO has no code for the world, so the world is `XW`, from ISO's user-assigned range (the BIS uses the same code). Sources' codes are mapped by [`registry/area_map.csv`](../registry/area_map.csv). The earlier registry's `W1` for the world GPR index, which the ECB uses for *rest of* the world, is now `XW`. |

There is also no SDMX unit codelist, so `UNIT_MEASURE` reuses the
cross-domain concept with codes in `AMD:CL_UNIT_MEASURE(1.0)`.

## Layers

| Layer | Holds | Format | Where |
|---|---|---|---|
| Bronze | Each answer as the source sent it | The source's bytes, one file per request | `output/bronze/<AGENCY>/<DATAFLOW>/<YYYY-MM-DD>_<hash>.<ext>`, not committed |
| Silver | Every observation fetched, under its source's structure (rules 1 to 3), with no value changed; daily series stay daily | SDMX-CSV 2.0, one file per dataflow and version | `output/silver/<AGENCY>/<DATAFLOW>_<VERSION>.csv`, committed |
| Gold: indicators | `AMD:INDICATORS(1.0)`: one long table of everything published, with every transformation recorded | Parquet, partitioned by `INDICATOR` | `output/gold/indicators/INDICATOR=<CODE>/part-0.parquet` |
| Gold: panels | The FRED-QD- and FRED-MD-style panels, metadata, dummies and semantic layer, derived from the indicator table | As today, unchanged | `output/<cc>_*.csv`, `output/semantic/` |
| Exports | Parquet and SDMX-CSV for analysis; an Excel workbook for users | | `output/exports/` |

Exporting to a database stays outside this repository. Anything that loads
`output/exports/` or the parquet files can do it.

### Bronze

Every fetch first writes the raw answer: the CSV, XML, JSON, zip or workbook,
named by date and a hash of the request URL. A sidecar `.json` records the
URL, the request headers, the HTTP status and the time. Bronze makes a parser
bug recoverable without refetching, and it is what a silver file's manifest
points to. It is not committed. Locally it is a cache, as the landing caches
(`gpr_data`, the EC zips, the degree-day files) are today. In CI it is
uploaded as a workflow artifact with the default retention.

One source is different. OeNB data are fetched with the `oenb` Python package.
It returns a data frame, not the service's XML, so bronze for the OeNB holds
that frame written to CSV. The package passes on what the service returns
without rescaling, so nothing is lost for silver.

### Silver

As designed in [sdmx_silver_layer.md](sdmx_silver_layer.md), with these
additions:

- **A silver file is named by its dataflow and version**
  (`output/silver/ESTAT/NAMQ_10_GDP_1.0.csv`,
  `output/silver/OECD.SDD.STES/DSD_KEI@DF_KEI_4.0.csv`). A new source version
  goes to a new file and never silently changes an old one.
- **Silver accepts only declared dataflows.** A source flow must be listed in
  [`registry/source_dataflows.csv`](../registry/source_dataflows.csv). An AMD
  flow must be listed in [`registry/dataflows.csv`](../registry/dataflows.csv),
  with its structure in
  [`registry/data_structures.csv`](../registry/data_structures.csv). A row
  whose columns or codes do not fit is refused before anything is written.
- **`output/silver/_manifest.csv`** records, for each series key, the run that
  last wrote it, the time, the bronze file it came from and its number of
  observations. The run summary uses it to say what is stale.
- **The IMF has now been checked** (20 November 2026). `IMF.STA:QNEA(7.0.0)`
  answers in SDMX-CSV **2.0** (`STRUCTURE[;],STRUCTURE_ID,ACTION`, with
  `ACTION = R`) whatever the `Accept` header asks for, even when the response's
  `Content-Type` says version 1.0. It also ignored `startPeriod`. The reader
  therefore goes by the header line, never by the content type.
- **The OeNB is fetched with the `oenb` Python package** (version 0.1.0 on
  PyPI), replacing the XML parsing in `R/oenb.R`. The OeNB topic reads the
  series to fetch from the registry and calls `oenb.data(id=, pos=, freq=)`.
  It writes each result to bronze, then into `AMD:OENB(1.0)`. `oenb.data()` returns `period`,
  `pos`, `postitle`, `attr1…attrN` with `attrNdim`, `freq`, `unitmult`,
  `unittext` and `value` (checked 20 November 2026 on
  `23/VDBZSBSZN10010`). These map onto the structure's dimensions and its
  `UNIT_MULT`, `UNIT_MEASURE`, `TITLE` and `OENB_ATTRIBUTES` attributes.
- **Codes are mapped, values are not.** Where a non-SDMX source's identifier
  is not a valid SDMX ID or breaks rule 3 (`^ATX`, the EC's `TOT`, the OeNB's
  hyphens), silver writes the AMD code. The source's spelling is kept as that
  code's `source_code` in `registry/codes.csv`. Values and periods are written
  as sent.

### Gold: AMD:INDICATORS(1.0)

This is the long table, and it is an SDMX dataflow in its own right. Its data
structure, `AMD:DSD_INDICATORS(1.0)`:

| # | Component | Role | Concept | Representation |
|---|---|---|---|---|
| 1 | `FREQ` | dimension | SDMX `FREQ` | `SDMX:CL_FREQ(2.1)`: A, Q, M, D |
| 2 | `REF_AREA` | dimension | SDMX `REF_AREA` | `AMD:CL_AREA(1.0)`: ISO 3166-1 alpha-2, `EU`, `EZ`, `XW` |
| 3 | `INDICATOR` | dimension | SDMX `INDICATOR` | `AMD:CL_INDICATOR(1.0)` |
| 4 | `SUBINDICATOR` | dimension | AMD `SUBINDICATOR` | `AMD:CL_SUBINDICATOR(1.0)`; `_Z` if no breakdown, `_T` for a total |
| 5 | `ADJUSTMENT` | dimension | SDMX `ADJUSTMENT` | `SDMX:CL_SEASONAL_ADJUST(1.0)` |
| 6 | `TIME_PERIOD` | time dimension | SDMX `TIME_PERIOD` | One form per frequency: `2026`, `2026-Q2`, `2026-M04`, `2026-11-20` |
| 7 | `OBS_VALUE` | measure | SDMX `OBS_VALUE` | Double |
| | `UNIT_MEASURE` | attribute, series | SDMX `UNIT_MEASURE` | `AMD:CL_UNIT_MEASURE(1.0)` |
| | `UNIT_MULT` | attribute, series | SDMX `UNIT_MULT` | `SDMX:CL_UNIT_MULT(1.1)` |
| | `BASE_PER` | attribute, series, conditional | SDMX `BASE_PER` | index base period, e.g. `2020` |
| | `DECIMALS` | attribute, series, conditional | SDMX `DECIMALS` | `SDMX:CL_DECIMALS(1.0)` |
| | `DATA_COMP` | attribute, series | SDMX `DATA_COMP` | ID of the transformation that built the series |
| | `EDITION` | attribute, series, conditional | AMD `EDITION` | forecasts only |
| | `OBS_STATUS` | attribute, observation | SDMX `OBS_STATUS` | `SDMX:CL_OBS_STATUS(2.3)` |
| | `SOURCE_AGENCY` | attribute, observation | ECB `SOURCE_AGENCY` | `AMD:CL_SOURCE_AGENCY(1.0)` |
| | `SOURCE_KEY` | attribute, observation | AMD `SOURCE_KEY` | `<structure ID>/<series key>` of the silver input(s) |

Three design points:

- **Names live in the codelists, not in the data.**
  `registry/codes.csv` gives every `INDICATOR`, `SUBINDICATOR` and unit code a
  `name_en` and a `name_de`. Exports join them in. `CL_INDICATOR` is seeded
  with the 51 indicators the 117 panel concepts fold into. The EC survey
  questions, for example, become `CONSUMER_SURVEY` × 13 subindicators. The
  new topics add 17 more. German names are drafted for all of them and need a
  read by a native speaker.
- **`SOURCE_AGENCY` and `SOURCE_KEY` are attached to each observation, not to
  the series.** A spliced series changes source at the splice. Today's
  `real_gdp` is Eurostat from 1995 and the OECD before that. Each observation
  names the silver series it actually came from.
- **`OBS_STATUS` is never invented.** It is the source's own flag, mapped to
  `SDMX:CL_OBS_STATUS(2.3)` by a declared table. For example, Eurostat's `p`
  maps to P, `e` to E and `b` to B, and an unmapped flag stops the build.
  There are two exceptions. A period aggregated from an incomplete set of
  months is flagged P, which is today's "the current quarter can be partial"
  made machine-readable. A forecast year is flagged F.

#### Transformations

Every number in gold is built from silver by a transformation declared in
[`registry/transformations.csv`](../registry/transformations.csv). A
transformation is a chain of operations from `AMD:CL_DATA_COMP(1.0)`:
`SELECT`, `SCALE`, `NEGATE`, `RATIO`, `DEFLATE`, `SUM`, `AGG_MEAN`, `AGG_SUM`,
`AGG_LAST`, `SPLICE_LEVEL`, `SPLICE_APPEND`, `BACKCAST_GROWTH`,
`WEIGHTED_MEAN`, `CALIBRATE` and `RECODE_AREA`. Each one has ordered inputs
(silver keys with `{REF_AREA}`-style placeholders) and parameters. Its ID is
written to `DATA_COMP` on every series it builds. In SDMX terms this is a
small transformation scheme. SDMX 3.0 would express it in VTL, and
`transformations.csv` could gain a VTL column once there is a reason to
execute VTL. For now the R code executes the operation codes.

Six examples are declared now. MDB's cases, checked against the live data:

- RWA density is `E0000 / A0000 × 100` from `ECB:CBD2(1.0)`.
- The cost-income ratio is `NEGATE`, because the ECB publishes it negative
  (−51.6 for AT in 2026-Q2).
- Bank total assets are `SCALE` to millions.

And today's own cases:

- The level splice of the OECD QNA onto Eurostat.
- The daily CISS averaged to months.
- The monthly CISS averaged to quarters.

Everything today's fetchers do to values moves here. That includes the
splices in `splice_prefer()`, the MIR pure-new-loans backcast, the deflation
of disposable income, the weighting and calibration of the degree days, the
switch from the OECD MEI rate to Euribor at euro adoption, and every
monthly-to-quarterly aggregation.

**Frequency conversion is a gold transformation too.** The quarterly series of
a monthly concept is its own `FREQ = Q` series in `AMD:INDICATORS`, built
with `AGG_MEAN` or `AGG_SUM` and declared like any other. As a result, the
panels are pure pivots of the indicator table.

### Gold: the panels

[`registry/panel_columns.csv`](../registry/panel_columns.csv) maps each of
the 117 panel columns to its `INDICATOR`, `SUBINDICATOR` and `ADJUSTMENT`.
For example, `core_cpi_index` maps to `CPI`, `CORE`, `N`. A panel is the
indicator table filtered to one `REF_AREA` and one `FREQ`, pivoted by that map,
with `date` derived from `TIME_PERIOD` as the period's first day.
`<cc>_metadata.csv`, `availability.csv` and the semantic layer are built from
the same rows. Their `key` column becomes the observation-level `SOURCE_KEY`s
and the splice periods, so it no longer depends on a hand-written sentence.

The acceptance test for this layer: a build through the indicator table writes
every existing gold file byte-identical to a build of the current code from
the same silver.

### Exports

- `output/exports/AMD_INDICATORS_1.0.csv`: the whole indicator table as
  SDMX-CSV 2.0 (`STRUCTURE = dataflow`, `STRUCTURE_ID = AMD:INDICATORS(1.0)`).
- `output/exports/indicators.parquet`: the same table as a single file, for
  people who do not want a partitioned directory.
- `output/exports/structures.xml`: the AMD registry as an SDMX-ML 3.0
  structure message, generated from `registry/`, so that SDMX tools (the .Stat
  Suite, the Fusion Metadata Registry, `rsdmx`, `sdmx1`) can read the
  structures.
- `output/exports/AustriaMacroData.xlsx`, for users. It has four sheets:
  - **About**: the as-of date, the run date and the git commit.
  - **Data**: the long table, with each code followed by its English and
    German label, and `PERIOD_START` and `PERIOD_END` derived from
    `TIME_PERIOD`.
  - **Indicators**: the codelist.
  - **Sources**: the source dataflows.

  Daily series are left out of the Excel file, because of its row limit.

## Dates

`TIME_PERIOD` is the key in every layer from gold onwards, in SDMX's
reporting forms: `2026` (A), `2026-Q2` (Q), `2026-M04` (M) and `2026-11-20`
(D). These are SDMX's forms, kept rather than ISO 8601's (decided 20
November 2026), because ISO 8601 has no quarter and the panels already use
`2026-M04`. Silver keeps a period as the source wrote it. Every source's form is a
valid SDMX time period, but the forms differ: Eurostat, the ECB and the OeNB
write `2026-07`, FRED and the EC workbooks a first day, `2026-07-01`. Writing
the period in one reporting form is gold's first step, which is a normalisation
of the key, not of a value. Dates (`PERIOD_START`, `PERIOD_END`) are derived for
display and never stored as the key. The panels keep their first-day `date`
column, derived the same way.

## Topics and the run

As in MDB, the pipeline is split into topics, and each topic is one function.
The differences are in validation and in reporting.

- **A topic fetches and returns silver.** `topics.<name>.fetch(ctx)` returns
  a dict of data frames keyed by structure ID. Each frame must match its
  declared structure. The runner validates them and writes them to silver. A
  gold builder, `topics.<name>.build(silver)`, returns rows in the fixed
  `AMD:DSD_INDICATORS` schema, and those are validated too.
- **A topic declares what it expects:** the silver series keys its
  transformations name. After it runs, the runner compares what was expected
  with what arrived. A series that did not arrive is a failure with a name,
  not an empty column found a month later.
- **One failing topic does not stop the run.** Each topic runs inside a
  `try` block, with `warnings.catch_warnings(record=True)` collecting its
  warnings. A failed topic leaves its silver files as they were. Gold is rebuilt from
  silver, so its series keep their last good data, and the manifest marks
  them stale.
- **Every failure is reported.** `output/run_summary.json` and
  `output/run_summary.md` give, for each topic:
  - its status (`ok`, `partial` or `failed`);
  - its duration and its warnings;
  - the expected series that did not arrive;
  - the stale series, each with the date of its last good fetch.

  Both files are committed with the output. The CI job commits the output first
  and then fails if any topic failed, so a broken source shows as a red run
  rather than a quiet NA.

The topics, with the existing fetchers grouped and the new ones added:

| Topic | Today in | Sources (silver dataflows) |
|---|---|---|
| `national_accounts` | `eurostat.R`, `oecd.R`, `imf.R`, `inventories.R`, `population.R`, `employment.R` | `ESTAT:NAMQ_10_*`, `NASQ_10_NF_TR`; `OECD.SDD.NAD:*`; `IMF.STA:QNEA(7.0.0)`; `AMD:FRED` |
| `labour_activity` | `eurostat_sts.R` | `ESTAT:STS_*`, `UNE_RT_M` |
| `prices` | `eurostat.R` (HICP), `construction_costs.R`, `commodities.R` | `ESTAT:PRC_HICP_MINR`, `STS_COPI_*`; `AMD:FRED` |
| `surveys` | `ec_survey.R` | `AMD:EC_BCS(1.0)` |
| `rates` | `ecb_market_rates.R`, `gov_yields.R`, `ecb.R` (MIR) | `ECB:FM`, `IRS`, `MIR`; `BBK:BBSIS(1.0)`; `AMD:FRED`; `AMD:OENB` (23) |
| `credit` | `bis.R`, `ecb.R` (BSI, QSA) | `BIS:WS_TC(2.0)`; `ECB:BSI`; `ECB.DISS:QSA_PUB`; `AMD:OENB` (100140002) |
| `fiscal` | `eurostat.R` (primary balance) | `ESTAT:GOV_10Q_GGNFA` |
| `financial_markets` | `ecb.R` (CISS), `yahoo_finance.R` | `ECB:CISS(1.0)`; `AMD:YAHOO(1.0)`; `AMD:FRED` |
| `external` | `fred_mirror.R` (exchange rates) | `AMD:FRED` |
| `weather` | `weather.R` | `ESTAT:NRG_CHDD_M`; `AMD:OPEN_METEO(1.0)` |
| `world` | `gpr.R`, `global_activity.R`, `commodities.R` | `AMD:GPR(1.0)`; `AMD:FRED` |
| `policy_events` | `dummies.R` | `AMD:POLICY_EVENTS(1.0)` |
| **`banks`** (new) | – | `ECB:CBD2(1.0)` |
| **`fdi`** (new) | – | `ESTAT:BOP_FDI6_POS`, `BOP_IIP6_Q`; `AMD:OENB` (902, Austria excl. SPEs) |
| **`current_account`** (new) | – | `ESTAT:BOP_GDP6_Q`, `BOP_C6_Q` |
| **`insolvencies`** (new) | – | `ESTAT:STS_RB_Q` |
| **`government_deficit`** (new) | – | `ESTAT:GOV_10Q_GGNFA` (B9, quarterly), `GOV_10DD_EDPT1` (annual, EDP) |
| **`forecasts`** (new) | – | `OECD.ECO.MAD:DSD_EO@DF_EO(1.5)`; `IMF.RES:WEO(9.0.0)` |

### The new topics

All their source dataflows were checked live on 20 November 2026 to exist,
in the versions above. Their series keys have not yet been fetched. Choosing
those keys is part of implementing each topic.

- **Banks: CET1, T1, NPL, coverage, LCR, cost-income, RWA density and total
  assets.** These come from `ECB:CBD2(1.0)`, using the same items MDB used:
  - CET1 is I4008, T1 is I4002, NPL is I3632 and coverage is I3631.
  - Cost-income is I2100, and the ECB publishes it negative.
  - LCR is I3017.
  - Total assets is A0000, and risk-weighted assets is E0000.

  The ECB's data structure has 16 dimensions. Their reporting-sector code
  differs by area: 67 for a country, 57 for U2, 47 for B0. This has to be
  confirmed against the codelist. RWA density, the sign change and the scaling
  are gold transformations. For Austria the OeNB's data set 3104 has
  regulatory capital in more detail. CBD2 stays the cross-country source.
- **FDI.** Positions and flows come from Eurostat's BPM6 flows. For Austria
  the OeNB publishes direct investment **excluding SPEs** (data set 902,
  `VDBDSA5---KSALD---UP` and siblings). SPEs dominate Austria's gross FDI
  figures, which makes this series worth having, and it comes through the
  `oenb` package.
- **Current account.** Eurostat's `bop_gdp6_q` gives the balance in percent of
  GDP, broken down into goods, services, primary income and secondary income.
- **Insolvencies.** Eurostat's `sts_rb_q` publishes an index of declarations
  of bankruptcy. A count of insolvencies needs a national source and is out of
  scope until one with a machine-readable API is found.
- **Government deficit.** B9 (net lending) of general government is a second
  item in `gov_10q_ggnfa`, which is already fetched, and the annual EDP figure
  is in `gov_10dd_edpt1`. It is published with the ESA sign, so a deficit is
  negative. A "deficit" with the sign reversed would be its own declared
  transformation.
- **Forecasts.** These come from the OECD's Economic Outlook and the IMF's
  WEO, both of which are SDMX. The IMF publishes each WEO edition as its own
  dataflow (`IMF.RES:WEO_2026_APR_VINTAGE(1.0.0)`), so the edition is in the
  silver key. In gold, a forecast is its own indicator
  (`FORECAST_REAL_GDP_GROWTH` and the like). The forecaster goes in
  `SUBINDICATOR` (`OECD_EO`, `IMF_WEO`), the edition in `EDITION`, and forecast
  years carry `OBS_STATUS = F`. Gold keeps only the latest edition, and the
  vintages keep the earlier ones. Austrian forecasters (WIFO, IHS, OeNB) follow
  only if they publish machine-readable forecasts.
- **Euro-area and EU aggregates** are not a topic of their own. They are
  `REF_AREA` values in every topic whose source publishes them: the CISS for
  U2, CBD2 for U2 and B0, and the Eurostat flows for EA20 and EU27_2020.
  Silver keeps the source's code. Gold maps it to `EZ` or `EU` by
  `RECODE_AREA`, following [`registry/area_map.csv`](../registry/area_map.csv),
  and the same map turns Eurostat's `EL` and `UK` into ISO's `GR` and `GB`.
  ISO has no codes for fixed and changing compositions. So `EZ` means the
  euro area as the source defines it, and the observation's `SOURCE_KEY`
  says which composition that is (U2 changing, EA20 fixed). Each aggregate
  series is declared from one source, so the two compositions are never mixed
  within a series. Wide panels for the euro area and the EU are not in this
  scope. They would be one more pivot.
- **CISS** is already fetched. `fetch_ecb_ciss()` (`R/ecb.R:445`) requests
  `CISS/D.<cc>.Z0Z.4F.EC.SS_CIN.IDX` for each country and averages the daily
  values within the month (`R/panel_monthly.R:250`). What is missing is the
  euro-area CISS, `D.U2.Z0Z.4F.EC.SS_CIN.IDX`, which is published daily and
  was checked live. It becomes one more key in the `financial_markets` topic.

## The registry

Everything AMD declares is in [`registry/`](../registry/). The registry is
kept as CSV, so that changes are readable in a diff, and is exported as
SDMX-ML.

| File | SDMX artefact | Holds |
|---|---|---|
| [`concepts.csv`](../registry/concepts.csv) | Concept scheme `AMD:AMD_CONCEPTS(1.0)` | The 19 concepts SDMX has none for, with each one's core representation |
| [`codelists.csv`](../registry/codelists.csv) | Codelists | The 20 `AMD:CL_*` codelists, with names in English and German. `AMD:CL_AREA` extends `SDMX:CL_AREA(2.0.1)`, as SDMX 3.0 lets a codelist extend another |
| [`codes.csv`](../registry/codes.csv) | Codes | 346 codes. Each has a parent, English and German names, a description and, where silver maps a source identifier, the `source_code` |
| [`data_structures.csv`](../registry/data_structures.csv) | Data structures `AMD:DSD_*(1.0)` | 8 structures. Each component has its position, role, concept (by full reference), representation, attachment level and assignment status |
| [`dataflows.csv`](../registry/dataflows.csv) | Dataflows `AMD:*(1.0)` | The 8 AMD dataflows, by layer |
| [`source_dataflows.csv`](../registry/source_dataflows.csv) | References to source dataflows | The 37 source dataflows silver accepts, with the date each was checked and the layout it answers in |
| [`external.csv`](../registry/external.csv) | References to SDMX and ECB artefacts | Every non-AMD concept scheme and codelist the AMD structures use, with the date each was checked |
| [`area_map.csv`](../registry/area_map.csv) | (Representation map) | Each source's area codes mapped to `AMD:CL_AREA` |
| [`transformations.csv`](../registry/transformations.csv) | (Transformation scheme) | The gold derivations; six examples so far |
| [`panel_columns.csv`](../registry/panel_columns.csv) | (Mapping) | Panel column to indicator series |

It replaces `docs/sdmx_structures.csv` and changes it in four ways:

- Every dimension is now coded. Silver's identifiers (FRED series, OeNB
  positions, locations, tickers) have codelists that list the codes in use.
  The earlier choice to leave them uncoded broke rule 3.
- The EC survey structure follows the Commission's series code
  (`SURVEY.COUNTRY.ACTIVITY.QUESTION.ANSWER.FREQ`).
- `ADJUSTMENT` now points at a codelist that exists.
- `REF_AREA` uses ISO codes, and the world GPR index is `XW`.

**Versioning** follows the ECB's practice. Every artefact is version 1.0 and
not final, so codes may be added without a new version. A change that alters
what an existing code or component means, or the order of a structure's
dimensions, gets a new major version. A new version of a dataflow writes a new
silver file.

**Validation**, to be implemented as `tests/test_registry.py` and in the
writers:

- Every code is an upper-case SDMX ID (`[A-Z0-9_]+`) with an English name.
- Every component's concept and codelist is declared in `concepts.csv` and
  `codelists.csv`, or listed in `external.csv`.
- Every dataflow has a structure.
- Every panel column maps to declared codes.

A prototype of these checks already passes on the committed files. The writers
refuse any row whose dimension values are not in the codelist. For an
external codelist the check uses a cached copy, `registry/external/<id>.csv`,
fetched by `python -m amd registry fetch-external` and refreshed
deliberately, never at build time.

## Python, not R

The pipeline is ported to Python, which is installed on the Pi, so all of it
can be run and tested here. The R code stays in place until the Python build
has been shown to give the same panels. After that it is removed in one
commit.

- **Package.** `amd/`, run as `python -m amd <command>`, with these modules:
  - `amd.registry`: loads `registry/` and validates against it.
  - `amd.bronze`: one `fetch()` for every request, which writes bronze, retries
    as `safe_get()` does today, and is the single point the tests mock.
  - `amd.sdmx_csv`: reads the four answer layouts and writes SDMX-CSV 2.0.
  - `amd.silver`: the writer and the manifest.
  - `amd.topics.*`: one module per topic.
  - `amd.gold`: the transformation operations and the indicator table.
  - `amd.panels`: the pivots, metadata and dummies.
  - `amd.semantic`: the semantic layer and the query API.
  - `amd.exports`: SDMX-CSV, parquet, SDMX-ML and Excel.
  - `amd.run`: the topic runner and the run summary.
- **Dependencies**, pinned in `pyproject.toml`: pandas, pyarrow, requests,
  openpyxl (for the EC workbooks and the Excel export), oenb and pytest. No
  SDMX client library is needed, since every source is read as CSV.
- **What users see.** The query CLI becomes `python -m amd query search|describe|get|list`,
  with the same arguments as `scripts/query.R`. `AGENTS.md` and the README are
  updated in the same commit. Python cannot offer `amd_get()` and its siblings
  to R users, so R users read the parquet or CSV files directly. Keeping a thin
  R reader would mean keeping R in CI, which is a choice for later.
- **Tests.** The `tests/testthat` suite is ported to pytest, test by test.
  The canned responses in `helper-mocks.R` become fixtures.
- **CI.** `monthly-update.yml` sets up Python instead of R. During the port, a
  second workflow runs both builds on the same day and compares them.

**Parity check.** A build fetches live data, so two runs can differ because
a source revised its figures. The comparison therefore runs on the same
bytes:

1. The R build in CI records every answer it receives. This is a small change
   to `fetch_text()`, the one function every R fetcher goes through, and it is
   the only R change in the plan.
2. The Python build replays those answers from bronze.
3. Each panel, metadata and semantic file is compared value by value, to
   within 1e-9 relative, and column by column.

Byte identity of the CSVs also depends on number formatting, because R writes
15 significant digits. The Python writer copies that, and the check reports
both the value differences and the byte differences.

## Implementation steps

1. **The `amd` package skeleton, `amd.registry` and its tests.** These run on
   the Pi.
2. **Bronze, the runner and the run summary**, with the Bundesbank, the IMF
   and the OeNB through `oenb` as the first topics.
3. **The recording hook in R's `fetch_text()`** and the parity workflow in CI.
4. **The SDMX sources' topics**: Eurostat, the OECD, the BIS and the ECB,
   written to silver.
5. **The non-SDMX sources' topics**: FRED, the EC surveys, Yahoo, Open-Meteo,
   the GPR and the policy events.
6. **`AMD:INDICATORS` built from silver.** Every transformation the R fetchers
   do today becomes a declared transformation.
7. **The panels, metadata, dummies and semantic layer**, then the query CLI.
   The parity workflow must pass before step 8.
8. **Switch CI to Python, then remove the R code**, and update `AGENTS.md`,
   the README and `CONTRIBUTING.md`.
9. **Exports:** parquet, SDMX-CSV, SDMX-ML structures and the Excel workbook.
10. **New topics**, one commit each: banks, FDI, current account,
    insolvencies, government deficit, forecasts, and
    the aggregates.

The steps up to 7 change no published file. Step 10 adds data.

## Decisions

Made on 20 November 2026:

- **`output/silver/` is committed.**
- **Daily series stay daily in silver.**
- **The pipeline moves to Python.**
- **`REF_AREA` follows ISO conventions** as far as they go: ISO 3166-1
  alpha-2 for countries, ISO's reserved `EU` and `EZ`, and `XW` for the world.
- **`TIME_PERIOD` stays in SDMX's forms** (`2026-M04`), not ISO 8601's.
- **The fundamental house price indicator is dropped.** It is not in the
  OeNB web service, and the ECB's `RESV` estimates are not taken in its
  place.

## Not yet verified

- The ECB's `CB_REP_SECTOR` codes 57 and 47 for U2 and B0, and every new
  topic's series keys. Only the dataflows' existence and versions were
  checked.
- The IMF WEO answer layout. It is assumed to be the same as QNEA's.
- The German names in `registry/codes.csv`, which were drafted, not reviewed.
- The registry's `CL_FRED_SERIES` holds the series in the fetch templates for
  AUT, DEU and USA. A test that compares it with what the fetchers request
  will find any it misses.
