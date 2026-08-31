# -*- coding: utf-8 -*-
"""
generate_technical_report.py -- run from the repository root:
    python docs/generate_technical_report.py

Rebuilds docs/Mohr_AUSTRIA-QD.tex, a working-paper-style technical
report describing how the Austrian counterpart dataset is constructed,
modeled on McCracken and Ng (2020), "FRED-QD: A Quarterly Database for
Macroeconomic Research," Federal Reserve Bank of St. Louis Working Paper
2020-005B (https://doi.org/10.20955/wp.2020.005).

Reuses the existing 14-group FRED-QD variable catalog tables verbatim
(Appendix A) and regenerates the Austria source-mapping table
(Appendix B) fresh from docs/data_sources.csv every run, so the report
never drifts out of sync with what build_country_panel.R actually did.
"""
import re
import csv
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
old_tex_path = os.path.join(script_dir, "Mohr_AUSTRIA-QD.tex")
data_sources_path = os.path.join(script_dir, "data_sources.csv")
out_path = os.path.join(script_dir, "Mohr_AUSTRIA-QD.tex")

with open(old_tex_path, encoding="utf-8") as f:
    old_tex = f.read()

# ---- 1. Pull the 14 group longtables out of the existing document, verbatim ----
group_tables = re.findall(
    r"(\\section\*\{Group: [^}]+\}\s*\\begin\{longtable\}.*?\\end\{longtable\})",
    old_tex, re.S
)
if len(group_tables) != 14:
    raise SystemExit(f"Expected 14 group tables in the existing tex, found {len(group_tables)} -- aborting so nothing is silently lost.")

appendix_a_tables = "\n\n".join(group_tables)

