# -*- coding: utf-8 -*-
"""
generate_candidate_indicators.py -- run from the repository root:
    python docs/generate_candidate_indicators.py

Parses docs/Mohr_AUSTRIA-QD.tex (Appendix A) to get the authoritative 245-series
catalog (mnemonic, group, description), then joins it against a
hand-built annotation table proposing an Austrian-equivalent candidate
source for each series. Output: docs/candidate_indicators_austria.csv

This is a RESEARCH PROPOSAL, not a verified registry (unlike
docs/data_sources.csv, which is only ever populated by scripts/
build_country_panel.R from a real, live-tested fetch). Every CANDIDATE
row here is UNVERIFIED unless its note says otherwise ("dataflow
existence confirmed" means only that -- the dataset exists, not that the
exact key/dimension values proposed are correct). `confidence` reflects
how sure this pass is that the named dataset/series exists in roughly
that form, based on domain knowledge of Eurostat/ECB/OECD data products,
not on a live test. Before implementing any CANDIDATE row the same way
R/eurostat.R, R/ecb.R etc. were built, verify it live first -- see those
files' header comments for the pattern (structure query, then a real
data pull, then update this row's status to IMPLEMENTED and move it into
docs/data_sources.csv via a build_country_panel.R run).
"""
import re
import csv
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
tex_path = os.path.join(script_dir, "Mohr_AUSTRIA-QD.tex")
with open(tex_path, encoding="utf-8") as f:
    tex = f.read()

# ---- 1. Parse the 245-series catalog straight from the tex tables ----
group_blocks = re.findall(
    r"\\section\*\{Group: ([^}]+)\}\s*\\begin\{longtable\}.*?\\endhead\s*(.*?)\\bottomrule",
    tex, re.S
)

catalog = []  # list of (mnemonic, group, description)
for group, body in group_blocks:
    for line in body.strip().split("\\\\"):
        line = line.strip()
        if not line or "\\texttt" not in line:
            continue
        m = re.match(r"\\texttt\{([^}]+)\}\s*&\s*(.*?)\s*&\s*\d\s*&", line, re.S)
        if not m:
            continue
        mnemonic = m.group(1).replace("\\&", "&")
        desc = m.group(2)
        desc = desc.replace("\\&", "&").replace("\\%", "%").replace("--", "-")
        desc = re.sub(r"\\allowbreak\{?\}?", "", desc)
        desc = re.sub(r"\s+", " ", desc).strip()
        catalog.append((mnemonic, group, desc))

print("Parsed", len(catalog), "series from", len(group_blocks), "groups")

# ---- 2. Already-implemented concepts (label -> mnemonic it approximates) ----
# From concept_group_map / us_note in scripts/build_country_panel.R.
implemented_mnemonics = {
    "GDPC1", "GPDIC1", "PCECC96", "GCEC1", "FPIx", "EXPGSC1", "IMPGSC1",
    "INDPRO", "UNRATE", "USSTHPI", "RSAFSx", "CPIAUCSL", "ULCNFB", "GS10",
    "TB3MS", "MORTGAGE30US", "TNWBSHNOx", "TWEXAFEGSMTHx", "EXUSEU", "UMCSENTx",
    "S&P 500",
}

# ---- 3. Candidate annotations, keyed by mnemonic ----
# (status, source, confidence, note)
# status: CANDIDATE | DERIVABLE | NO_EQUIVALENT
# confidence (for CANDIDATE only): HIGH | MEDIUM | LOW
A = {}

def add(mnemonics, status, source="", confidence="", note=""):
    for m in mnemonics.split(","):
        A[m.strip()] = (status, source, confidence, note)

