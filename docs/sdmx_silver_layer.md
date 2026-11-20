# An SDMX silver layer

Status: design, not yet implemented. Written 20 November 2026.

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
| Gold | the FRED-QD- and FRED-MD-style panels, metadata, dummies, the semantic layer | as today, unchanged for anyone reading them |

Silver is lossless and source-shaped: it says what Eurostat, the ECB or the
OECD published, under their own codes, before any choice of this project is
applied. Splicing, the switch from one provider to another, frequency
conversion and transformation codes all stay in gold, where they are today.
A gold column becomes a function of silver series named by their SDMX keys,
so its provenance is a key that can be looked up, not a sentence.

## The silver format

One file per dataflow, under `output/silver/<AGENCY>/<DATAFLOW>.csv`, in
SDMX-CSV 2.0:

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
  SDMX's reporting-period forms, `2026-Q2` and `2026-M04`. Daily data
  (`2026-11-20`) stays daily in silver; frequency conversion is gold's job.
- **One file per dataflow, not per country.** A fetch adds or replaces the
  series it asked for (`ACTION = I`), keyed on the full series key. Building
  AUT, DEU and USA writes into the same files, and every series is fetched
  once.

### Where it is captured

Every SDMX response already goes through one function,
`parse_time_value_csv()` in `R/utils.R`. It finds `TIME_PERIOD` and
`OBS_VALUE` by name and drops the rest. The capture goes there: before the
reduction, the full rows are handed to `write_silver(df, structure_id)`,
then reduced as now. No fetcher has to change how it computes its result,
and the panels come out identical. That is the first test (see below).

Two flows need their URL changed first so that the answer is SDMX-CSV with
its dimensions:

- **Bundesbank** (`R/gov_yields.R`). The key is already SDMX
  (`BBSIS.M.I.ZST.ZI.EUR.S1311.B.A604.R05XX.R.A.A._Z._Z.A`), but it is
  requested in the Bundesbank's own CSV layout, with a metadata header block
  and `.` for a missing day. The REST service also answers in SDMX-CSV;
  request that instead.
- **IMF** (`R/imf.R`) already asks its SDMX 3.0 API for CSV, with an
  explicit `Accept` header because the query parameter alone is not always
  honoured. That answer is SDMX-CSV 2.0 and fits as is; the only change is
  to capture it before it is reduced.

## Sources that are not SDMX

Some sources publish no SDMX at all. For each, silver gets a dataflow of
this project's own, under the agency `AMD`. Each has a declared data
structure: the dimensions that identify a series at that source, the
SDMX cross-domain codelists where one applies (`CL_FREQ`, `CL_AREA`,
`CL_OBS_STATUS`, `CL_UNIT_MULT`), and the source's own identifiers where
none does. The structures are declared in one table,
[`docs/sdmx_structures.csv`](sdmx_structures.csv), the same way
`R/eurostat_dimensions.R` declares Eurostat's. The writer refuses a row
that does not fit its declared structure.

| Source | Today | Silver dataflow | Series key | Better: an SDMX source for the same data |
|---|---|---|---|---|
| FRED graph export (`fred_mirror.R`) | CSV of one series | `AMD:FRED(1.0)` | `FREQ.SERIES_ID`, e.g. `Q.IRLTLT01ATQ156N` | Most FRED-mirrored series are OECD MEI or BIS series under another name. Each mirrored series should name its original, and the fetch should move to the OECD or BIS SDMX API where the original is still published. FRED stays only for what has no SDMX original. |
| EC Business and Consumer Surveys (`ec_survey.R`) | zipped workbooks | `AMD:EC_BCS(1.0)` | `FREQ.REF_AREA.SECTOR.INDICATOR.ADJUSTMENT`, from the codes in the workbook's column names | Eurostat republishes the surveys as SDMX (`ei_bsin_m_r2`, `ei_bsco_m`, `ei_bsbu_m_r2`, `ei_bsrt_m_r2`, `ei_bsse_m_r2`, `teibs010` and siblings). Check whether every indicator used is there, with the same history, then switch. |
| OeNB data service (`oenb.R`) | its own XML | `AMD:OENB(1.0)` | `FREQ.HIERID.POSITION`, e.g. `M.23.VDBZSBSZN10010` | The two series are Austrian MFI statistics. The ECB's `MIR` dataflow, which `ecb.R` already uses for `mortgage_rate`, is the harmonised SDMX counterpart. Where it carries the same concept over the same span, switch; where the OeNB series differs in coverage (the new-lending series excludes revolving loans), keep it as a declared source. |
| Yahoo Finance (`yahoo_finance.R`) | JSON chart API | `AMD:YAHOO(1.0)` | `FREQ.TICKER.PRICE_TYPE`, e.g. `D.^ATX.CLOSE` | None for the ATX itself. The ECB's `FM` dataflow has euro-area equity indices; keep Yahoo for the ATX. |
| Open-Meteo (`weather.R`) | JSON | `AMD:OPEN_METEO(1.0)` | `FREQ.LOCATION.VARIABLE`, e.g. `D.VIENNA.TEMPERATURE_2M_MEAN` | `weather.R` already takes Eurostat's `nrg_chdd_m` first, which is SDMX and lands in silver under `ESTAT`. Open-Meteo is the second source for the months Eurostat does not yet cover, and needs the declared structure only for those. |
| Geopolitical Risk Index (`gpr.R`) | workbook | `AMD:GPR(1.0)` | `FREQ.REF_AREA.INDEX`, e.g. `M.DE.GPRC` (`REF_AREA = W1` for the world index; Austria has no country index) | None. |
| Policy events (`dummies.R`, `docs/policy_events.csv`) | hand-kept table | `AMD:POLICY_EVENTS(1.0)` | `FREQ.REF_AREA.EVENT` | None. These are this project's own records and belong in gold, but declaring them this way lets the dummies be read with the rest. |

`LOCATION`, `SERIES_ID`, `TICKER` and `HIERID.POSITION` are left uncoded:
the source's identifier is the code, and silver does not invent a list of
allowed values the source does not publish.

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

1. **Capture without changing anything.** Add `write_silver()` and call it
   from `parse_time_value_csv()`. Test: a full build writes
   `output/silver/` and leaves every gold file byte-identical to a build
   without it.
2. **Declare the non-SDMX structures** in `docs/sdmx_structures.csv` and
   capture those sources through the same writer. Each fetcher hands its
   parsed rows over with the key columns its structure declares.
3. **Switch the Bundesbank and IMF requests to SDMX-CSV.**
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

- **Size.** Silver holds full source histories for three countries. If it
  grows too large for the repository, commit only the gold files and keep
  silver as a build artefact of the monthly job.
- **Daily series.** The Bundesbank yields, Yahoo and Open-Meteo are daily
  at source. Keeping them daily in silver is correct but is most of the
  volume; the alternative is to request the monthly frequency where the
  source has one (the Bundesbank does, as `freq = "M"`).
- **Versioned dataflows.** The OECD versions its dataflows and renames
  them from time to time. The structure ID in silver includes the version,
  so a new version becomes a new file rather than silently changing an old
  one; gold then has to say which version it reads.
