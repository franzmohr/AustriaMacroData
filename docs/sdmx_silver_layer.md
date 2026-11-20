# An SDMX silver layer

Status: design, not yet implemented. Written 20 November 2026. The whole
pipeline, from bronze to the exports, and the AMD registry are designed in
[sdmx_pipeline.md](sdmx_pipeline.md); this document details the silver layer.
The pipeline is being ported to Python (decided 20 November 2026). Where
this document names R functions, it describes today's code, which the Python
port replaces.

## What changes

Today every fetcher reduces what a source sends to two columns, a period
and a value, and the panels are built straight from those. Everything else
the source said is dropped where the response is parsed: the series key,
the unit and its multiplier, the observation status, the decimals. The only
record of where a number came from is the free-text `key` column of
`<cc>_metadata.csv`, such as `namq_10_gdp:B1GQ (extended pre-1995 with
level-spliced OECD_QNA:S1.B1GQ)`.

The silver layer keeps that information. It sits between the sources and
the panels:

| Layer | Holds | Shape |
|---|---|---|
| Bronze | each response as the source sent it | the existing landing caches (`gpr_data`, the EC survey zips, the degree-day files), extended to every source |
| **Silver** | **every observation fetched, under its source's own SDMX structure** | **SDMX-CSV 2.0, one file per dataflow** |
| Gold | the long indicator table `AMD:INDICATORS(1.0)`, and derived from it the FRED-QD- and FRED-MD-style panels, metadata, dummies, the semantic layer | parquet for the indicator table; the panels as today, unchanged for anyone reading them |

Silver is lossless and source-shaped: it says what Eurostat, the ECB or the
OECD published, under their own codes, before any choice of this project is
applied. Splicing, the switch from one provider to another, frequency
conversion and transformation codes all stay in gold, where they are today.
A gold column becomes a function of silver series named by their SDMX keys,
so its provenance is a key that can be looked up, not a sentence.

## The silver format

One file per dataflow and version, under
`output/silver/<AGENCY>/<DATAFLOW>_<VERSION>.csv`, in SDMX-CSV 2.0. An answer in SDMX-CSV 1.0, as most sources send it (see below),
becomes 2.0 by turning its `DATAFLOW` column into `STRUCTURE = dataflow`,
`STRUCTURE_ID` and `ACTION = I`:

```
STRUCTURE,STRUCTURE_ID,ACTION,<dimensions in DSD order>,TIME_PERIOD,OBS_VALUE,<attributes>
dataflow,ESTAT:NAMQ_10_GDP(1.0),I,Q,CLV10_MEUR,SCA,B1GQ,AT,2026-Q2,...,...
```

- **The dimensions are the source's own, in its DSD order.** A Eurostat row
  keeps `freq`, `unit`, `s_adj`, `na_item`, `geo`; an ECB row keeps the 7 to 13
  dimensions of its dataflow. `R/eurostat_dimensions.R` already declares
  the order for every Eurostat flow the project requests, and the guard
  there stays: a response whose dimensions differ from the declared ones
  stops the build before anything is written.
- **The attributes are kept where the source sends them:** `OBS_STATUS`,
  `OBS_FLAG`, `UNIT_MULT`, `DECIMALS`, `TITLE` and the like. A source that
  sends none gets none. Silver does not invent attributes.
- **`TIME_PERIOD` is written as the source sent it.** The panels already use
  SDMX's reporting-period forms, `2026-Q2` and `2026-M04`; silver keeps
  whichever valid SDMX form the source used (`2026-07`, `2026-07-01`), and
  gold writes one form per frequency. Whether daily data (`2026-11-20`) stays
  daily in silver is an open decision (see sdmx_pipeline.md); frequency
  conversion is gold's job either way.
- **One file per dataflow, not per country.** A fetch adds or replaces the
  series it asked for (`ACTION = I`), keyed on the full series key. Building
  AUT, DEU and USA writes into the same files, and every series is fetched
  once.

### Where it is captured

Every SDMX response already goes through one function,
`parse_time_value_csv()` in `R/utils.R`. It finds `TIME_PERIOD` and
`OBS_VALUE` by name and drops the rest. The capture goes there: before the
reduction, the full rows are handed to a `write_silver()`, then reduced as
now, so the panels come out identical.