# --- Output and Income ---
add("PCDGx,PCESVx,PCNDx", "CANDIDATE", "Eurostat nama_10_fcs / namq_10_fcs (household consumption by durability: DUR/SEMI/NDUR/SERV)", "MEDIUM", "Durability breakdown is standard annually; quarterly availability for AT not confirmed")
add("Y033RC1Q027SBEAx,PNFIx", "CANDIDATE", "Eurostat GFCF by asset type (AN.111/AN.1112, e.g. namq_10_anagg)", "MEDIUM", "Machinery/equipment vs. non-residential structures breakdown exists but exact quarterly table for AT unverified")
add("PRFIx", "CANDIDATE", "Eurostat GFCF, dwellings (AN.1111), namq_10_anagg or namq_10_gdp NA_ITEM=P51G + asset filter", "HIGH", "Residential investment is a routinely published EU quarterly series")
add("A014RE1Q156NBEA", "CANDIDATE", "Derived: Eurostat P52 (changes in inventories) / GDP, from namq_10_gdp", "MEDIUM", "P52 validity for this dataflow not yet confirmed (only B1GQ/P31_S14/P3_S13/P51G/P6/P7 confirmed so far)")
add("A823RL1Q225SBEA,FGRECPTx", "CANDIDATE", "Eurostat government finance stats by subsector (S1311 central government), gov_10q_ggnfa or similar", "LOW", "Austria's federal/Länder/Gemeinden split maps loosely onto S1311/S1312/S1313; quarterly subsector detail is thin")
add("SLCEx", "CANDIDATE", "Eurostat government consumption by subsector (S1312+S1313, Länder+Gemeinden)", "LOW", "Same subsector caveat as above")
add("OUTNFB,OUTBS", "NO_EQUIVALENT", note="\"Nonfarm/business sector output\" is a BLS/BEA productivity-accounts construct with no direct EU statistical analog; Eurostat GVA excl. agriculture is a distant proxy at best")
add("OUTMS", "CANDIDATE", "Eurostat/Statistik Austria manufacturing (NACE C) production index, sts_inpr_m", "MEDIUM", "Index concept, not GVA-based like FRED-QD's series")
add("B020RE1Q156NBEA,B021RE1Q156NBEA", "DERIVABLE", note="Simple ratio of already-implemented real_exports/real_imports to real_gdp; no new source needed")

# --- Industrial Production ---
add("IPFINAL", "CANDIDATE", "Eurostat sts_inpr_m, Main Industrial Groupings (MIG) aggregate", "HIGH", "MIG breakdown is a standard Eurostat STS product, closely parallels FRED-QD's market groups")
add("IPCONGD", "CANDIDATE", "Eurostat sts_inpr_m, MIG=Consumer goods (MIG_CAG)", "HIGH")
add("IPMAT", "CANDIDATE", "Eurostat sts_inpr_m, MIG=Intermediate goods (MIG_ING)", "HIGH")
add("IPDMAT,IPNMAT", "CANDIDATE", "Eurostat sts_inpr_m, NACE division detail within intermediate goods", "LOW", "MIG intermediate-goods category is not itself split by durability")
add("IPDCONGD", "CANDIDATE", "Eurostat sts_inpr_m, MIG=Durable consumer goods (MIG_CDG)", "HIGH")
add("IPB51110SQ", "CANDIDATE", "Eurostat/Statistik Austria IP by NACE division 29 (motor vehicles)", "HIGH")
add("IPNCONGD", "CANDIDATE", "Eurostat sts_inpr_m, MIG=Non-durable consumer goods (MIG_CNG)", "HIGH")
add("IPBUSEQ", "CANDIDATE", "Eurostat sts_inpr_m, MIG=Capital goods (MIG_CAG)", "MEDIUM")
add("IPB51220SQ", "CANDIDATE", "Eurostat/Statistik Austria IP, NACE division D (energy)", "MEDIUM")
add("TCU,CUMFNS", "CANDIDATE", "European Commission Business and Consumer Survey, Capacity Utilisation in manufacturing (same archive already used for consumer confidence, R/ec_survey.R)", "HIGH", "The same monthly EC survey archive this project already fetches also carries a capacity-utilisation question; worth checking its exact column code")
add("IPMANSICS", "CANDIDATE", "Eurostat/Statistik Austria manufacturing (NACE C) production index", "HIGH")
add("IPB51222S", "NO_EQUIVALENT", note="US-specific utility/residential IP subcategory; no standard EU analog")
add("IPFUELS", "CANDIDATE", "Eurostat/Statistik Austria IP, NACE mining and energy production", "MEDIUM")

