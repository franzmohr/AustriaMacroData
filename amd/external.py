"""Cache the SDMX artefacts the registry refers to but does not own.

`registry/external.csv` lists them: the SDMX cross-domain concepts and
codelists, the ECB's area codelist and concept scheme, Eurostat's GEO, the
BIS's area codelist. This module fetches each from its maintainer's
structure API, in exactly the version listed, and writes its items to
`registry/external/<AGENCY>_<ID>_<VERSION>.csv` (columns id, name_en,
parent). Validation reads only that cache, so a build never depends on these
services. Run it deliberately: `python -m amd registry fetch-external`.
"""

from __future__ import annotations

import csv
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from amd.registry import Ref

XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

#: Structure API of each maintenance agency. `{kind}` is codelist or conceptscheme.
ENDPOINTS = {
    "SDMX": "https://registry.sdmx.org/sdmx/v2/structure/{kind}/SDMX/{id}/{version}",
    "ECB": "https://data-api.ecb.europa.eu/service/{kind}/ECB/{id}/{version}",
    "ESTAT": "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/{kind}/ESTAT/{id}/{version}",
    "BIS": "https://stats.bis.org/api/v1/{kind}/BIS/{id}/{version}",
}
KINDS = {"codelist": "codelist", "concept_scheme": "conceptscheme"}
CONTAINERS = {"codelist": ("Codelist", "Code"), "concept_scheme": ("ConceptScheme", "Concept")}


@dataclass
class Item:
    id: str
    name_en: str
    parent: str = ""


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def parse_structure_message(xml: bytes, ref: Ref, artefact_type: str) -> list[Item]:
    """Read the items of one codelist or concept scheme from SDMX-ML 2.1 or 3.0.

    Raises ValueError if the message does not hold that artefact in that
    version, so a moved version is noticed rather than cached under the old
    name.
    """
    container_tag, item_tag = CONTAINERS[artefact_type]
    root = ET.fromstring(xml)
    for el in root.iter():
        if (_local(el.tag) == container_tag and el.get("id") == ref.id
                and el.get("agencyID") == ref.agency and el.get("version") == ref.version):
            container = el
            break
    else:
        found = sorted({f"{e.get('agencyID')}:{e.get('id')}({e.get('version')})"
                        for e in root.iter() if _local(e.tag) == container_tag})
        raise ValueError(f"{ref} not in the answer; it holds {found or 'no ' + container_tag}")

    items = []
    for el in container:
        if _local(el.tag) != item_tag:
            continue
        name = ""
        parent = ""
        for child in el:
            tag = _local(child.tag)
            if tag == "Name" and child.get(XML_LANG) == "en" and not name:
                name = " ".join((child.text or "").split())
            elif tag == "Parent":
                # SDMX-ML 3.0 writes the parent's ID as text, 2.1 as <Ref id=""/>
                ref_el = next(iter(child), None)
                parent = (ref_el.get("id") if ref_el is not None else (child.text or "")).strip()
        items.append(Item(el.get("id", ""), name, parent))
    if not items:
        raise ValueError(f"{ref} has no {item_tag} items in the answer")
    return items


def write_cache(items: list[Item], file: Path) -> None:
    file.parent.mkdir(parents=True, exist_ok=True)
    with file.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["id", "name_en", "parent"])
        for it in items:
            w.writerow([it.id, it.name_en, it.parent])


def structure_url(ref: Ref, artefact_type: str) -> str:
    if ref.agency not in ENDPOINTS:
        raise ValueError(f"no structure API known for agency {ref.agency}")
    return ENDPOINTS[ref.agency].format(kind=KINDS[artefact_type], id=ref.id, version=ref.version)


def _get(url: str, attempts: int = 3) -> bytes:
    import requests

    last = None
    for attempt in range(1, attempts + 1):
        try:
            resp = requests.get(url, timeout=120, headers={"Accept": "application/xml"})
            if resp.status_code == 200:
                return resp.content
            last = f"HTTP {resp.status_code}"
            if resp.status_code < 500 and resp.status_code != 429:
                break
        except requests.RequestException as e:
            last = str(e)
        time.sleep(5 * attempt)
    raise RuntimeError(f"{url}: {last}")


def fetch_external(registry_dir: Path | str = "registry", only: str | None = None) -> dict[str, str]:
    """Fetch every artefact of external.csv (or only one) into the cache.

    Returns artefact -> outcome ("N items" or the error), and leaves an
    existing cache file untouched when its fetch fails.
    """
    registry_dir = Path(registry_dir)
    with (registry_dir / "external.csv").open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    outcome = {}
    for row in rows:
        if only and row["artefact"] != only:
            continue
        ref = Ref.parse(row["artefact"])
        try:
            items = parse_structure_message(_get(structure_url(ref, row["type"])), ref, row["type"])
            write_cache(items, registry_dir / "external" / ref.cache_name)
            outcome[row["artefact"]] = f"{len(items)} items"
        except Exception as e:  # noqa: BLE001 -- reported per artefact, the rest still run
            outcome[row["artefact"]] = f"FAILED: {e}"
    return outcome
