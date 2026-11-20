"""The AMD registry: the SDMX artefacts this project declares, and their checks.

`registry/` holds, as CSV, everything the pipeline invents under the agency
AMD (concept scheme, codelists, data structures, dataflows) and everything it
refers to elsewhere (source dataflows, SDMX and ECB artefacts). See
docs/sdmx_pipeline.md, "The registry". `Registry.load()` reads it and
`Registry.validate()` returns every rule it breaks, so that no artefact is
only implied by the code.

Artefacts outside AMD are checked against a cached copy in
`registry/external/`, written by `amd.external.fetch_external()` and
refreshed deliberately, never during a build.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path

AGENCY = "AMD"

#: Representations that are not codelists (SDMX facets, simplified).
PRIMITIVES = frozenset({"String", "Double", "ObservationalTimePeriod"})

#: Roles of a component, in the order a data structure lists them.
ROLE_ORDER = ("dimension", "time_dimension", "measure", "attribute")
ATTACHMENTS = frozenset({"series", "observation", "dataflow"})
ASSIGNMENTS = frozenset({"mandatory", "conditional"})
LAYERS = frozenset({"silver", "gold"})
SOURCE_STATUSES = frozenset({"in_use", "proposed"})
EXTERNAL_TYPES = frozenset({"codelist", "concept_scheme"})

#: An AMD code: an SDMX ID restricted to upper case, as rule 3 asks.
AMD_CODE_RE = re.compile(r"^[A-Z0-9_]+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

_REF_RE = re.compile(
    r"^(?P<agency>[A-Za-z][A-Za-z0-9_.-]*):(?P<id>[A-Za-z0-9_@$-]+)"
    r"\((?P<version>\d+(?:\.\d+){1,2})\)$"
)
_ITEM_REF_RE = re.compile(r"^(?P<artefact>.+\))\.(?P<item>[A-Za-z0-9_@$-]+)$")

#: The columns every registry file must have, in this order.
COLUMNS = {
    "concepts": ["concept_scheme", "concept", "name_en", "name_de", "core_representation", "description"],
    "codelists": ["codelist", "name_en", "name_de", "description", "extends"],
    "codes": ["codelist", "code", "parent", "name_en", "name_de", "description", "source_code"],
    "data_structures": ["structure", "position", "component", "role", "concept", "representation",
                        "attachment", "assignment", "description"],
    "dataflows": ["dataflow", "structure", "layer", "source_agency", "name_en", "name_de", "description"],
    "source_dataflows": ["dataflow", "status", "checked", "answer_layout", "note"],
    "external": ["artefact", "type", "checked", "checked_at", "note"],
    "transformations": ["transformation", "indicator", "subindicator", "ref_area", "freq", "adjustment",
                        "steps", "inputs", "parameters", "note"],
    "panel_columns": ["label", "frequency", "INDICATOR", "SUBINDICATOR", "ADJUSTMENT"],
    "area_map": ["source_codelist", "source_code", "REF_AREA", "note"],
}

#: The codelists other files are checked against.
CL_INDICATOR = "AMD:CL_INDICATOR(1.0)"
CL_SUBINDICATOR = "AMD:CL_SUBINDICATOR(1.0)"
CL_AREA = "AMD:CL_AREA(1.0)"
CL_DATA_COMP = "AMD:CL_DATA_COMP(1.0)"
CL_SOURCE_AGENCY = "AMD:CL_SOURCE_AGENCY(1.0)"
CL_FREQ = "SDMX:CL_FREQ(2.1)"
CL_SEASONAL_ADJUST = "SDMX:CL_SEASONAL_ADJUST(1.0)"


class RegistryError(Exception):
    """Raised by `Registry.check()` with every broken rule in its message."""


@dataclass(frozen=True)
class Ref:
    """A maintainable artefact reference, `AGENCY:ID(VERSION)`."""

    agency: str
    id: str
    version: str

    @classmethod
    def parse(cls, text: str) -> "Ref":
        m = _REF_RE.match(text)
        if not m:
            raise ValueError(f"not an SDMX artefact reference AGENCY:ID(VERSION): {text!r}")
        return cls(m["agency"], m["id"], m["version"])

    def __str__(self) -> str:
        return f"{self.agency}:{self.id}({self.version})"

    @property
    def cache_name(self) -> str:
        """File name of this artefact's cached copy in `registry/external/`."""
        return f"{self.agency}_{self.id}_{self.version}.csv"