# --- Employment and Unemployment ---
add("PAYEMS", "CANDIDATE", "Eurostat national accounts employment (namq_10_pe, total domestic employment) or LFS employed persons (lfsq_egan)", "HIGH")
add("USPRIV", "CANDIDATE", "Derived: PAYEMS candidate minus LFS public-administration employment (NACE O)", "LOW", "EU stats don't cleanly separate \"private\" vs \"public\" sector employment the way US establishment survey does")
add("MANEMP", "CANDIDATE", "Eurostat LFS employment by NACE (lfsq_egan2), sector C", "HIGH")
add("SRVPRD", "CANDIDATE", "Eurostat LFS employment by NACE, services aggregate (G-U)", "HIGH")
add("USGOOD", "CANDIDATE", "Eurostat LFS employment by NACE, industry+construction (B-F)", "HIGH")
add("DMANEMP,NDMANEMP", "CANDIDATE", "Eurostat LFS employment by 2-digit NACE division within manufacturing", "LOW", "Durable/non-durable split isn't a standard NACE cut; would need a manual division-level rollup")
add("USCONS", "CANDIDATE", "Eurostat LFS employment by NACE, sector F", "HIGH")
add("USEHS", "CANDIDATE", "Eurostat LFS employment by NACE, sectors P+Q", "HIGH")
add("USFIRE", "CANDIDATE", "Eurostat LFS employment by NACE, sector K (+L)", "HIGH")
add("USINFO", "CANDIDATE", "Eurostat LFS employment by NACE, sector J", "HIGH")
add("USPBS", "CANDIDATE", "Eurostat LFS employment by NACE, sectors M+N", "HIGH")
add("USLAH", "CANDIDATE", "Eurostat LFS employment by NACE, sectors I+R", "HIGH")
add("USSERV", "CANDIDATE", "Eurostat LFS employment by NACE, sector S", "MEDIUM")
add("USMINE", "CANDIDATE", "Eurostat LFS employment by NACE, sector B", "MEDIUM", "\"Logging\" (part of A) not cleanly separable")
add("USTPU", "CANDIDATE", "Eurostat LFS employment by NACE, sectors G+H+D+E", "HIGH")
add("USGOVT", "CANDIDATE", "Eurostat LFS employment by NACE, sector O (public administration)", "MEDIUM", "Excludes public employees classified under P/Q (education/health), unlike the US series")
add("USTRADE", "CANDIDATE", "Eurostat LFS employment by NACE division 47 (retail)", "HIGH")
add("USWTRADE", "CANDIDATE", "Eurostat LFS employment by NACE division 46 (wholesale)", "HIGH")
add("CES9091000001,CES9092000001,CES9093000001", "NO_EQUIVALENT", note="Federal/state/local employment split has no EU statistical analog at this granularity; Austria's own government employment stats (Stellenplan) are not harmonized this way")
add("CE16OV", "CANDIDATE", "Eurostat LFS total employed persons (lfsq_egan)", "HIGH")
add("CIVPART", "CANDIDATE", "Eurostat LFS activity rate (lfsq_argan)", "HIGH", "Natural complement to the already-implemented employment_rate")
add("UNRATESTx,UNRATELTx", "CANDIDATE", "Eurostat LFS unemployment by duration (lfsq_upgal / une_ltu series)", "MEDIUM")
add("LNS14000012", "CANDIDATE", "Eurostat LFS unemployment rate by age (lfsq_urgan), youth 15-24 band", "MEDIUM", "EU's standard youth band (15-24) doesn't exactly match FRED-QD's 16-19")
add("LNS14000025,LNS14000026", "CANDIDATE", "Eurostat LFS unemployment rate by sex and age (lfsq_urgan)", "HIGH")
add("UEMPLT5,UEMP5TO14,UEMP15T26,UEMP27OV", "CANDIDATE", "Eurostat LFS unemployment by duration bands (lfsq_ugad)", "MEDIUM", "EU duration bands (<1mo, 1-2, 3-5, 6-11, 12+) don't align exactly with FRED-QD's week-based cutoffs")
add("LNS13023621,LNS13023557,LNS13023705,LNS13023569", "NO_EQUIVALENT", note="Unemployment-by-reason (job loser/leaver/reentrant/new entrant) is a CPS-specific classification; EU LFS does not publish a comparable quarterly breakdown for most countries")
add("LNS12032194", "CANDIDATE", "Eurostat LFS involuntary part-time employment (lfsq_epgai or similar)", "MEDIUM", "\"Involuntary part-time\" (EU concept) vs. \"part-time for economic reasons\" (US) are similar but not identically defined")
add("HOABS,HOAMS,HOANBS", "CANDIDATE", "Eurostat national accounts, total hours worked (namq_10_pe)", "MEDIUM")
add("AWHMAN,AWHNONAG,AWOTMAN", "CANDIDATE", "Eurostat LFS average usual weekly hours worked (lfsq_ewhun2)", "MEDIUM", "LFS doesn't separately break out overtime hours the way AWOTMAN does")
add("HWIx", "CANDIDATE", "Eurostat job vacancy rate (jvs_q_nace2)", "LOW", "A rate, not an index -- different construction from the Help-Wanted Index")
add("UEMPMEAN", "CANDIDATE", "Eurostat LFS mean/median unemployment duration", "MEDIUM")
add("CES0600000007", "CANDIDATE", "Eurostat LFS average hours worked by NACE, goods-producing sectors", "MEDIUM")
add("HWIURATIOx", "DERIVABLE", note="Ratio of the HWIx and UNRATE candidates above, once both exist")
add("CLAIMSx", "CANDIDATE", "AMS (Arbeitsmarktservice Österreich) new unemployment registrations -- a NATIONAL (not EU-harmonized) source", "MEDIUM", "Conceptually close to US initial claims; AMS publishes this but it is Austria-only, not a generalizable cross-country pattern like the rest of this project")