With the formats requested today, the function cannot work out the structure from the response alone. The
four SDMX sources answer the requests this project makes in four different
layouts (checked live on 20 November 2026 with one small request each):

| Source | Request | Header of the answer | Structure ID in the answer | Dimensions |
|---|---|---|---|---|
| Eurostat | `format=SDMX-CSV` | `DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS` | yes, `ESTAT:NAMQ_10_GDP(1.0)` in `DATAFLOW` (SDMX-CSV 1.0) | the lower-case columns before `TIME_PERIOD` |
| OECD | `format=csvfilewithlabels` | `STRUCTURE,STRUCTURE_ID,STRUCTURE_NAME,ACTION,REF_AREA,Reference area,FREQ,...` | yes, `OECD.SDD.STES:DSD_KEI@DF_KEI(4.0)` in `STRUCTURE_ID` (SDMX-CSV 2.0) | every code column is followed by a label column, which silver drops |
| ECB | `format=csvdata` | `KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE,OBS_STATUS,...` | no; the dataflow is the first segment of `KEY`, the version is not stated | the columns between `KEY` and `TIME_PERIOD` |
| BIS | `format=csv` | `FREQ,BORROWERS_CTY,...,TC_ADJUST,COLLECTION,DECIMALS,UNIT_MULT,UNIT_MEASURE,TITLE_TS,TIME_PERIOD,OBS_VALUE,...` | no | not separable: series attributes (`COLLECTION`, `DECIMALS`, `UNIT_MULT`, `UNIT_MEASURE`, `TITLE_TS`) stand before `TIME_PERIOD` with the dimensions |

Most of that is the choice of format, not the source. Asked for standard
SDMX-CSV through the SDMX media type (`Accept:
application/vnd.sdmx.data+csv;version=1.0.0`, checked live on the same
day), three of the four answer in one layout:

| Source | Header with the SDMX media type |
|---|---|
| Eurostat | `DATAFLOW,LAST UPDATE,freq,unit,s_adj,na_item,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS` |
| OECD | `DATAFLOW,REF_AREA,FREQ,MEASURE,UNIT_MEASURE,ACTIVITY,ADJUSTMENT,TRANSFORMATION,TIME_PERIOD,OBS_VALUE,OBS_STATUS,UNIT_MULT,DECIMALS,BASE_PER` |
| BIS | `DATAFLOW,FREQ,BORROWERS_CTY,TC_BORROWERS,TC_LENDERS,VALUATION,UNIT_TYPE,TC_ADJUST,TIME_PERIOD,OBS_VALUE,COLLECTION,UNIT_MULT,...` |
| ECB | refused: the ECB offers only its own CSV (`text/csv` or `application/vnd.ecb.data+csv`, the `csvdata` above) and SDMX-ML |

In SDMX-CSV 1.0 the dataflow and its version are in `DATAFLOW`, the
dimensions are the columns between it and `TIME_PERIOD`, and the
attributes follow `OBS_VALUE` (Eurostat adds `LAST UPDATE`, which silver
keeps as an attribute). The BIS asked this way puts its series attributes
after `OBS_VALUE` as well. So the capture is:

1. **Request SDMX-CSV from Eurostat, the OECD and the BIS** through the
   media type. The OECD's `csvfilewithlabels` and the BIS's `format=csv`
   go; Eurostat's `format=SDMX-CSV` already is this layout. The
   structure, the dimensions and the attributes are then read from the
   answer itself.
2. **Read the ECB's `csvdata` as it is.** The dataflow is the first segment
   of `KEY`, the dimensions are the columns between `KEY` and
   `TIME_PERIOD`, and the attributes follow `OBS_VALUE`. The version is not
   in the answer; every ECB dataflow this project uses is version 1.0
   (`ECB:EXR(1.0)` and `ECB:MIR(1.0)` checked against the ECB's structure
   API), which the ECB reader states and checks against that API in a test.