def split_item_ref(text: str) -> tuple[Ref, str]:
    """Split `AGENCY:SCHEME(VERSION).ITEM`, e.g. a concept reference."""
    m = _ITEM_REF_RE.match(text)
    if not m:
        raise ValueError(f"not an item reference AGENCY:ID(VERSION).ITEM: {text!r}")
    return Ref.parse(m["artefact"]), m["item"]


def is_ref(text: str) -> bool:
    return bool(_REF_RE.match(text))


def _read(path: Path, name: str, errors: list[str]) -> list[dict[str, str]]:
    file = path / f"{name}.csv"
    if not file.exists():
        errors.append(f"{name}.csv: missing")
        return []
    with file.open(newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader, [])
        rows = list(reader)
    if header != COLUMNS[name]:
        errors.append(f"{name}.csv: columns are {header}, expected {COLUMNS[name]}")
        return []
    out = []
    for i, row in enumerate(rows, start=2):
        if len(row) != len(header):
            errors.append(f"{name}.csv line {i}: {len(row)} fields, expected {len(header)}")
            continue
        out.append(dict(zip(header, row)))
    return out


def read_external_cache(file: Path) -> dict[str, dict[str, str]]:
    """Read one cached external artefact: item ID to its row."""
    with file.open(newline="", encoding="utf-8") as fh:
        return {row["id"]: row for row in csv.DictReader(fh)}