# --- Housing ---
add("HOUST,HOUST5F", "NO_EQUIVALENT", note="\"Housing starts\" has no standard EU equivalent; Statistik Austria publishes building COMPLETIONS (Fertigstellungen), a related but different concept, annually")
add("PERMIT", "CANDIDATE", "Eurostat quarterly building permits index (sts_cobp_q)", "HIGH", "Dataflow existence confirmed live 2026-08-30; exact dimension key not yet verified")
add("HOUSTMW,HOUSTNE,HOUSTS,HOUSTW,PERMITNE,PERMITMW,PERMITS,PERMITW", "NO_EQUIVALENT", note="US Census-region breakdown; no standard Austrian sub-national equivalent (could use Bundesland via Statistik Austria but not a standard cut)")
add("SPCS10RSA,SPCS20RSA", "NO_EQUIVALENT", note="US-city-specific house price indices; already covered at country level by the implemented house_price_real (BIS), no Austrian city-level series tracked")

# --- Inventories, Orders, and Sales ---
add("CMRMTSPLx", "CANDIDATE", "Eurostat turnover index, industry+trade (sts_trtu_m)", "MEDIUM")
add("AMDMNOx,ACOGNOx,AMDMUOx,ANDENOx", "CANDIDATE", "Eurostat New Orders Index, industry (sts_inop_m/sts_intv)", "MEDIUM", "Category exists at EU level (total/domestic/non-domestic orders) but FRED-QD's finer consumer/capital-goods order splits may not")
add("INVCQRMTSPL,BUSINVx", "CANDIDATE", "Eurostat/Statistik Austria industrial inventories survey balance (qualitative, from the EC Business Survey)", "LOW", "EU inventory data is typically a qualitative survey balance, not a real Chained-dollar level like FRED-QD's")
add("ISRATIOx", "DERIVABLE", note="Ratio of the inventories and sales candidates above, once both exist")

