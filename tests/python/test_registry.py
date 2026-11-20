"""The AMD registry: the committed files are valid, and each rule bites.

Each rule is tested by copying the committed registry, breaking exactly one
thing, and checking that validation names it. No test touches the network:
external artefacts come from the cache in registry/external/.
"""

from __future__ import annotations

import csv
import shutil
from pathlib import Path

import pytest

from amd.registry import Ref, Registry, RegistryError, split_item_ref

REGISTRY = Path(__file__).resolve().parents[2] / "registry"


@pytest.fixture
def reg_dir(tmp_path: Path) -> Path:
    target = tmp_path / "registry"
    shutil.copytree(REGISTRY, target)
    return target


def edit(reg_dir: Path, name: str, change) -> None:
    """Apply `change(rows)` to the rows (header first) of one registry file."""
    file = reg_dir / f"{name}.csv"
    with file.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    rows = change(rows) or rows
    with file.open("w", newline="", encoding="utf-8") as fh:
        csv.writer(fh, lineterminator="\n").writerows(rows)


def set_cell(rows, match: dict, column: str, value: str):
    header = rows[0]
    hits = [r for r in rows[1:] if all(r[header.index(k)] == v for k, v in match.items())]
    assert hits, f"no row matches {match}"
    hits[0][header.index(column)] = value


def errors_of(reg_dir: Path) -> list[str]:
    return Registry.load(reg_dir).validate()


def assert_error(reg_dir: Path, fragment: str) -> None:
    errors = errors_of(reg_dir)
    assert any(fragment in e for e in errors), f"no error containing {fragment!r} in {errors}"


# -- the committed registry ---------------------------------------------------

def test_committed_registry_is_valid():
    assert Registry.load(REGISTRY).validate() == []


def test_check_raises_with_every_error(reg_dir):
    edit(reg_dir, "codes", lambda rows: set_cell(rows, {"code": "REAL_GDP"}, "code", "real_gdp"))
    with pytest.raises(RegistryError, match="upper-case"):
        Registry.load(reg_dir).check()


def test_area_codelist_extends_sdmx_with_iso_aggregates():
    codes = Registry.load(REGISTRY).codes_of("AMD:CL_AREA(1.0)")
    assert {"AT", "DE", "US", "GR", "EU", "EZ", "XW"} <= codes
    assert not {"U2", "B0", "EL", "W1"} & codes


def test_every_panel_column_is_mapped():
    labels = {r["label"] for r in Registry.load(REGISTRY).panel_columns}
    with (REGISTRY.parent / "output" / "semantic" / "concepts.csv").open(newline="", encoding="utf-8") as fh:
        concepts = {r["label"] for r in csv.DictReader(fh)}
    assert labels == concepts


# -- references ---------------------------------------------------------------

@pytest.mark.parametrize("text, agency, id_, version", [
    ("AMD:INDICATORS(1.0)", "AMD", "INDICATORS", "1.0"),
    ("OECD.SDD.STES:DSD_KEI@DF_KEI(4.0)", "OECD.SDD.STES", "DSD_KEI@DF_KEI", "4.0"),
    ("IMF.STA:QNEA(7.0.0)", "IMF.STA", "QNEA", "7.0.0"),
])
def test_ref_parses(text, agency, id_, version):
    ref = Ref.parse(text)
    assert (ref.agency, ref.id, ref.version) == (agency, id_, version)
    assert str(ref) == text


@pytest.mark.parametrize("text", ["AMD:INDICATORS", "INDICATORS(1.0)", "AMD:IND ICATORS(1.0)", "AMD:X(v1)"])
def test_ref_rejects(text):
    with pytest.raises(ValueError):
        Ref.parse(text)


def test_item_ref_splits_after_the_version():
    ref, item = split_item_ref("SDMX:CROSS_DOMAIN_CONCEPTS(2.0).FREQ")
    assert (str(ref), item) == ("SDMX:CROSS_DOMAIN_CONCEPTS(2.0)", "FREQ")


# -- each rule ----------------------------------------------------------------

def test_lower_case_code(reg_dir):
    edit(reg_dir, "codes", lambda rows: set_cell(rows, {"code": "REAL_GDP"}, "code", "real_gdp"))
    assert_error(reg_dir, "upper-case SDMX ID")


def test_code_in_undeclared_codelist(reg_dir):
    edit(reg_dir, "codes", lambda rows: rows.append(["AMD:CL_NOPE(1.0)", "X", "", "x", "", "", ""]))
    assert_error(reg_dir, "codelist not declared")


def test_duplicate_code(reg_dir):
    edit(reg_dir, "codes", lambda rows: rows.append(list(rows[1])))
    assert_error(reg_dir, "declared twice")


def test_code_without_english_name(reg_dir):
    edit(reg_dir, "codes", lambda rows: set_cell(rows, {"code": "REAL_GDP"}, "name_en", ""))
    assert_error(reg_dir, "no English name")