# ---- 2. Concept taxonomy (label -> group, FRED-QD mnemonic, us_note) ----
# Read fresh from docs/concept_dictionary.csv every run, rather than a
# separately hand-transcribed Python copy (the previous approach here,
# and the exact class of risk R/concept_dictionary.R was created to
# eliminate on the R side -- see that file's header: two independently
# maintained tables once silently disagreed about real_gfcf_total's
# FRED-QD mnemonic). docs/concept_dictionary.csv is written by
# scripts/build_country_panel.R directly from R/concept_dictionary.R's
# `concept_dictionary`, the single authored source, every time the CLI
# runs -- so this script can never drift out of sync with it the way the
# old hardcoded copy silently could.
concept_dictionary_path = os.path.join(script_dir, "concept_dictionary.csv")
concept_group_map = []
with open(concept_dictionary_path, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        concept_group_map.append((
            row["label"],
            row["fred_qd_group"],
            row["fred_qd_mnemonic"] or None,
            row["us_note"] or None,
        ))
label_order = [c[0] for c in concept_group_map]
label_to_group = {c[0]: c[1] for c in concept_group_map}

# ---- 2b. EA-MD-QD cross-reference (quarterly series only) ----
# Matches this project's 38 concepts against EA-MD-QD's own QUARTERLY
# indicators (Barigozzi, Lissona and Tonni 2026, Table 1) -- EA-MD-QD's
# 118 EA-level series are roughly 60% quarterly / 40% monthly (Table 2 of
# that paper); only the quarterly ones are in scope here, since the
# monthly majority (all Interest Rates, Financial Markets, Industrial
# Production and Turnover, Prices except DFGDP, and Confidence Indicators
# series) has no meaningful correspondence to this project's own
# quarterly panel at the frequency EA-MD-QD actually publishes it.
# Value is (ea_md_qd_id, caveat) where caveat is:
#   None    -- same concept, same construction, high-confidence match
#   "unit"  -- same broad concept but EA-MD-QD publishes a raw currency
#              LEVEL (from ECB/Eurostat Quarterly Sector Accounts) where
#              this project publishes a BIS-sourced RATIO (% of GDP) --
#              related, not identical, the same kind of caveat this
#              report already carries for several FRED-QD mnemonics
#   "at_gap" -- EA-MD-QD constructs this exact series but its own Table 1
#              confirms (checkmark absent) no observations for Austria
#              specifically -- independent confirmation, from a
#              different vendor, of the same gap this project already
#              found and left \textsc{unresolved} (Section~\ref{sec:coverage})
# Concepts not listed here have no quarterly EA-MD-QD counterpart at all,
# either because EA-MD-QD does not track the concept, or tracks it only
# at monthly frequency.
ea_md_qd_quarterly_map = {
    "real_gdp":                            ("GDP", None),
    "real_household_consumption":          ("HFCE", None),
    "real_govt_consumption":               ("GFCE", None),
    "real_gfcf_total":                     ("GCFC", None),
    "real_exports":                        ("EXPGS", None),
    "real_imports":                        ("IMPGS", None),
    "real_household_disposable_income":    ("AHRDI", "at_gap"),
    "house_price_real":                    ("HPRC", None),
    "household_mortgage_loans":            ("HHLB.LLN", "unit"),
    "household_credit_to_gdp":             ("HHLB", "unit"),
    "corporate_credit_to_gdp":             ("NFCLB", "unit"),
    "government_debt_to_gdp":              ("GGLB", "unit"),
}

# ---- 3. Read the live data-sources registry, filter to Austria ----
with open(data_sources_path, encoding="utf-8", newline="") as f:
    reg_rows = list(csv.DictReader(f))
aut_rows = {r["variable"]: r for r in reg_rows if r["country"] == "AUT"}

_TEX_SPECIAL = {
    "\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
    "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}",
    "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
}

def tex_escape(s):
    if s is None:
        return ""
    s = s.replace('""', "''")
    # Single pass over a character class -- avoids cascading re-escaping
    # that a sequential chain of .replace() calls would cause (e.g. the
    # braces introduced by escaping "^" getting escaped again later).
    return re.sub(r'[\\&%$#_{}~^]', lambda m: _TEX_SPECIAL[m.group(0)], s)

def code_break(s):
    if not s:
        return ""
    s = re.sub(r"(?<=[./:])", r"\\allowbreak{}", s)
    s = s.replace("\\_", "\\_\\allowbreak{}")
    return s

provider_display = {
    "EUROSTAT": "Eurostat", "OECD_QNA": "OECD QNA", "IMF_QNEA": "IMF QNEA",
    "BIS_WSTC": "BIS WS\\_TC", "ECB_QSA_PUB": "ECB QSA\\_PUB",
    "ECB_MIR": "ECB MIR", "ECB_BSI": "ECB BSI", "FRED_MIRROR": "FRED mirror",
    "EC_BCS": "EC Business/Consumer Survey", "YAHOO_FINANCE": "Yahoo Finance",
    "EUROSTAT_HICP": "Eurostat HICP", "EUROSTAT_ULC": "Eurostat ULC",
    "GPR": "GPR Index", "": "\\emph{unresolved}",
}

appendix_b_rows = []
n_resolved = 0
for label in label_order:
    group = label_to_group[label]
    row = aut_rows.get(label, {})
    provider = row.get("provider", "") or ""
    key = row.get("key", "") or ""
    comment = row.get("comment", "") or ""
    if provider:
        n_resolved += 1
    provider_disp = provider_display.get(provider, provider)
    key_disp = code_break(tex_escape(key))
    label_disp = code_break(tex_escape(label))
    comment_disp = tex_escape(comment)
    appendix_b_rows.append(
        f"{tex_escape(group)} & \\texttt{{{label_disp}}} & {provider_disp} & \\texttt{{{key_disp}}} & {comment_disp} \\\\"
    )

appendix_b_body = "\n".join(appendix_b_rows)
n_concepts = len(label_order)

# ---- 3b. Table 1 (main body): the 38-concept taxonomy by FRED-QD group,
#      cross-referenced against both FRED-QD (US) and EA-MD-QD (EA) ----
table1_rows = []
for label in label_order:
    group = label_to_group[label]
    mnemonic = next((c[2] for c in concept_group_map if c[0] == label), None)
    mnemonic_disp = f"\\texttt{{{tex_escape(mnemonic)}}}" if mnemonic else "\\emph{none}"
    label_disp = code_break(tex_escape(label))
    ea_entry = ea_md_qd_quarterly_map.get(label)
    if ea_entry is None:
        ea_disp = "\\emph{none}"
    else:
        ea_id, caveat = ea_entry
        marker = {"unit": "$^{*}$", "at_gap": "$^{\\dagger}$"}.get(caveat, "")
        ea_disp = f"\\texttt{{{code_break(tex_escape(ea_id))}}}{marker}"
    table1_rows.append(f"{tex_escape(group)} & \\texttt{{{label_disp}}} & {mnemonic_disp} & {ea_disp} \\\\")
table1_body = "\n".join(table1_rows)

# ---- 4. Assemble the full working-paper-style document ----
doc = r"""\documentclass[11pt]{article}

\usepackage[margin=1in]{geometry}
\usepackage{longtable}
\usepackage{booktabs}
\usepackage{array}
\usepackage{amsmath}
\usepackage{amssymb}
\usepackage{pdflscape}
\usepackage{hyperref}
\usepackage{natbib}
\usepackage{orcidlink}

\newcolumntype{L}[1]{>{\raggedright\arraybackslash}p{#1}}

\title{AUSTRIA-QD: A Quarterly Database for Macroeconomic Research in Austria}
\author{Franz X.\ Mohr \orcidlink{0009-0003-8890-7781}}
\date{\today}

\begin{document}

\maketitle

\begin{abstract}
\noindent This report's contribution is a \emph{methodology}, not a
dataset: a documented, live-verified, and fully reproducible procedure for
building a FRED-QD-style \citep{mccracken2020fred} quarterly macroeconomic
panel for a single country from public international statistical APIs, and
its reference implementation for Austria. Larger academic releases already
cover Austria as part of a multi-country panel -- notably EA-MD-QD
\citep{barigozzi2024eamdqd}, with 1,136 series for the euro area and its
ten largest members -- so this report does not compete on coverage.
Instead it demonstrates, and documents in enough detail to be repeated for
any other country, a construction discipline that a periodically-released
static file cannot easily expose: every source (Eurostat, the OECD, the
IMF, the ECB, the BIS, and, for two country-specific overrides, the
European Commission's Business and Consumer Survey and Yahoo Finance) is
confirmed against its live API -- structure query, then a real data pull
returning current, plausible values -- rather than assumed correct from
documentation, with the exact identifier and any conceptual caveat
recorded in a public, machine-readable registry rather than left implicit
in code or spreadsheet formulas. One concrete payoff of this discipline:
merging rather than strictly falling back between sources for the anchor
national-accounts concepts recovers 35 years of Austrian history that a
naive Eurostat-then-OECD fallback would silently forfeit, extending
coverage to 1960-Q1 -- four decades earlier than EA-MD-QD's stated
January~2000 start. A second payoff came from a country-agnostic
plausibility-check layer added specifically so a researcher extending
this project to a new country has some automated verification beyond
eyeballing a spreadsheet: on its first live run, it caught a
previously-unknown $\sim$4x level discontinuity that very merge had
introduced (OECD's contribution was on an annualized-rate scale,
Eurostat's was not), invisible to growth-rate correlation checks alone
-- fixed the same day it was found. The reference implementation itself
covers 38 concepts, identical in column structure for every country the
underlying open-source tool has been run for, and the report catalogs,
series by series, which of FRED-QD's remaining 207 concepts have a
plausible but as yet unverified Austrian counterpart, which are directly
computable from concepts already implemented, and which have no
cross-country equivalent at all -- itself a template for scoping the same
exercise elsewhere.
\end{abstract}

\noindent\textbf{JEL Classification:} C82, C33, E01

\noindent\textbf{Keywords:} quarterly database, Austria, FRED-QD, macroeconomic data, open data, reproducibility

\section{Introduction}

\citet{mccracken2020fred} introduced FRED-QD as the quarterly companion to
FRED-MD \citep{mccracken2016fred}, itself designed to emulate the
macroeconomic panel used by \citet{stockwatson2012disentangling}. Their
stated goal was narrow but consequential: relieve researchers working with
macroeconomic ``big data'' methods of the burden of assembling, revising,
and documenting a large panel themselves, by providing one standardized,
continuously updated, publicly available file. FRED-QD has since become a
standard input to factor models, large Bayesian VARs, and a range of other
data-rich empirical methods -- and has itself inspired country- and
region-specific analogs, most notably a Canadian version
\citep{fortingagnon2018fred} and, for the euro area,
\citet{barigozzi2024eamdqd}'s EA-MD-QD, which provides 1,136 monthly and
quarterly series for the euro area as a whole and its ten largest member
states, Austria included, drawn from Eurostat, the ECB, the OECD, and FRED.

FRED-QD is, however, a U.S. database. Its 245 series are drawn from FRED,
which in turn mirrors U.S. statistical agencies (the Bureau of Economic
Analysis, the Bureau of Labor Statistics, the Census Bureau, the Federal
Reserve). A researcher wanting the same kind of standardized, quarterly,
factor-model-ready panel for a single country other than the United
States has, since \citeyear{barigozzi2024eamdqd}, had EA-MD-QD to draw an
Austrian sub-panel from -- but only as a byproduct of a euro-area-wide
construction, at a scale (1,136 series, distributed as spreadsheets plus
MATLAB code) oriented toward cross-country panel analysis rather than a
single country's own use.

This report's contribution is accordingly framed as a \emph{methodology}
rather than a competing dataset: a construction and verification procedure
that, applied to Austria as a reference case, produces a panel
parameterized by country rather than hard-coded (the underlying tool
already has built-in country-code support for 38 OECD member states), and
that trades EA-MD-QD's scale for two properties a country-first, code-based
construction makes easier to guarantee. First, every series' exact source
and any conceptual caveat is recorded in a public, machine-readable
registry rather than left to spreadsheet documentation
(Section~\ref{sec:registry}). Second, the fetch pipeline itself is open and
re-runnable rather than a periodically-refreshed static release, so a
researcher can audit, correct, or extend any single series' provenance
directly, and repeat the same procedure for a country neither FRED-QD nor
EA-MD-QD covers. Rather than replicate FRED-QD's exact 245 series -- most
of which, as documented in Section~\ref{sec:coverage}, have no
cross-country equivalent at all -- it reproduces FRED-QD's \emph{design}:
one representative concept per group, sourced from the most authoritative
and freshest agency available, with every source verified against its live
API rather than assumed correct from documentation alone.

The remainder of this report is organized as follows. Section~\ref{sec:construction}
describes how the panel is constructed: the concept taxonomy, the source
hierarchy and the country-specific overrides that take precedence over it,
the verification methodology, and the update cadence. Section~\ref{sec:registry}
describes the data-sources registry itself. Section~\ref{sec:coverage}
situates the 38 implemented concepts against FRED-QD's full 245-series
catalog. Section~\ref{sec:limitations} documents known data-quality issues
and gaps, following FRED-QD's own convention of disclosing rather than
papering over them. Section~\ref{sec:future} outlines concrete extensions.
Section~\ref{sec:conclusion} concludes. Appendix~\ref{app:catalog} reproduces
the full FRED-QD variable catalog; Appendix~\ref{app:mapping} gives the
current Austria-specific source mapping.

\section{Data Construction}
\label{sec:construction}

\subsection{Concept taxonomy and canonical schema}

Every country the underlying tool (\texttt{scripts/build\_country\_panel.R})
is run for produces a panel with exactly the same 38 columns, in the same
order, regardless of which concepts actually resolved for that country: a
concept with no available source for a given country is still present as
an all-\texttt{NA} column rather than silently missing. This mirrors, in
spirit, FRED-QD's own commitment to a fixed, documented series list -- and
is a deliberate design choice separate from mirroring FRED-QD's specific
series: the point of routing every country through the same 25
FRED-QD-style concept labels is that switching the country argument should
be the \emph{only} thing that changes between two runs, so that downstream
code can load any country's file with identical column-handling logic.
Table~\ref{tab:groups} lists the 38 concepts, the FRED-QD group each
belongs to, and -- alongside the FRED-QD mnemonic each already
approximates for the United States -- the corresponding quarterly series
ID from EA-MD-QD \citep{barigozzi2026eamdqdpaper}, the large existing
euro-area dataset already discussed in Section~\ref{sec:future}, where
one exists. This puts the US reference, the EA reference and this
project's own Austrian construction of the same concept side by side in
one place; Appendix~\ref{app:mapping} gives the exact Austrian source and
any conceptual caveat.

\begin{longtable}{L{4cm} L{4cm} L{2.8cm} L{2.5cm}}
\toprule
\textbf{FRED-QD Group} & \textbf{Concept} & \textbf{FRED-QD ID (US)} & \textbf{EA-MD-QD ID (EA)} \\
\midrule
\endhead
""" + table1_body + r"""
\bottomrule
\caption{The 38 implemented concepts, their FRED-QD group, and their US
(FRED-QD) and EA (EA-MD-QD, quarterly series only) cross-references.
Fourteen concepts have no direct FRED-QD mnemonic: five standard
cross-country indicators FRED-QD has no equivalent for at all (employment
rate, credit to the private non-financial sector, household credit-to-GDP,
corporate credit-to-GDP, the FX rate to USD), two HICP sub-categories with
no standalone FRED-QD counterpart (food, energy), and seven survey- or
research-index-based concepts entirely outside FRED-QD's scope (economic
sentiment, industrial/services/retail/construction confidence, employment
expectations, geopolitical risk) -- see Section~\ref{sec:overrides} for
the seven's sourcing. Twelve concepts have an EA-MD-QD quarterly
cross-reference: seven are exact matches (same concept, same construction);
four (marked $^{*}$) are the closest EA-MD-QD counterpart to a BIS-sourced
\%-of-GDP ratio this project publishes, but are themselves raw
ECB/Eurostat Quarterly Sector Accounts currency LEVELS, not ratios --
related, not identical; one (marked $^{\dagger}$, household disposable
income) is a series EA-MD-QD itself confirms has no observations for
Austria, independently corroborating the same gap Section~\ref{sec:limitations}
already documents. The remaining 26 concepts have no quarterly EA-MD-QD
counterpart: most of EA-MD-QD's own series for these concepts exist only
at monthly frequency (all its Interest Rates, Financial Markets,
Industrial Production and Turnover, Confidence Indicators, and Prices
series other than the GDP deflator), and a few concepts -- geopolitical
risk chief among them -- fall outside EA-MD-QD's scope entirely.}
\label{tab:groups}
\end{longtable}

\subsection{Source hierarchy and country-specific overrides}
\label{sec:overrides}

For the seven ``anchor'' national-accounts concepts (real GDP, household
consumption, government consumption, gross fixed capital formation,
exports, imports, and household disposable income), the tool queries both
Eurostat's Quarterly National Accounts (\texttt{namq\_10\_gdp}) for EU
member states and the OECD's Quarterly National Accounts
(\texttt{DF\_QNA}), and merges the two rather than treating either as a
pure fallback for the other: Eurostat's value is kept at every period it
covers, and OECD's value fills in any period Eurostat does not, with the
IMF's National Economic Accounts (\texttt{QNEA}) as a final fallback for
whatever neither source has at all. Eurostat is preferred where both
cover the same period not merely because it is the more ``local'' source,
but because in at least one case it is conceptually closer to FRED-QD's
own definition: Eurostat's household-consumption transaction
(\texttt{P31\_S14}) covers households only, while the equivalent OECD
sector (\texttt{S1M}) also includes non-profit institutions serving
households, making it broader than FRED-QD's household-only personal
consumption expenditure. Merging rather than strictly falling back
matters because the two sources' histories differ substantially:
Eurostat's own Austrian series start at 1995-Q1 for every anchor concept
(confirmed live -- querying as far back as 1970-Q1 returns nothing
earlier), while OECD QNA's Austrian real GDP series was confirmed live to
extend to 1960-Q1. Treating OECD as a fallback used only when Eurostat
returns nothing at all would have left 35 years of available history
unused for every concept Eurostat covers even partially; the merge
recovers it, extending this project's default starting point from
1995-Q1 to 1960-Q1 -- four decades earlier than EA-MD-QD's stated
January~2000 starting vintage \citep{barigozzi2024eamdqd}.

Merging two sources is not simply coalescing them, however: a plain
period-by-period coalesce (\texttt{merge\_prefer()} in the code) silently
assumes both sources report the SAME quantity on the SAME scale wherever
one takes over from the other, an assumption this project's own
plausibility checks (Section~\ref{sec:plausibility}) found to be false
here. OECD's QNA table (\texttt{T0102}, used for every anchor concept)
only offers \texttt{TRANSFORMATION=\allowbreak{}"LA"} (``Annual
levels'', i.e. the quarterly series expressed at an annualized rate) --
confirmed live by querying \texttt{TRANSFORMATION=\allowbreak{}"N"}
(``Non transformed data'') and receiving a clean \texttt{NoRecordsFound}
for both a 1990s and a 2020s period, not a guess -- while Eurostat
reports true, non-annualized quarterly levels. Coalescing the two as-is
therefore introduced a $\sim$75\% level discontinuity at the exact
quarter each anchor concept's source switches from OECD to Eurostat
(1994-Q4 to 1995-Q1 for Austria), across all six concepts alike. The fix,
\texttt{splice\_prefer()}, rescales OECD's contribution by the ratio of
the two sources' values at their one genuine overlap point (OECD is
queried for the full requested range regardless of where Eurostat takes
over, so this overlap already exists in the fetched data) before
coalescing -- preserving OECD's own internally-consistent quarter-to-
quarter dynamics for the period Eurostat does not cover, while correcting
its absolute level to match Eurostat's. Section~\ref{sec:plausibility}
describes how this was found.

For credit and balance-sheet concepts, the BIS's Credit to the
Non-Financial Sector dataflow (\texttt{WS\_TC}) is queried once per
borrower sector (private non-financial sector, households, non-financial
corporations, and general government) for \emph{all} countries at once --
a wildcarded \texttt{BORROWERS\_CTY} dimension was confirmed live to
return every country BIS covers in a single request -- and the result
cached locally so that building panels for multiple countries in one
session does not
re-download the same data. The general-government sector doubles as this
project's source for \texttt{government\_debt\_to\_gdp}: BIS's own
credit-statistics methodology treats ``credit to general government'' as
a close proxy for gross government debt, confirmed live for Austria,
Germany and the United States alike (75--111\% of GDP across the three
as of 2025-Q4) -- a genuinely cross-country source, unlike every other
override in this section, none of which extend outside the EU or euro
area. The ECB's Quarterly Sector Accounts supply
household net worth, but only as a euro-area \emph{aggregate}: the
dataflow was confirmed, by enumerating its actual published series keys
rather than assuming per-country availability, to have observations only
for the fixed-composition euro-area total, not for individual member
states. The ECB's MFI Interest Rate Statistics, by contrast, are genuinely
country-specific, and supply a mortgage rate (new-business loans to
households for house purchase) for any euro-area member. A second ECB
dataflow, MFI Balance Sheet Items (BSI), supplies the natural counterpart
to that rate: the outstanding stock of the same loan category
(\texttt{household\_mortgage\_loans}), confirmed current for both Austria
(EUR 133.0 billion) and Germany (EUR 1{,}658.4 billion) as of July 2026.
BSI and MIR are both ECB MFI statistics about the same underlying loans,
but use entirely different dimension structures and codes -- constructing
the BSI key by analogy with MIR's (a reasonable-looking guess) returned a
structurally valid zero-observation response even for the simplest
total-loans case; the working key was instead found by searching the ECB
Data Portal's own published series list for its human-readable title,
which exposes the exact SDMX key alongside it.

For the remaining concepts (industrial production, unemployment, house
prices, consumer prices, consumer sentiment, share prices, and several
others), the default source is FRED's own public mirror of OECD Main
Economic Indicators and BIS series -- reached via the same
\texttt{fredgraph.csv} export used throughout FRED-QD's own construction,
requiring no API key. Four deliberate exceptions take precedence over this
default. Two are staleness fixes, each because the FRED-mirrored OECD
series was confirmed live to have stopped updating (frozen since
2023--2024, depending on the series and country) while a fresher EU
primary source exists: for EU member states, consumer confidence is
sourced from the European Commission's own Business and Consumer Survey;
and, for the same EU member states, the consumer price index is sourced
from Eurostat's own Harmonised Index of Consumer Prices
(\texttt{prc\_hicp\_midx}), confirmed live to extend roughly two years
further (to 2025-Q4 for Austria) than the frozen FRED mirror (2023-Q4). A
third is a conceptual-fidelity fix rather than a staleness one: for EU
member states where Eurostat publishes an index-level series for it, unit
labor cost is sourced from Eurostat's labour productivity and
unit-labour-cost dataflow (\texttt{namq\_10\_lp\_ulc}, \texttt{NA\_ITEM=}
\texttt{NULC\_HW}), which is hours-based like FRED-QD's own \texttt{ULCNFB}
construction, unlike the FRED-mirrored OECD proxy's employment-based
percentage change -- confirmed available in this index-level form for
Austria but, on the identical live query, confirmed \emph{absent} for
Germany (only percentage-change variants are published there), which
keeps the FRED-mirror value. This is the one override in this project
that can genuinely fail for an EU member country, not only outside the
EU -- documented here rather than assumed to generalize from the Austrian
case it was verified against. The fourth exception is Austria-specific:
the share-price-index concept is sourced from the ATX (Austria's own
benchmark index) via Yahoo Finance, in place of a generic OECD ``all
shares'' proxy.

Beyond these four exceptions to an existing default, the Prices group
also gains four concepts with \emph{no} FRED-mirror default to override
at all: the HICP fetcher above generalizes to any COICOP category, so the
same verified dataflow and key structure also supply core inflation
(\texttt{TOT\_X\_NRG\_FOOD}, excluding energy and food -- the standard
ECB/Eurostat measure, and FRED-QD's closest analog to \texttt{CPILFESL}),
food (\texttt{CP01}), energy (\texttt{NRG}), and services
(\texttt{SERV}), all confirmed live for both Austria and Germany. These
are new \texttt{core\_cpi\_index}/\texttt{food\_price\_index}/
\texttt{energy\_price\_index}/\texttt{services\_price\_index} concepts,
EU-only by construction, since no international default exists for them
to fall back to outside the EU.

The same archive already fetched for consumer confidence carries six
further per-country columns this project did not previously use --
confirmed live by enumerating the cached workbook's own header row, not
assumed from the source's documentation. Two were prioritized for their
documented predictive value rather than mere availability: the Economic
Sentiment Indicator (\texttt{economic\_\allowbreak{}sentiment\_\allowbreak{}indicator}, column
suffix \texttt{ESI}) is DG ECFIN's own flagship composite -- a weighted
average of the industry, services, consumer, retail and construction
survey balances -- explicitly constructed and empirically validated to
track and lead euro-area GDP growth; the Industrial Confidence Indicator
(\texttt{industrial\_\allowbreak{}confidence}, \texttt{INDU}) is one of the archive's
oldest series (published since 1985) and a standard input to the OECD's
own Composite Leading Indicators for many countries. A third,
\texttt{employment\_\allowbreak{}expectations} (\texttt{EEI}), is DG ECFIN's own
purpose-built leading indicator for employment turning points,
introduced in 2013 specifically because the sectoral surveys'
employment sub-components lead employment growth. The remaining three --
services, retail and construction confidence (\texttt{SERV}/
\texttt{RETA}/\texttt{BUIL}) -- are the archive's other ESI
sub-components: standard EC-published sentiment measures without the
same individually-validated leading-indicator literature behind ESI,
INDU or EEI specifically, but a low-cost addition once the underlying
fetcher was already generalized to accept any of the seven column
suffixes.

Geopolitical uncertainty is sourced from the Geopolitical Risk (GPR)
index of \citet{caldara2022measuring}, the standard academic and policy
measure of adverse geopolitical events and their associated risks,
downloaded directly from the authors' own published monthly data file
rather than reimplemented. The source constructs country-specific
indices for 44 countries, confirmed by enumerating the file's own column
names rather than assumed from its documentation -- a check that also
surfaced a genuine trap: the file's ``GPRC\_AUS'' column is Australia,
not Austria, the same two-versus-three-letter country-code collision
this project's own country-code table exists to prevent for FRED's
mirror series. Austria is confirmed \emph{absent} from the 44
country-specific series; \texttt{geopolitical\_\allowbreak{}risk} falls back to the
source's global index for Austria and any other country without its own
column, rather than leaving the concept unresolved, since the index's
own validation literature documents international spillovers of
geopolitical risk shocks independent of a country's own media coverage
of them. Germany and the United States do have their own country-specific
series, confirmed live and current through July 2026.

\subsection{Verification methodology}

Every source used in this project was confirmed against its live API --
structure and codelist queries where relevant, then a real data pull
returning current, plausible values for at least two countries -- before
being wired into the panel-construction tool. This project's predecessor
script guessed several dataflow identifiers and dimension orderings that
later verification found to be wrong (documented in each module's header
comments, e.g.\ \texttt{R/oecd.R}, \texttt{R/bis.R}, \texttt{R/ecb.R}); the
verification pass this report describes was undertaken specifically to
replace those guesses with confirmed keys, correcting several outright
errors along the way. Series accepted as ``verified'' report a real
non-empty response with plausible values, not merely an HTTP~200 status,
since several sources return a syntactically valid but semantically empty
or stale response for an unsupported query -- for example, an unpublished
monthly archive redirecting to a generic landing page rather than
returning a 404.

\subsection{Update cadence}

Following FRED-QD's own practice of publishing a new vintage on the last
business day of each month, a scheduled job rebuilds the Austrian (and two
comparison, German and U.S.) panels on the first of each month and
archives a dated copy of both the data and its coverage report into
\texttt{output/vintages/}, so that a given month's release remains
reproducible even after later revisions are folded into the ``current''
file -- the same rationale FRED-QD gives for retaining its own historical
vintages.

\subsection{Transformation codes}

Where a concept corresponds to an actual FRED-QD series, this project
reuses that series' published transformation code (Appendix~\ref{app:catalog})
rather than re-deriving one, for the same reason FRED-QD itself reuses
\citet{stockwatson2012disentangling}'s original codes where available:
consistency with the literature that already uses these codes, rather than
introducing an independent judgment call about each series' order of
integration.

\subsection{Plausibility checks: verification without a ground truth}
\label{sec:plausibility}

Section~\ref{sec:overrides} above (\emph{Verification methodology}) describes
how every SOURCE was confirmed against its live API before being wired
into the tool. That check happens once, when a module is built. A
separate question is whether the OUTPUT a given run actually produces
still looks right -- and for the United States, \S~\ref{sec:coverage}'s
\texttt{--validate} flag answers exactly that, by correlating this
project's growth rates against the real published FRED-QD file. No such
file exists for any other country, including Austria itself; without a
second check, a researcher extending this project to a new country would
have no automated signal at all pointing at which of the panel's 38
columns might be wrong, only the option of reading every value by hand.

\texttt{R/plausibility\_checks.R} closes that gap with checks that need
no ground truth, only the panel itself and each concept's known
measurement type (percentage/ratio, survey balance or sentiment index,
quarterly growth rate, or level/index): a broad but real-world-informed
range for the first three types, and, for levels and indices, both
positivity and the absence of an implausible quarter-over-quarter jump
(a heuristic threshold, loose enough to tolerate genuine volatility --
confirmed live not to flag real crisis-era spikes in Austria's own
\texttt{geopolitical\_risk} series, which move far more than any
whole-economy aggregate around events like the Gulf War or Russia's 2022
invasion of Ukraine). These are deliberately loose bounds, not
authoritative thresholds: the goal is a prioritized list of which
concepts most reward a researcher's limited manual-verification time, not
a certificate of correctness. Results are written into
\texttt{<country>\_coverage.json} alongside the existing resolved/skipped
breakdown, and summarized on the console after every run.

This is not a hypothetical safeguard: on its first live run, it caught a
real, previously-unknown bug (the OECD/Eurostat level-splice issue
described in Section~\ref{sec:overrides}) that had been present, and
invisible to \texttt{--validate}, since the anchor-concept merge was
introduced. It also surfaced a second, deeper finding not yet acted on:
\texttt{cpi\_index}'s FRED-mirror default (used for non-EU countries) is
itself a percentage-change series, not the index level its own FRED-QD
mnemonic (\texttt{CPIAUCSL}) implies -- flagged as a concrete first task
for a researcher extending this project, in \texttt{CONTRIBUTING.md}.

\section{The Data-Sources Registry}
\label{sec:registry}

\texttt{docs/data\_sources.csv} is a long-format table -- one row per
(country, concept) pair -- with columns \texttt{country}, \texttt{variable},
\texttt{provider}, \texttt{key}, and \texttt{comment}. It is the single
documentation surface for ``what source backs this number, and how does it
conceptually differ from the US/FRED-QD definition,'' replacing what would
otherwise be prose comments scattered across each source-specific module.
The \texttt{USA} rows are the deliberate exception: they always hold the
actual FRED-QD mnemonic for each concept, since FRED-QD itself is the
ground truth every other country's row approximates, and are not
overwritten by a live run through the international sources for the United
States. Appendix~\ref{app:mapping} reproduces the current Austria rows.

\section{Coverage Relative to FRED-QD}
\label{sec:coverage}

Of FRED-QD's 245 series, 38 concepts are currently implemented for Austria
(24 correspond directly to a specific FRED-QD mnemonic; the remaining
fourteen have none, as Table~\ref{tab:groups}'s caption details -- five
standard cross-country indicators, two HICP sub-categories, and seven
survey- or research-index-based concepts sourced from the European
Commission's own survey archive and an external academic index,
respectively, discussed in Section~\ref{sec:overrides}). A companion
file, \texttt{docs/\allowbreak{}candidate\_\allowbreak{}indicators\_\allowbreak{}austria.csv}, goes
through every one of the remaining 207 FRED-QD series individually and
classifies each as a \textsc{candidate} (a proposed but unverified
Eurostat/ECB/OECD source, with a confidence rating), \textsc{derivable}
(computable from concepts already implemented, e.g.\ export and import
shares of GDP), or \textsc{no\_equivalent} (a genuinely U.S.-specific
construct, with the reason stated -- for example, the federal/state/local
government employment split has no counterpart in European labour-market
statistics). Unlike the registry described in Section~\ref{sec:registry},
that file is an explicitly unverified research proposal, intended as a
prioritized starting point for future verification passes rather than a
claim that any given source is confirmed to work.

\section{Known Limitations}
\label{sec:limitations}

Following FRED-QD's own convention of documenting data-quality issues
rather than silently working around them, several are noted here explicitly.
First, the OECD-mirrored consumer price index was found, on live
inspection, to have stopped updating at 2023-Q4 for Austria -- the same
underlying FRED-mirror family already fixed for consumer confidence via
the EC survey override. For EU member states this is now fixed the same
way, via an override to Eurostat's own HICP dataflow (see
Section~\ref{sec:overrides}), confirmed live to extend coverage to
2025-Q4; non-EU countries (including the United States) still receive the
stale FRED-mirror value, since no equivalent EU-style primary source
exists for them.
Second, OECD's own data API was found to rate-limit under the moderate
request volume of building three countries' panels back-to-back; the IMF
fallback absorbs this in practice; but it means a much larger cross-country
loop should expect to encounter it. Third, household net worth is
available only as a euro-area aggregate, not per country, a genuine data
availability limit rather than an implementation gap. Fourth, the unit
labor cost override is the one exception to the pattern that a source
either works for every country in its stated scope (EU, euro area) or
none: Eurostat's index-level series for it is confirmed present for
Austria but confirmed absent for Germany, an EU member, even though both
are otherwise EU-anchor-concept countries in this project -- future
countries added to this project should not assume EU membership alone
predicts whether this particular override will apply. Fifth, several
concepts are structurally unavailable outside the euro area or the EU
respectively, so a non-EU country's panel will show these as \texttt{NA}
by construction, not by omission: mortgage rate and household mortgage
loans (euro area), and the four HICP sub-categories plus six of the seven
EC Business and Consumer Survey concepts (all but consumer confidence,
which alone has a FRED-mirror fallback that also works outside the EU)
for the EU. Combined with the pre-existing genuine data gaps this section
already documents -- retail sales volume specifically for the US, the
euro-area-only household-net-worth aggregate, and the FX-rate concept
that is not meaningful for the US itself -- this means sixteen of the
panel's 38 concepts are necessarily \texttt{NA} for the United States,
not a coverage failure of this project's own sources. The one exception
to this section's pattern of EU/euro-area-only overrides is geopolitical
risk, which -- unlike every other addition here -- resolves for every
country regardless of EU membership (Section~\ref{sec:overrides}).
Sixth, the anchor-concept merge itself had a genuine level-scale bug --
found and fixed the same day by the plausibility checks introduced in
this pass (Section~\ref{sec:plausibility}); see Section~\ref{sec:overrides}
for the full account. It is recorded here, not just where it was fixed,
because FRED-QD's own convention this section follows is to document
data-quality issues rather than let a fix quietly erase the fact that a
real error existed in a previously-distributed vintage of this dataset.
Seventh, and NOT yet fixed: \texttt{cpi\_index}'s FRED-mirror default for
non-EU countries was found, by the same plausibility checks, to be a
percentage-change series rather than the index level its own FRED-QD
mnemonic implies (Section~\ref{sec:plausibility}) -- flagged as a
concrete first task in \texttt{CONTRIBUTING.md} rather than guessed at
under this report's own writing deadline.
Finally, quarterly household disposable income was not found for
Austria, Germany, or the United States themselves through either OECD or
Eurostat, consistent with McCracken and Ng's own observation that FRED-QD's
income-side detail is harder to source than its expenditure side.

\section{Future Work}
\label{sec:future}

The candidate list in Section~\ref{sec:coverage} identifies several
concrete, high-confidence extensions: Eurostat's Harmonised Index of
Consumer Prices, already implemented for the overall \texttt{cpi\_index}
concept plus core, food, energy and services (Section~\ref{sec:overrides}),
could, via its finer COICOP breakdown, also supply Austrian counterparts
to most of FRED-QD's remaining PCE/CPI sub-category price indices (apparel,
transport, health, and the various all-items-less-X variants); Eurostat's
labour productivity and unit-labour-cost dataflow
(\texttt{namq\_10\_lp\_ulc}), already used for the whole-economy
\texttt{unit\_labor\_cost} override (Section~\ref{sec:overrides}), also
carries sector-specific output-per-hour and unit-labor-cost series that
would be a direct source for FRED-QD's \texttt{OPHMFG}/\texttt{OPHNFB}/
\texttt{OPHPBS}/\texttt{ULCBS}/\texttt{ULCMFG} candidates, none of which
this project currently tracks; the ECB's MFI Balance Sheet Items, already
used for \texttt{household\_mortgage\_loans} (Section~\ref{sec:overrides}),
carries the same loan-by-purpose breakdown for other counterpart sectors
and purposes -- \texttt{BS\_ITEM=A21T} (``Credit for consumption''), by
direct analogy with the \texttt{A22T} (``Lending for house purchase'')
code already confirmed working, is the natural next candidate for
\texttt{CONSUMERx}; and Eurostat's quarterly government debt (Maastricht
debt) series remains a candidate for \texttt{GFDEBTNx}, the
real-dollar-level federal-debt concept BIS does not publish (its
\%-of-GDP counterpart, \texttt{GFDEGDQ188S}, is already implemented via
BIS -- Section~\ref{sec:overrides}). The European Commission's AMECO
database was
evaluated and deliberately not integrated into the quarterly panel, since
it is annual only; it remains a candidate for a separate annual companion
file covering fiscal concepts absent from both FRED-QD and this project's
current scope.

A further extension comes from cross-checking the candidate list against
EA-MD-QD's own published data description
\citep{barigozzi2026eamdqdpaper}, which -- being already live, verified,
and Austria-specific for every series it carries -- serves as independent
corroboration wherever its coverage overlaps this project's candidates.
Two of this report's lowest-confidence candidates turn out to be directly
confirmed: EA-MD-QD's Table~1 lists Austria-specific quarterly household
total financial assets and liabilities (\texttt{HHASS}, \texttt{HHLB},
sourced from the same Eurostat/ECB Quarterly Sector Accounts family as
this project's euro-area-only household net worth series) and the
analogous non-financial-corporation aggregates (\texttt{NFCASS},
\texttt{NFCLB}) as genuinely available per country, not merely
euro-area-wide -- upgrading four Household and Non-Household
Balance Sheet candidates from an unconfirmed \textsc{low} to a
verified-elsewhere \textsc{high} in the updated
\texttt{docs/\allowbreak{}candidate\_\allowbreak{}indicators\_\allowbreak{}austria.csv}. EA-MD-QD's variable
list also covers several concepts with no FRED-QD counterpart at all --
a household gross saving rate, household and corporate investment and
profit shares, a semi-durable-goods consumption category sitting between
FRED-QD's durable and non-durable splits, a real effective exchange
rate, and per-worker (rather than per-hour) labour productivity. A
seventh, sector-specific confidence balances (construction, retail,
services) obtainable from the same European Commission survey archive
this project already fetches for consumer confidence, has since been
implemented (Section~\ref{sec:overrides}), alongside two further survey
concepts (economic sentiment, employment expectations) EA-MD-QD's own
list does not carry. The remaining six
concepts are catalogued separately in
\texttt{docs/\allowbreak{}candidate\_\allowbreak{}indicators\_\allowbreak{}ea\_md\_qd.csv}, alongside FRED-QD's
own list, rather than folded into Appendix~B's mnemonic-keyed table, since
they fall outside FRED-QD's 245-series scope by construction. Finally, in
the spirit of \citet{mccracken2020fred}'s own
empirical validation of FRED-QD via factor estimation and forecasting
exercises, a natural extension once coverage and country count grow
further is to assess whether factors extracted from this panel behave
comparably to those extracted from FRED-QD itself over the sample period
they overlap.

\section{Conclusion}
\label{sec:conclusion}

This report's contribution is the construction and verification
methodology it describes, not the size of the panel it happens to produce:
a fixed concept taxonomy, a source hierarchy with explicit
country-specific overrides, every source confirmed against its live API
rather than assumed correct, a public registry of exactly what was used
and why, and an explicit accounting of what remains uncovered and why.
Austria serves here as the reference case precisely because a
larger-scale alternative already exists for it (EA-MD-QD,
\citealp{barigozzi2024eamdqd}) -- so the value on offer is not a bigger
panel, but a smaller, fully transparent, and openly re-runnable one that
the same procedure can reproduce for any other country, together with a
concrete, prioritized, and honestly-labeled path to extending its
coverage further.

\bibliographystyle{apalike}
\begin{thebibliography}{9}

\bibitem[Barigozzi and Lissona, 2024]{barigozzi2024eamdqd}
Barigozzi, M. and Lissona, C. (2024).
EA-MD-QD: Large Euro Area and Euro Member Countries Datasets for Macroeconomic Research.
\textit{Zenodo dataset}, \url{https://doi.org/10.5281/zenodo.10514667}.

\bibitem[Barigozzi et al., 2026]{barigozzi2026eamdqdpaper}
Barigozzi, M., Lissona, C., and Tonni, L. (2026).
Large datasets for the euro area and its member countries and the dynamic effects of the common monetary policy.
\textit{arXiv preprint}, arXiv:2410.05082.

\bibitem[Caldara and Iacoviello, 2022]{caldara2022measuring}
Caldara, D. and Iacoviello, M. (2022).
Measuring Geopolitical Risk.
\textit{American Economic Review}, 112(4):1194--1225.

\bibitem[Fortin-Gagnon et al., 2018]{fortingagnon2018fred}
Fortin-Gagnon, O., Leroux, M., Stevanovic, D., and Surprenant, S. (2018).
A Large Canadian Database for Macroeconomic Analysis.
\textit{CIRANO Working Papers}, 2018s-25.

\bibitem[McCracken and Ng, 2016]{mccracken2016fred}
McCracken, M.~W. and Ng, S. (2016).
FRED-MD: A Monthly Database for Macroeconomic Research.
\textit{Journal of Business \& Economic Statistics}, 34(4):574--589.

\bibitem[McCracken and Ng, 2020]{mccracken2020fred}
McCracken, M.~W. and Ng, S. (2020).
FRED-QD: A Quarterly Database for Macroeconomic Research.
\textit{Federal Reserve Bank of St.\ Louis Working Paper}, 2020-005.
\url{https://doi.org/10.20955/wp.2020.005}.

\bibitem[Stock and Watson, 2012]{stockwatson2012disentangling}
Stock, J.~H. and Watson, M.~W. (2012).
Disentangling the Channels of the 2007--2009 Recession.
\textit{NBER Working Paper}, 18094.

\end{thebibliography}

\appendix

\begin{landscape}
\section{FRED-QD Variable Catalog}
\label{app:catalog}

For reference, Table~\ref{tab:groups} lists this project's 38 implemented
concepts and their FRED-QD group; the tables that follow reproduce
FRED-QD's complete 245-series catalog (McCracken and Ng, 2020), grouped
into the original fourteen categories, with each series' recommended
transformation code and whether Stock and Watson (2012) used it when
estimating factors (\checkmark~= yes). If the FRED mnemonic does not end
in ``x'' the series comes directly from the FRED database; otherwise it is
a modified variant, most commonly a nominal series manually deflated by
the PCE or core-PCE price index. Monthly-frequency source series are
aggregated to quarterly frequency by averaging over the three months of
the quarter.

""" + appendix_a_tables + r"""

\section{Austrian Data-Source Mapping}
\label{app:mapping}

Table~\ref{tab:austria} reproduces the current Austria rows of
\texttt{docs/data\_sources.csv} (Section~\ref{sec:registry}) -- regenerated
directly from that file every time this report is rebuilt, so it cannot
drift out of sync with what \texttt{scripts/build\_country\_panel.R}
actually resolved. """ + f"{n_resolved} of {n_concepts}" + r""" concepts were
resolved as of the most recent run; an empty Provider/Key cell means the
concept was attempted but no source returned data for Austria, with the
reason given in the Comment column.

\begin{longtable}{L{3cm} L{4cm} L{2.6cm} L{3.2cm} L{7.5cm}}
\caption{Austria source mapping, regenerated from \texttt{docs/data\_sources.csv}.}
\label{tab:austria} \\
\toprule
\textbf{FRED-QD Group} & \textbf{Concept} & \textbf{Provider} & \textbf{Key} & \textbf{Comment} \\
\midrule
\endfirsthead
\multicolumn{5}{l}{\textit{Table \ref{tab:austria} continued}} \\
\toprule
\textbf{FRED-QD Group} & \textbf{Concept} & \textbf{Provider} & \textbf{Key} & \textbf{Comment} \\
\midrule
\endhead
""" + appendix_b_body + r"""
\bottomrule
\end{longtable}

\end{landscape}

\end{document}
"""

with open(out_path, "w", encoding="utf-8") as f:
    f.write(doc)

print("Resolved for AUT:", n_resolved, "/", n_concepts)
print("Wrote", out_path, "(", len(doc), "chars )")