# --- Prices ---
add("PCECTPI,PCEPILFE", "CANDIDATE", "Eurostat HICP overall / HICP excl. food and energy (prc_hicp_midx)", "HIGH", "Dataflow existence confirmed live 2026-08-30 (structure query succeeds); exact dimension key not yet verified. HICP basket differs from the US PCE deflator's basket, but is the standard EU price-level proxy -- also the leading candidate to fix cpi_index's known staleness (see README Known issues)")
add("GDPCTPI,GPDICTPI", "DERIVABLE", note="Nominal/real ratio, once nominal GDP/GFCF (not currently fetched) are added alongside the real series already implemented")
add("IPDBS", "CANDIDATE", "Eurostat business-sector GVA deflator (derived from nominal/real GVA)", "LOW")
add("DGDSRG3Q086SBEA,DDURRG3Q086SBEA,DSERRG3Q086SBEA,DNDGRG3Q086SBEA,DHCERG3Q086SBEA,DMOTRG3Q086SBEA,DFDHRG3Q086SBEA,DREQRG3Q086SBEA,DODGRG3Q086SBEA,DFXARG3Q086SBEA,DCLORG3Q086SBEA,DGOERG3Q086SBEA,DONGRG3Q086SBEA,DHUTRG3Q086SBEA,DHLCRG3Q086SBEA,DTRSRG3Q086SBEA,DRCARG3Q086SBEA,DFSARG3Q086SBEA,DIFSRG3Q086SBEA,DOTSRG3Q086SBEA",
    "CANDIDATE", "Eurostat HICP by COICOP division/group (prc_hicp_midx), ~90 categories per country", "MEDIUM", "Conceptually parallel (price index by consumption category) but COICOP != BEA's NIPA categories; needs a category-by-category crosswalk, not a 1:1 code match")
add("CPILFESL", "CANDIDATE", "Eurostat HICP excl. energy, food, alcohol and tobacco (standard ECB core measure)", "HIGH")
add("WPSFD49207,PPIACO,WPSFD49502,WPSFD4111,PPIIDC,WPSID61,WPSID62,PPICMM", "CANDIDATE", "Eurostat/Statistik Austria Producer Price Index by MIG/NACE product group (sts_inpp_m)", "HIGH", "PPI with MIG breakdown (energy/intermediate/capital/durable/non-durable consumer goods) closely parallels several of these WPS series")
add("WPU0531,WPU0561", "CANDIDATE", "Eurostat PPI, NACE energy products (natural gas/petroleum)", "MEDIUM")
add("OILPRICEx", "CANDIDATE", "Same global benchmark (Brent/WTI) usable unchanged for any country -- not Austria-specific", "HIGH", "No country adaptation needed; could be added to the panel as-is")
add("CPIAPPSL,CPITRNSL,CPIMEDSL,CUSR0000SAC,CUSR0000SAD,CUSR0000SAS,CPIULFSL,CUSR0000SA0L2,CUSR0000SA0L5",
    "CANDIDATE", "Eurostat HICP by COICOP category (apparel, transport, health, durables/services, all-items-less-X variants)", "MEDIUM")
add("CUSR0000SEHC", "CANDIDATE", "Eurostat experimental owner-occupied housing (OOH) price index", "LOW", "HICP historically excludes owner-occupied housing costs; the OOH index is newer/experimental and coverage for AT is unconfirmed")

