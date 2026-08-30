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
# Mirrors scripts/build_country_panel.R's concept_group_map exactly.
concept_group_map = [
    ("real_gdp", "Output and Income", "GDPC1", None),
    ("real_household_consumption", "Output and Income", "PCECC96", None),
    ("real_govt_consumption", "Output and Income", "GCEC1", None),
    ("real_gfcf_total", "Output and Income", "FPIx", None),
    ("real_exports", "Output and Income", "EXPGSC1", None),
    ("real_imports", "Output and Income", "IMPGSC1", None),
    ("real_household_disposable_income", "Output and Income", "DPIC96", None),
    ("industrial_production", "Industrial Production", "INDPRO", None),
    ("unemployment_rate", "Employment and Unemployment", "UNRATE", None),
    ("employment_rate", "Employment and Unemployment", None, "no FRED-QD equivalent"),
    ("house_price_real", "Housing", "USSTHPI", None),
    ("retail_sales_volume", "Inventories, Orders, and Sales", "RSAFSx", None),
    ("cpi_index", "Prices", "CPIAUCSL", None),
    ("unit_labor_cost", "Earnings and Productivity", "ULCNFB", None),
    ("long_term_rate", "Interest Rates", "GS10", None),
    ("short_term_rate", "Interest Rates", "TB3MS", None),
    ("mortgage_rate", "Interest Rates", "MORTGAGE30US", None),
    ("credit_to_private_nonfin_sector", "Money and Credit", None, "no FRED-QD equivalent"),
    ("euro_area_household_net_worth_growth", "Household Balance Sheets", "TNWBSHNOx", None),
    ("household_credit_to_gdp", "Household Balance Sheets", None, "no FRED-QD equivalent"),
    ("corporate_credit_to_gdp", "Non-Household Balance Sheets", None, "no FRED-QD equivalent"),
    ("fx_rate_to_usd", "Exchange Rates", None, "not meaningful for the US itself"),
    ("real_effective_exchange_rate", "Exchange Rates", "TWEXAFEGSMTHx", None),
    ("consumer_confidence", "Other", "UMCSENTx", None),
    ("share_price_index", "Stock Markets", "S&P 500", None),
]
label_order = [c[0] for c in concept_group_map]
label_to_group = {c[0]: c[1] for c in concept_group_map}

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
    "ECB_MIR": "ECB MIR", "FRED_MIRROR": "FRED mirror",
    "EC_BCS": "EC Business/Consumer Survey", "YAHOO_FINANCE": "Yahoo Finance",
    "": "\\emph{unresolved}",
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

# ---- 3b. Table 1 (main body): the 25-concept taxonomy by FRED-QD group ----
table1_rows = []
for label in label_order:
    group = label_to_group[label]
    mnemonic = next((c[2] for c in concept_group_map if c[0] == label), None)
    mnemonic_disp = f"\\texttt{{{tex_escape(mnemonic)}}}" if mnemonic else "\\emph{none}"
    label_disp = code_break(tex_escape(label))
    table1_rows.append(f"{tex_escape(group)} & \\texttt{{{label_disp}}} & {mnemonic_disp} \\\\")
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
in code or spreadsheet formulas. The reference implementation itself
covers 25 concepts, identical in column structure for every country the
underlying open-source tool has been run for, and the report catalogs,
series by series, which of FRED-QD's remaining 220 concepts have a
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
situates the 25 implemented concepts against FRED-QD's full 245-series
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
is run for produces a panel with exactly the same 25 columns, in the same
order, regardless of which concepts actually resolved for that country: a
concept with no available source for a given country is still present as
an all-\texttt{NA} column rather than silently missing. This mirrors, in
spirit, FRED-QD's own commitment to a fixed, documented series list -- and
is a deliberate design choice separate from mirroring FRED-QD's specific
series: the point of routing every country through the same 25
FRED-QD-style concept labels is that switching the country argument should
be the \emph{only} thing that changes between two runs, so that downstream
code can load any country's file with identical column-handling logic.
Table~\ref{tab:groups} lists the 25 concepts and the FRED-QD group each
belongs to; Appendix~\ref{app:mapping} gives the exact source and any
conceptual caveat for Austria specifically.

\begin{longtable}{L{4.5cm} L{5cm} L{3cm}}
\toprule
\textbf{FRED-QD Group} & \textbf{Concept} & \textbf{FRED-QD mnemonic} \\
\midrule
\endhead
""" + table1_body + r"""
\bottomrule
\caption{The 25 implemented concepts and their FRED-QD group. Four concepts
(employment rate, mortgage rate, and two credit-to-GDP ratios) have no
direct FRED-QD mnemonic; they are standard cross-country indicators
included because they are well-supported by the sources in this project.}
\label{tab:groups}
\end{longtable}

\subsection{Source hierarchy and country-specific overrides}