3. **Check the dimensions against a declaration** where one exists:
   `R/eurostat_dimensions.R` declares them for every Eurostat flow, and
   its guard stays. A declaration for the others can follow; it is a check,
   not what the capture depends on.

Two more sources speak SDMX and need only their request changed:

- **Bundesbank** (`R/gov_yields.R`). The key is already SDMX
  (`BBSIS.M.I.ZST.ZI.EUR.S1311.B.A604.R05XX.R.A.A._Z._Z.A`), but it is
  requested in the Bundesbank's own CSV layout, with a metadata header block
  and `.` for a missing day. With the SDMX media type the service answers
  in SDMX-CSV 1.0, `DATAFLOW = BBK:BBSIS(1.0)` (checked live on 20 November
  2026), separated by semicolons and opening with a byte-order mark, which
  the reader has to allow for.
- **IMF** (`R/imf.R`) already asks its SDMX 3.0 API (`IMF.STA/QNEA/7.0.0`)
  for CSV, with an explicit `Accept` header because the query parameter
  alone is not always honoured. Checked live on 20 November 2026: it answers
  in SDMX-CSV **2.0** (`STRUCTURE[;],STRUCTURE_ID,ACTION,COUNTRY,INDICATOR,...`,
  `STRUCTURE_ID = IMF.STA:QNEA(7.0.0)`, `ACTION = R`) whether `text/csv` or
  either SDMX-CSV media type is asked for, while its `Content-Type` echoes the
  version asked for. The reader goes by the header line. It also ignored
  `startPeriod` and sent the series from 1995.

## Sources that are not SDMX

Some sources publish no SDMX at all. For each, silver gets a dataflow of
this project's own, under the agency `AMD`. Each has a declared data
structure: the dimensions that identify a series at that source, the
SDMX cross-domain concepts and codelists where one applies (`CL_FREQ`,
`CL_SEASONAL_ADJUST`, `CL_OBS_STATUS`, `CL_UNIT_MULT`), and AMD codelists of
the source's own identifiers where none does. The structures, their concepts
and codelists are declared in [`registry/`](../registry/) (see
sdmx_pipeline.md). The writer refuses a row that does not fit its declared
structure.