# --- Earnings and Productivity ---
add("AHETPIx,CES2000000008x,CES3000000008x,CES0600000008", "CANDIDATE", "Eurostat Labour Cost Index (LCI, quarterly, lc_lci_r2_q) by NACE", "HIGH")
add("COMPRMS,COMPRNFB,RCPHBS", "CANDIDATE", "Eurostat LCI, labour cost per hour worked, deflated by HICP", "MEDIUM")
add("OPHMFG,OPHNFB,OPHPBS", "CANDIDATE", "Eurostat labour productivity and unit labour costs (namq_10_lp_ulc)", "HIGH", "Dataflow existence confirmed live 2026-08-30; exact dimension key not yet verified. A direct quarterly Eurostat dataset for exactly this concept -- also a candidate UPGRADE for the already-implemented unit_labor_cost, which currently uses an OECD-mirror proxy")
add("ULCBS,ULCMFG", "CANDIDATE", "Eurostat namq_10_lp_ulc (see OPHMFG note above)", "HIGH", "Dataflow existence confirmed live 2026-08-30; exact dimension key not yet verified")
add("UNLPNBS", "NO_EQUIVALENT", note="Residual \"unit nonlabor payments\" concept specific to BLS productivity accounts construction")

# --- Interest Rates ---
add("FEDFUNDS", "CANDIDATE", "ECB main refinancing rate / €STR (euro-area-wide, not Austria-specific -- same as every euro-area country)", "HIGH")
add("TB3MS,TB6MS", "CANDIDATE", "Euribor 3-month / 6-month (euro-area-wide benchmark)", "HIGH")
add("GS1,GS5", "CANDIDATE", "ECB government bond yield curve, Austria-specific short maturities", "MEDIUM", "ECB publishes a AAA/all-bond euro area curve by maturity per country; exact Austria availability at 1y/5y unconfirmed")
add("AAA,BAA", "CANDIDATE", "ECB/iBoxx euro-area corporate bond yield indices", "MEDIUM", "Typically euro-area-wide, not Austria-specific")
add("BAA10YM,MORTG10YRx,TB6M3Mx,GS1TB3Mx,GS10TB3Mx,CPF3MTB3Mx,TB3SMFFM,T5YFFM,AAAFFM,COMPAPFF", "DERIVABLE", note="Spread series -- computed from the underlying rate-level candidates above once fetched, not a new source")
add("CP3M", "CANDIDATE", "Euro commercial paper rate (less standardized publicly than Euribor)", "LOW")

# --- Money and Credit ---
add("BOGMBASEREALx", "CANDIDATE", "ECB monetary base (BSI dataset), euro-area-wide", "MEDIUM")
add("M1REAL,M2REAL", "CANDIDATE", "ECB Monetary aggregates M1/M2/M3 (BSI dataset), euro-area-wide", "HIGH")
add("BUSLOANSx,CONSUMERx,NONREVSLx,REALLNx,REVOLSLx,TOTALSLx", "CANDIDATE", "ECB MFI Balance Sheet Items (BSI): loans to households/NFCs by purpose, genuinely country-specific", "HIGH", "Same ECB statistical family as the already-implemented mortgage_rate (MIR); BSI's loan breakdowns by counterpart sector and purpose are per-country")
add("DRIWCIL", "CANDIDATE", "ECB Bank Lending Survey (BLS), country-level results", "MEDIUM")
add("TOTRESNS,NONBORRES", "CANDIDATE", "ECB reserves data, euro-area-wide only (not allocable to Austria specifically)", "LOW")
add("DTCOLNVHFNM,DTCTHFNM", "NO_EQUIVALENT", note="US \"finance company\" sector is a specific US institutional category with no EU/ESA2010 equivalent")
add("INVEST", "CANDIDATE", "ECB BSI, MFI holdings of securities, country-specific", "MEDIUM")

# --- Household Balance Sheets ---
add("TABSHNOx,TLBSHNOx,TARESAx,HNOREMQ027Sx,TFAABSHNOx", "CANDIDATE", "ECB Quarterly Sector Accounts (QSA_PUB), other STO codes beyond B90", "LOW", "The already-implemented euro_area_household_net_worth_growth found ONLY the euro-area aggregate has data for STO=B90; other balance-sheet items in the same dataflow likely face the same per-country data gap, unconfirmed")
add("NWPIx,LIABPIx,CONSPIx", "DERIVABLE", note="Ratios to disposable income, once the corresponding level series exist")