For the seven ``anchor'' national-accounts concepts (real GDP, household
consumption, government consumption, gross fixed capital formation,
exports, imports, and household disposable income), the tool tries
Eurostat's Quarterly National Accounts (\texttt{namq\_10\_gdp}) first for
EU member states, then the OECD's Quarterly National Accounts
(\texttt{DF\_QNA}) for whatever Eurostat did not resolve, then the IMF's
National Economic Accounts (\texttt{QNEA}) for whatever is still missing.
Eurostat is preferred for EU members not merely because it is the more
``local'' source, but because in at least one case it is conceptually
closer to FRED-QD's own definition: Eurostat's household-consumption
transaction (\texttt{P31\_S14}) covers households only, while the
equivalent OECD sector (\texttt{S1M}) also includes non-profit institutions
serving households, making it broader than FRED-QD's household-only
personal consumption expenditure.

For credit and balance-sheet concepts, the BIS's Credit to the
Non-Financial Sector dataflow (\texttt{WS\_TC}) is queried once per
borrower sector (private non-financial sector, households, non-financial
corporations) for \emph{all} countries at once -- a wildcarded
\texttt{BORROWERS\_CTY} dimension was confirmed live to return every
country BIS covers in a single request -- and the result cached locally so
that building panels for multiple countries in one session does not
re-download the same data. The ECB's Quarterly Sector Accounts supply
household net worth, but only as a euro-area \emph{aggregate}: the
dataflow was confirmed, by enumerating its actual published series keys
rather than assuming per-country availability, to have observations only
for the fixed-composition euro-area total, not for individual member
states. The ECB's MFI Interest Rate Statistics, by contrast, are genuinely
country-specific, and supply a mortgage rate (new-business loans to
households for house purchase) for any euro-area member.

For the remaining concepts (industrial production, unemployment, house
prices, consumer sentiment, share prices, and several others), the default
source is FRED's own public mirror of OECD Main Economic Indicators and
BIS series -- reached via the same \texttt{fredgraph.csv} export used
throughout FRED-QD's own construction, requiring no API key. Two
deliberate exceptions take precedence over this default: for EU member
states, consumer confidence is sourced from the European Commission's own
Business and Consumer Survey, which publishes current data, in place of
the FRED-mirrored OECD series, which was found to have been frozen since
2024; and for Austria specifically, the share-price-index concept is
sourced from the ATX (Austria's own benchmark index) via Yahoo Finance, in
place of a generic OECD ``all shares'' proxy.

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

Of FRED-QD's 245 series, 25 concepts are currently implemented for Austria
(21 correspond directly to a specific FRED-QD mnemonic; the remaining four
-- employment rate, mortgage rate, and two credit-to-GDP ratios -- are
standard cross-country indicators with no FRED-QD equivalent, included
because they are otherwise well-supported by the sources above). A
companion file, \texttt{docs/candidate\_indicators\_austria.csv}, goes
through every one of the remaining 220 FRED-QD series individually and
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
First, the OECD-mirrored consumer price index has no primary-source
override yet and was found, on live inspection, to have stopped updating
around 2024 -- the same underlying FRED-mirror family that was fixed for
consumer confidence via the EC survey override, but not yet for CPI.
Second, OECD's own data API was found to rate-limit under the moderate
request volume of building three countries' panels back-to-back; the IMF
fallback absorbs this in practice; but it means a much larger cross-country
loop should expect to encounter it. Third, household net worth is
available only as a euro-area aggregate, not per country, a genuine data
availability limit rather than an implementation gap. Fourth, several
concepts (mortgage rate, the EC survey override) are structurally
unavailable outside the euro area or the EU respectively, so a non-EU
country's panel will show these as \texttt{NA} by construction, not by
omission. Finally, quarterly household disposable income was not found for
Austria, Germany, or the United States themselves through either OECD or
Eurostat, consistent with McCracken and Ng's own observation that FRED-QD's
income-side detail is harder to source than its expenditure side.

\section{Future Work}
\label{sec:future}

The candidate list in Section~\ref{sec:coverage} identifies several
concrete, high-confidence extensions: Eurostat's Harmonised Index of
Consumer Prices, whose dataflow was confirmed to exist live, would both
fix the stale CPI series above and, via its COICOP breakdown, supply
Austrian counterparts to most of FRED-QD's twenty PCE/CPI sub-category
price indices; Eurostat's labour productivity and unit-labour-cost dataflow
(\texttt{namq\_10\_lp\_ulc}) is a direct quarterly source for a concept
currently approximated via an OECD-mirror proxy; the ECB's MFI Balance
Sheet Items appear to be the same country-specific statistical family as
the already-implemented mortgage rate, and may supply loans-by-purpose
series analogous to several Money and Credit concepts; and Eurostat's
quarterly government debt series is a well-established candidate for the
two federal-debt concepts. The European Commission's AMECO database was
evaluated and deliberately not integrated into the quarterly panel, since
it is annual only; it remains a candidate for a separate annual companion
file covering fiscal concepts absent from both FRED-QD and this project's
current scope. Finally, in the spirit of \citet{mccracken2020fred}'s own
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
\textit{arXiv preprint}, arXiv:2410.05082.

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

For reference, Table~\ref{tab:groups} lists this project's 25 implemented
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