| Source | Today | Silver dataflow | Series key | Better: an SDMX source for the same data |
|---|---|---|---|---|
| FRED graph export (`fred_mirror.R`) | CSV of one series | `AMD:FRED(1.0)` | `FREQ.FRED_SERIES`, e.g. `Q.IRLTLT01ATQ156N` | Most FRED-mirrored series are OECD MEI or BIS series under another name. Each mirrored series should name its original, and the fetch should move to the OECD or BIS SDMX API where the original is still published. FRED stays only for what has no SDMX original. |
| EC Business and Consumer Surveys (`ec_survey.R`) | zipped workbooks | `AMD:EC_BCS(1.0)` | `FREQ.REF_AREA.SURVEY.ACTIVITY.QUESTION.ANSWER.ADJUSTMENT`, from the Commission's series code `SURVEY.COUNTRY.ACTIVITY.QUESTION.ANSWER.FREQ`, e.g. `M.AT.CONS._T.2.BS.S` | Eurostat republishes the surveys as SDMX (`ei_bsin_m_r2`, `ei_bsco_m`, `ei_bsbu_m_r2`, `ei_bsrt_m_r2`, `ei_bsse_m_r2`, `teibs010` and siblings). Check whether every indicator used is there, with the same history, then switch. |
| OeNB data service (`oenb.R`) | its own XML; to be fetched with the `oenb` Python package | `AMD:OENB(1.0)` | `FREQ.OENB_DATASET.OENB_POSITION`, e.g. `M.23.VDBZSBSZN10010` | The two series are Austrian MFI statistics. The ECB's `MIR` dataflow, which `ecb.R` already uses for `mortgage_rate`, is the harmonised SDMX counterpart. Where it carries the same concept over the same span, switch; where the OeNB series differs in coverage (the new-lending series excludes revolving loans), keep it as a declared source. |
| Yahoo Finance (`yahoo_finance.R`) | JSON chart API | `AMD:YAHOO(1.0)` | `FREQ.TICKER.PRICE_TYPE`, e.g. `D.ATX.CLOSE` (Yahoo's `^ATX`) | None for the ATX itself. The ECB's `FM` dataflow has euro-area equity indices; keep Yahoo for the ATX. |
| Open-Meteo (`weather.R`) | JSON | `AMD:OPEN_METEO(1.0)` | `FREQ.LOCATION.VARIABLE`, e.g. `D.VIENNA.TEMPERATURE_2M_MEAN` | `weather.R` already takes Eurostat's `nrg_chdd_m` first, which is SDMX and lands in silver under `ESTAT`. Open-Meteo is the second source for the months Eurostat does not yet cover, and needs the declared structure only for those. |
| Geopolitical Risk Index (`gpr.R`) | workbook | `AMD:GPR(1.0)` | `FREQ.REF_AREA.GPR_INDEX`, e.g. `M.DE.GPRC` (`REF_AREA = W0` for the world index; Austria has no country index) | None. |
| Policy events (`dummies.R`, `docs/policy_events.csv`) | hand-kept table | `AMD:POLICY_EVENTS(1.0)` | `FREQ.REF_AREA.EVENT` | None. These are this project's own records and belong in gold, but declaring them this way lets the dummies be read with the rest. |

Every dimension is coded. `FRED_SERIES`, `OENB_POSITION`, `LOCATION` and
`TICKER` have AMD codelists listing the identifiers in use; where the
source's identifier is not a valid SDMX ID or breaks the AMD conventions
(`^ATX`, the EC's `TOT`, the hyphens in OeNB positions), the code is the
valid form and the source's spelling is the code's `source_code`.

## What gold gains

- **`<cc>_metadata.csv` and `availability.csv` name silver keys.** The `key`
  column becomes one or more full keys, `ESTAT:NAMQ_10_GDP(1.0)/Q.CLV10_MEUR.SCA.B1GQ.AT`,
  and a splice is two keys with the splice date, not a sentence. The
  semantic layer can then answer "which series is this built from" by
  lookup.
- **Units come from the source.** Today `unit` is text written by hand per
  concept. Silver carries `UNIT_MEASURE` and `UNIT_MULT` where the source
  sends them, and the hand-written text can be checked against them.
- **A build can be replayed without fetching anything.** Gold is a function
  of silver, so the panels can be rebuilt from `output/silver/` alone. This
  is what the vintages are for today, at the level of the finished panels.

## Steps

1. **Capture without changing anything.** Request SDMX-CSV from Eurostat,
   the OECD and the BIS, add `write_silver()` and call it from
   `parse_time_value_csv()`, with the ECB's `csvdata` read as described
   above. Test: a full build writes
   `output/silver/` and leaves every gold file byte-identical to a build
   without it.
2. **Declare the non-SDMX structures** in `registry/` and
   capture those sources through the same writer. Each fetcher hands its
   parsed rows over with the key columns its structure declares.
3. **Switch the Bundesbank request to SDMX-CSV**, and read the IMF's SDMX-CSV 2.0.
4. **Name silver keys in gold's metadata**, replacing the free-text `key`.
5. **Build gold from silver.** The panel builders read `output/silver/`
   instead of the fetchers' return values. After that, a fetch only fills
   silver.
6. **Move the non-SDMX sources to SDMX sources** where the table above
   names one, one source at a time, each checked against the series it
   replaces.

Steps 1 and 2 change no published number. Step 6 can, and each switch is
recorded in `docs/data_sources.csv` as any change of provider is today.

## Open questions

- **Size.** Silver holds full source histories for three countries. Whether
  it is committed or kept as a build artefact of the monthly job is an open
  decision (sdmx_pipeline.md).
- **Daily series.** The Bundesbank yields, Yahoo and Open-Meteo are daily
  at source. Keeping them daily in silver is correct but is most of the
  volume; the alternative is to request the monthly frequency where the
  source has one (the Bundesbank does, as `freq = "M"`).
- **Versioned dataflows.** The OECD versions its dataflows and renames
  them from time to time. The structure ID in silver includes the version,
  so a new version becomes a new file rather than silently changing an old
  one; gold then has to say which version it reads.