# --- Exchange Rates ---
add("EXSZUSx,EXJPUSx,EXUSUKx,EXCAUSx", "CANDIDATE", "ECB euro reference rates vs. CHF/JPY/GBP/CAD", "HIGH", "Same ECB reference-rate source as the already-implemented fx_rate_to_usd; trivial extension to other currency pairs")

# --- Other ---
add("USEPUINDXM", "CANDIDATE", "policyuncertainty.com European/country EPU index", "LOW", "Austria is not confirmed among the individually-maintained country EPU indices on that site (Germany, France, Italy, UK are); a European-aggregate EPU index may be the closest available, not Austria-specific")

# --- Stock Markets ---
add("VIXCLSx", "CANDIDATE", "VSTOXX (Euro STOXX 50 Volatility Index), euro-area-wide, via Yahoo Finance ticker \"^V2TX\" or STOXX directly", "MEDIUM", "Not Austria-specific -- same proxy every euro-area country would use")
add("NIKKEI225,NASDAQCOM", "CANDIDATE", "No country adaptation needed -- these are global reference indices already comparable across countries as-is", "HIGH", "FRED-QD includes them as international benchmarks, not US-specific concepts; reusable unchanged for any country's panel")
add("S&P div yield,S&P PE ratio", "CANDIDATE", "Wiener Börse's own ATX statistics (not exposed via the Yahoo Finance chart API already used for the index level)", "LOW", "Would need a different endpoint/source than R/yahoo_finance.R's current chart API")

# --- Non-Household Balance Sheets ---
add("GFDEGDQ188S,GFDEBTNx", "CANDIDATE", "Eurostat quarterly government debt (Maastricht debt), gov_10q_ggdebt", "HIGH", "Dataflow existence confirmed live 2026-08-30; exact dimension key not yet verified. A standard, well-established EU quarterly series")
add("TLBSNNCBx,TTAABSNNCBx,TNWMVBSNNCBx,TNWMVBSNNCBBDIx,TLBSNNCBBDIx", "CANDIDATE", "Eurostat quarterly non-financial sector accounts, sector S11 (non-financial corporations)", "LOW", "May face the same per-country data-availability gap already found in the analogous ECB household QSA dataflow, unconfirmed")
add("TLBSNNBx,TLBSNNBBDIx,TABSNNBx,TNWBSNNBx,TNWBSNNBBDIx", "NO_EQUIVALENT", note="\"Non-corporate business\" (sole proprietorships) is a distinct US National Accounts sector; ESA2010 (the EU standard) folds this into the household sector (S14), so there is no separately-published Austrian equivalent")
add("CNCFx", "CANDIDATE", "Eurostat non-financial corporate sector accounts, disposable income/saving", "LOW")

# ---- 4. Assemble output rows ----
rows = []
for mnemonic, group, desc in catalog:
    if mnemonic in implemented_mnemonics:
        rows.append([mnemonic, group, desc, "IMPLEMENTED", "", "", "Already in production -- see docs/data_sources.csv"])
        continue
    if mnemonic == "DPIC96":
        rows.append([mnemonic, group, desc, "IMPLEMENTED (unresolved)", "", "", "Attempted (real_household_disposable_income); no source found for AT/DEU/USA -- see Known issues in README"])
        continue
    ann = A.get(mnemonic)
    if ann is None:
        rows.append([mnemonic, group, desc, "UNREVIEWED", "", "", "Not yet triaged in this pass"])
        continue
    status, source, confidence, note = ann
    rows.append([mnemonic, group, desc, status, source, confidence, note])

out_path = os.path.join(script_dir, "candidate_indicators_austria.csv")
with open(out_path, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["fred_qd_mnemonic", "fred_qd_group", "fred_qd_description", "status", "candidate_source", "confidence", "note"])
    w.writerows(rows)

print("Wrote", len(rows), "rows to", out_path)

# ---- 5. Coverage check ----
from collections import Counter
c = Counter(r[3] for r in rows)
print(c)
unreviewed = [r[0] for r in rows if r[3] == "UNREVIEWED"]
print("UNREVIEWED (", len(unreviewed), "):", unreviewed)