def test_codelist_named_otherwise(reg_dir):
    def change(rows):
        set_cell(rows, {"codelist": "AMD:CL_TICKER(1.0)"}, "codelist", "AMD:TICKERS(1.0)")
    edit(reg_dir, "codelists", change)
    assert_error(reg_dir, "named CL_<CONCEPT>")


def test_extends_must_be_external(reg_dir):
    edit(reg_dir, "codelists", lambda rows: set_cell(rows, {"codelist": "AMD:CL_AREA(1.0)"},
                                                      "extends", "SDMX:CL_NOPE(1.0)"))
    assert_error(reg_dir, "which is not an external codelist")


def test_structure_position_gap(reg_dir):
    edit(reg_dir, "data_structures", lambda rows: set_cell(
        rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "OBS_VALUE"}, "position", "9"))
    assert_error(reg_dir, "positions must run 1..5")


def test_structure_role_order(reg_dir):
    def change(rows):
        set_cell(rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "TICKER"}, "position", "4")
        set_cell(rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "TIME_PERIOD"}, "position", "2")
    edit(reg_dir, "data_structures", change)
    assert_error(reg_dir, "must run dimensions, time dimension, measure, attributes")


def test_component_concept_missing_from_scheme(reg_dir):
    edit(reg_dir, "data_structures", lambda rows: set_cell(
        rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "TICKER"}, "concept",
        "SDMX:CROSS_DOMAIN_CONCEPTS(2.0).TICKER"))
    assert_error(reg_dir, "concept TICKER is not in SDMX:CROSS_DOMAIN_CONCEPTS(2.0)")


def test_component_with_undeclared_codelist(reg_dir):
    edit(reg_dir, "data_structures", lambda rows: set_cell(
        rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "TICKER"}, "representation", "AMD:CL_NOPE(1.0)"))
    assert_error(reg_dir, "neither declared nor listed")


def test_dimension_with_attachment(reg_dir):
    edit(reg_dir, "data_structures", lambda rows: set_cell(
        rows, {"structure": "AMD:DSD_YAHOO(1.0)", "component": "TICKER"}, "attachment", "series"))
    assert_error(reg_dir, "only an attribute, has an attachment level")


def test_dataflow_without_structure(reg_dir):
    edit(reg_dir, "dataflows", lambda rows: set_cell(rows, {"dataflow": "AMD:YAHOO(1.0)"},
                                                      "structure", "AMD:DSD_NOPE(1.0)"))
    assert_error(reg_dir, "structure AMD:DSD_NOPE(1.0) is not declared")


def test_panel_column_with_unknown_indicator(reg_dir):
    edit(reg_dir, "panel_columns", lambda rows: set_cell(rows, {"label": "real_gdp"}, "INDICATOR", "GDP"))
    assert_error(reg_dir, "INDICATOR GDP is not a declared code")


def test_panel_column_with_unknown_adjustment(reg_dir):
    edit(reg_dir, "panel_columns", lambda rows: set_cell(rows, {"label": "real_gdp"}, "ADJUSTMENT", "SCA"))
    assert_error(reg_dir, "ADJUSTMENT SCA is not a declared code")


def test_transformation_from_undeclared_dataflow(reg_dir):
    edit(reg_dir, "transformations", lambda rows: set_cell(
        rows, {"transformation": "BANK_TOTAL_ASSETS.SCALE"}, "inputs", "ECB:NOPE(1.0)/Q.AT"))
    assert_error(reg_dir, "input from ECB:NOPE(1.0)")


def test_transformation_with_unknown_step(reg_dir):
    edit(reg_dir, "transformations", lambda rows: set_cell(
        rows, {"transformation": "BANK_TOTAL_ASSETS.SCALE"}, "steps", "MULTIPLY"))
    assert_error(reg_dir, "step MULTIPLY is not in")


def test_area_map_to_unknown_area(reg_dir):
    edit(reg_dir, "area_map", lambda rows: set_cell(rows, {"source_code": "U2"}, "REF_AREA", "EA"))
    assert_error(reg_dir, "REF_AREA EA is not in AMD:CL_AREA(1.0)")


def test_area_map_from_unknown_source_code(reg_dir):
    edit(reg_dir, "area_map", lambda rows: set_cell(rows, {"source_code": "U2"}, "source_code", "ZZ9"))
    assert_error(reg_dir, "ZZ9 is not a code of ECB:CL_AREA(1.0)")


def test_missing_external_cache(reg_dir):
    (reg_dir / "external" / "SDMX_CL_FREQ_2.1.csv").unlink()
    assert_error(reg_dir, "no cached copy SDMX_CL_FREQ_2.1.csv")


def test_wrong_columns(reg_dir):
    edit(reg_dir, "dataflows", lambda rows: rows[0].__setitem__(0, "flow"))
    assert_error(reg_dir, "dataflows.csv: columns are")