class Registry:
    """Everything in `registry/`, loaded and indexed."""

    def __init__(self, path: Path | str):
        self.path = Path(path)
        self.load_errors: list[str] = []
        read = lambda name: _read(self.path, name, self.load_errors)  # noqa: E731
        self.concepts = read("concepts")
        self.codelists = read("codelists")
        self.codes = read("codes")
        self.components = read("data_structures")
        self.dataflows = read("dataflows")
        self.source_dataflows = read("source_dataflows")
        self.external = read("external")
        self.transformations = read("transformations")
        self.panel_columns = read("panel_columns")
        self.area_map = read("area_map")

        self.external_cache: dict[str, dict[str, dict[str, str]]] = {}
        for row in self.external:
            if not is_ref(row["artefact"]):
                continue
            file = self.path / "external" / Ref.parse(row["artefact"]).cache_name
            if file.exists():
                self.external_cache[row["artefact"]] = read_external_cache(file)

    @classmethod
    def load(cls, path: Path | str = "registry") -> "Registry":
        return cls(path)

    # -- lookups -----------------------------------------------------------

    @property
    def codelist_ids(self) -> set[str]:
        return {r["codelist"] for r in self.codelists}

    @property
    def external_ids(self) -> set[str]:
        return {r["artefact"] for r in self.external}

    def codes_of(self, codelist: str) -> set[str] | None:
        """Every valid code of a codelist, or None if it cannot be known here.

        An AMD codelist's codes are its own plus those of the codelist it
        extends; an external codelist's are those of its cached copy.
        """
        if codelist in self.codelist_ids:
            own = {r["code"] for r in self.codes if r["codelist"] == codelist}
            parent = next(r["extends"] for r in self.codelists if r["codelist"] == codelist)
            if parent:
                inherited = self.codes_of(parent)
                if inherited is None:
                    return None
                own |= inherited
            return own
        cached = self.external_cache.get(codelist)
        return set(cached) if cached is not None else None

    def concepts_of(self, scheme: str) -> set[str] | None:
        """Every concept ID of a concept scheme, or None if not known here."""
        own = {r["concept"] for r in self.concepts if r["concept_scheme"] == scheme}
        if own:
            return own
        cached = self.external_cache.get(scheme)
        return set(cached) if cached is not None else None

    def structure(self, ref: str) -> list[dict[str, str]]:
        """The components of one data structure, in position order."""
        rows = [r for r in self.components if r["structure"] == ref]
        return sorted(rows, key=lambda r: int(r["position"]) if r["position"].isdigit() else 0)

    @property
    def structure_ids(self) -> set[str]:
        return {r["structure"] for r in self.components}

    @property
    def dataflow_ids(self) -> set[str]:
        return {r["dataflow"] for r in self.dataflows} | {r["dataflow"] for r in self.source_dataflows}

    # -- validation --------------------------------------------------------

    def validate(self) -> list[str]:
        """Return every rule the registry breaks; empty if it is valid."""
        errors = list(self.load_errors)
        for check in (
            self._check_external,
            self._check_codelists,
            self._check_codes,
            self._check_concepts,
            self._check_structures,
            self._check_dataflows,
            self._check_source_dataflows,
            self._check_panel_columns,
            self._check_transformations,
            self._check_area_map,
        ):
            errors.extend(check())
        return errors

    def check(self) -> None:
        """Raise `RegistryError` listing every broken rule, if any."""
        errors = self.validate()
        if errors:
            raise RegistryError(f"{len(errors)} registry error(s):\n" + "\n".join(errors))

    def _codes_or_error(self, codelist: str, where: str, errors: list[str]) -> set[str] | None:
        codes = self.codes_of(codelist)
        if codes is None:
            errors.append(f"{where}: codes of {codelist} unknown (not declared, or not cached in "
                          f"registry/external/; run `python -m amd registry fetch-external`)")
        return codes

    def _check_external(self) -> list[str]:
        errors: list[str] = []
        seen = set()
        for r in self.external:
            a = r["artefact"]
            where = f"external.csv {a}"
            if not is_ref(a):
                errors.append(f"{where}: not an artefact reference")
                continue
            if a in seen:
                errors.append(f"{where}: listed twice")
            seen.add(a)
            if Ref.parse(a).agency == AGENCY:
                errors.append(f"{where}: AMD artefacts are declared, not listed as external")
            if r["type"] not in EXTERNAL_TYPES:
                errors.append(f"{where}: type {r['type']!r} is not one of {sorted(EXTERNAL_TYPES)}")
            if not DATE_RE.match(r["checked"]):
                errors.append(f"{where}: checked {r['checked']!r} is not a YYYY-MM-DD date")
            if a not in self.external_cache:
                errors.append(f"{where}: no cached copy {Ref.parse(a).cache_name} in registry/external/ "
                              f"(run `python -m amd registry fetch-external`)")
        return errors

    def _check_codelists(self) -> list[str]:
        errors: list[str] = []
        seen = set()
        for r in self.codelists:
            cl = r["codelist"]
            where = f"codelists.csv {cl}"
            if not is_ref(cl):
                errors.append(f"{where}: not an artefact reference")
                continue
            ref = Ref.parse(cl)
            if cl in seen:
                errors.append(f"{where}: declared twice")
            seen.add(cl)
            if ref.agency != AGENCY:
                errors.append(f"{where}: declared codelists belong to AMD")
            if not ref.id.startswith("CL_"):
                errors.append(f"{where}: a codelist is named CL_<CONCEPT>")
            if not r["name_en"]:
                errors.append(f"{where}: no English name")
            if r["extends"]:
                ext = next((e for e in self.external if e["artefact"] == r["extends"]), None)
                if ext is None or ext["type"] != "codelist":
                    errors.append(f"{where}: extends {r['extends']}, which is not an external codelist")
            if not any(c["codelist"] == cl for c in self.codes):
                errors.append(f"{where}: has no codes")
        return errors

    def _check_codes(self) -> list[str]:
        errors: list[str] = []
        declared = self.codelist_ids
        seen: set[tuple[str, str]] = set()
        for r in self.codes:
            cl, code = r["codelist"], r["code"]
            where = f"codes.csv {cl} {code}"
            if cl not in declared:
                errors.append(f"{where}: codelist not declared in codelists.csv")
            if not AMD_CODE_RE.match(code):
                errors.append(f"{where}: an AMD code is an upper-case SDMX ID ([A-Z0-9_]+)")
            if (cl, code) in seen:
                errors.append(f"{where}: declared twice")
            seen.add((cl, code))
            if not r["name_en"]:
                errors.append(f"{where}: no English name")
        for r in self.codes:
            if r["parent"] and (r["codelist"], r["parent"]) not in seen:
                errors.append(f"codes.csv {r['codelist']} {r['code']}: parent {r['parent']} is not in the codelist")
        return errors

    def _check_representation(self, rep: str, where: str) -> list[str]:
        if rep in PRIMITIVES:
            return []
        if not is_ref(rep):
            return [f"{where}: representation {rep!r} is neither {sorted(PRIMITIVES)} nor a codelist"]
        if rep in self.codelist_ids:
            return []
        ext = next((e for e in self.external if e["artefact"] == rep), None)
        if ext is None or ext["type"] != "codelist":
            return [f"{where}: codelist {rep} is neither declared nor listed in external.csv"]
        return []

    def _check_concepts(self) -> list[str]:
        errors: list[str] = []
        seen = set()
        for r in self.concepts:
            where = f"concepts.csv {r['concept']}"
            if not is_ref(r["concept_scheme"]) or Ref.parse(r["concept_scheme"]).agency != AGENCY:
                errors.append(f"{where}: declared concepts belong to an AMD concept scheme")
            if not AMD_CODE_RE.match(r["concept"]):
                errors.append(f"{where}: a concept ID is upper case")
            key = (r["concept_scheme"], r["concept"])
            if key in seen:
                errors.append(f"{where}: declared twice")
            seen.add(key)
            if not r["name_en"]:
                errors.append(f"{where}: no English name")
            errors.extend(self._check_representation(r["core_representation"], where))
        return errors

    def _check_structures(self) -> list[str]:
        errors: list[str] = []
        for ref in sorted(self.structure_ids):
            where = f"data_structures.csv {ref}"
            if not is_ref(ref) or Ref.parse(ref).agency != AGENCY:
                errors.append(f"{where}: declared structures belong to AMD")
            rows = [r for r in self.components if r["structure"] == ref]
            positions = sorted(int(r["position"]) for r in rows if r["position"].isdigit())
            if positions != list(range(1, len(rows) + 1)):
                errors.append(f"{where}: positions must run 1..{len(rows)} without gaps or repeats")
            comps = self.structure(ref)
            ids = [c["component"] for c in comps]
            if len(set(ids)) != len(ids):
                errors.append(f"{where}: a component appears twice")
            roles = [c["role"] for c in comps]
            bad_roles = [x for x in roles if x not in ROLE_ORDER]
            if bad_roles:
                errors.append(f"{where}: unknown role(s) {bad_roles}")
                continue
            if [ROLE_ORDER.index(x) for x in roles] != sorted(ROLE_ORDER.index(x) for x in roles):
                errors.append(f"{where}: components must run dimensions, time dimension, measure, attributes")
            if roles.count("time_dimension") != 1 or roles.count("measure") != 1:
                errors.append(f"{where}: needs exactly one time dimension and one measure")
            if "dimension" not in roles:
                errors.append(f"{where}: needs at least one dimension")
            for c in comps:
                cw = f"{where} {c['component']}"
                if c["role"] == "time_dimension" and c["component"] != "TIME_PERIOD":
                    errors.append(f"{cw}: the time dimension is TIME_PERIOD")
                if c["role"] == "measure" and c["component"] != "OBS_VALUE":
                    errors.append(f"{cw}: the measure is OBS_VALUE")
                if (c["role"] == "attribute") != bool(c["attachment"]):
                    errors.append(f"{cw}: an attribute, and only an attribute, has an attachment level")
                if c["attachment"] and c["attachment"] not in ATTACHMENTS:
                    errors.append(f"{cw}: attachment {c['attachment']!r} is not one of {sorted(ATTACHMENTS)}")
                if c["assignment"] not in ASSIGNMENTS:
                    errors.append(f"{cw}: assignment {c['assignment']!r} is not one of {sorted(ASSIGNMENTS)}")
                if c["role"] != "attribute" and c["assignment"] != "mandatory":
                    errors.append(f"{cw}: dimensions, the time dimension and the measure are mandatory")
                try:
                    scheme, concept = split_item_ref(c["concept"])
                except ValueError as e:
                    errors.append(f"{cw}: {e}")
                    continue
                if concept != c["component"]:
                    errors.append(f"{cw}: component ID differs from its concept {concept}")
                known = self.concepts_of(str(scheme))
                if known is None:
                    errors.append(f"{cw}: concept scheme {scheme} is neither declared nor cached")
                elif concept not in known:
                    errors.append(f"{cw}: concept {concept} is not in {scheme}")
                errors.extend(self._check_representation(c["representation"], cw))
        return errors

    def _check_dataflows(self) -> list[str]:
        errors: list[str] = []
        agencies = self.codes_of(CL_SOURCE_AGENCY) or set()
        seen = set()
        for r in self.dataflows:
            where = f"dataflows.csv {r['dataflow']}"
            if not is_ref(r["dataflow"]) or Ref.parse(r["dataflow"]).agency != AGENCY:
                errors.append(f"{where}: declared dataflows belong to AMD")
            if r["dataflow"] in seen:
                errors.append(f"{where}: declared twice")
            seen.add(r["dataflow"])
            if r["structure"] not in self.structure_ids:
                errors.append(f"{where}: structure {r['structure']} is not declared")
            if r["layer"] not in LAYERS:
                errors.append(f"{where}: layer {r['layer']!r} is not one of {sorted(LAYERS)}")
            if r["source_agency"] not in agencies:
                errors.append(f"{where}: source agency {r['source_agency']} is not in {CL_SOURCE_AGENCY}")
        used = {r["structure"] for r in self.dataflows}
        for s in sorted(self.structure_ids - used):
            errors.append(f"data_structures.csv {s}: no dataflow uses it")
        return errors

    def _check_source_dataflows(self) -> list[str]:
        errors: list[str] = []
        seen = set()
        for r in self.source_dataflows:
            where = f"source_dataflows.csv {r['dataflow']}"
            if not is_ref(r["dataflow"]):
                errors.append(f"{where}: not an artefact reference")
                continue
            if Ref.parse(r["dataflow"]).agency == AGENCY:
                errors.append(f"{where}: AMD dataflows belong in dataflows.csv")
            if r["dataflow"] in seen:
                errors.append(f"{where}: listed twice")
            seen.add(r["dataflow"])
            if r["status"] not in SOURCE_STATUSES:
                errors.append(f"{where}: status {r['status']!r} is not one of {sorted(SOURCE_STATUSES)}")
            if r["checked"] and not DATE_RE.match(r["checked"]):
                errors.append(f"{where}: checked {r['checked']!r} is not a YYYY-MM-DD date")
        return errors

    def _check_panel_columns(self) -> list[str]:
        errors: list[str] = []
        ind = self._codes_or_error(CL_INDICATOR, "panel_columns.csv", errors) or set()
        sub = self._codes_or_error(CL_SUBINDICATOR, "panel_columns.csv", errors) or set()
        freq = self._codes_or_error(CL_FREQ, "panel_columns.csv", errors) or set()
        adj = self._codes_or_error(CL_SEASONAL_ADJUST, "panel_columns.csv", errors) or set()
        labels, keys = set(), set()
        for r in self.panel_columns:
            where = f"panel_columns.csv {r['label']}"
            if r["label"] in labels:
                errors.append(f"{where}: listed twice")
            labels.add(r["label"])
            for value, codes, name in ((r["INDICATOR"], ind, "INDICATOR"), (r["SUBINDICATOR"], sub, "SUBINDICATOR"),
                                       (r["frequency"], freq, "frequency"), (r["ADJUSTMENT"], adj, "ADJUSTMENT")):
                if codes and value not in codes:
                    errors.append(f"{where}: {name} {value} is not a declared code")
            key = (r["INDICATOR"], r["SUBINDICATOR"], r["ADJUSTMENT"], r["frequency"])
            if key in keys:
                errors.append(f"{where}: another column maps to the same series {key}")
            keys.add(key)
        return errors

    def _check_transformations(self) -> list[str]:
        errors: list[str] = []
        ind = self.codes_of(CL_INDICATOR) or set()
        sub = self.codes_of(CL_SUBINDICATOR) or set()
        comp = self.codes_of(CL_DATA_COMP) or set()
        freq = self.codes_of(CL_FREQ) or set()
        adj = self.codes_of(CL_SEASONAL_ADJUST) or set()
        flows = self.dataflow_ids
        seen = set()
        for r in self.transformations:
            where = f"transformations.csv {r['transformation']}"
            if r["transformation"] in seen:
                errors.append(f"{where}: declared twice")
            seen.add(r["transformation"])
            if r["indicator"] not in ind:
                errors.append(f"{where}: indicator {r['indicator']} is not in {CL_INDICATOR}")
            if r["subindicator"] not in sub:
                errors.append(f"{where}: subindicator {r['subindicator']} is not in {CL_SUBINDICATOR}")
            if freq and r["freq"] not in freq:
                errors.append(f"{where}: freq {r['freq']} is not in {CL_FREQ}")
            if adj and r["adjustment"] not in adj:
                errors.append(f"{where}: adjustment {r['adjustment']} is not in {CL_SEASONAL_ADJUST}")
            for step in (s.strip() for s in r["steps"].split(">")):
                if step not in comp:
                    errors.append(f"{where}: step {step} is not in {CL_DATA_COMP}")
            for inp in (s.strip() for s in r["inputs"].split(" + ")):
                flow = inp.split("/", 1)[0]
                if flow not in flows:
                    errors.append(f"{where}: input from {flow}, which is neither an AMD nor a listed source dataflow")
        return errors

    def _check_area_map(self) -> list[str]:
        errors: list[str] = []
        area = self._codes_or_error(CL_AREA, "area_map.csv", errors) or set()
        for r in self.area_map:
            where = f"area_map.csv {r['source_codelist']} {r['source_code']}"
            if r["REF_AREA"] != "*" and area and r["REF_AREA"] not in area:
                errors.append(f"{where}: REF_AREA {r['REF_AREA']} is not in {CL_AREA}")
            source = self.external_cache.get(r["source_codelist"])
            if source is not None and r["source_code"] not in source:
                errors.append(f"{where}: {r['source_code']} is not a code of {r['source_codelist']}")
        return errors
