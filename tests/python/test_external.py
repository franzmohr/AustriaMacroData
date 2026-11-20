"""Reading cached SDMX artefacts from SDMX-ML 2.1 and 3.0 structure messages."""

from __future__ import annotations

import pytest

from amd.external import parse_structure_message, structure_url
from amd.registry import Ref

SDMX_ML_30 = b"""<?xml version='1.0' encoding='UTF-8'?>
<message:Structure xmlns:message="http://www.sdmx.org/resources/sdmxml/schemas/v3_0/message"
  xmlns:str="http://www.sdmx.org/resources/sdmxml/schemas/v3_0/structure"
  xmlns:com="http://www.sdmx.org/resources/sdmxml/schemas/v3_0/common">
 <message:Structures><str:Codelists>
  <str:Codelist agencyID="SDMX" id="CL_AREA" version="2.0.1">
   <com:Name xml:lang="en">Reference area code list</com:Name>
   <str:Code id="M49"><com:Name xml:lang="en">M49 Group</com:Name></str:Code>
   <str:Code id="001"><com:Name xml:lang="en">World</com:Name><str:Parent>M49</str:Parent></str:Code>
   <str:Code id="AT"><com:Name xml:lang="fr">Autriche</com:Name><com:Name xml:lang="en">Austria</com:Name></str:Code>
  </str:Codelist>
 </str:Codelists></message:Structures>
</message:Structure>"""

SDMX_ML_21 = b"""<?xml version='1.0' encoding='UTF-8'?>
<message:Structure xmlns:message="http://www.sdmx.org/resources/sdmxml/schemas/v2_1/message"
  xmlns:str="http://www.sdmx.org/resources/sdmxml/schemas/v2_1/structure"
  xmlns:com="http://www.sdmx.org/resources/sdmxml/schemas/v2_1/common">
 <message:Structures><str:Codelists>
  <str:Codelist agencyID="ECB" id="CL_AREA" version="1.0">
   <com:Name xml:lang="en">Area</com:Name>
   <str:Code id="U2"><com:Name xml:lang="en">Euro area (changing
      composition)</com:Name></str:Code>
   <str:Code id="AT"><com:Name xml:lang="en">Austria</com:Name><str:Parent><Ref id="U2"/></str:Parent></str:Code>
  </str:Codelist>
 </str:Codelists></message:Structures>
</message:Structure>"""


def test_reads_sdmx_ml_30_with_text_parents_and_english_names():
    items = parse_structure_message(SDMX_ML_30, Ref.parse("SDMX:CL_AREA(2.0.1)"), "codelist")
    assert [(i.id, i.name_en, i.parent) for i in items] == [
        ("M49", "M49 Group", ""), ("001", "World", "M49"), ("AT", "Austria", "")]


def test_reads_sdmx_ml_21_with_ref_parents_and_folds_whitespace():
    items = parse_structure_message(SDMX_ML_21, Ref.parse("ECB:CL_AREA(1.0)"), "codelist")
    assert [(i.id, i.name_en, i.parent) for i in items] == [
        ("U2", "Euro area (changing composition)", ""), ("AT", "Austria", "U2")]


def test_refuses_another_version():
    with pytest.raises(ValueError, match=r"SDMX:CL_AREA\(2\.0\.1\)"):
        parse_structure_message(SDMX_ML_30, Ref.parse("SDMX:CL_AREA(2.1)"), "codelist")


def test_structure_urls():
    assert structure_url(Ref.parse("ESTAT:GEO(28.1)"), "codelist") == \
        "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/codelist/ESTAT/GEO/28.1"
    assert structure_url(Ref.parse("SDMX:CROSS_DOMAIN_CONCEPTS(2.0)"), "concept_scheme") == \
        "https://registry.sdmx.org/sdmx/v2/structure/conceptscheme/SDMX/CROSS_DOMAIN_CONCEPTS/2.0"
    with pytest.raises(ValueError):
        structure_url(Ref.parse("OECD:CL_AREA(1.0)"), "codelist")
