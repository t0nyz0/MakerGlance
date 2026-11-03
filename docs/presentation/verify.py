#!/usr/bin/env python3
"""Structural and privacy-pattern checks; visual and assistive-tech review remain separate."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1] / "scripts"))
from check_repository import findings

def verify():
    pdf = PdfReader(ROOT / "MakerGlance.pdf")
    assert len(pdf.pages) == 10
    catalog = pdf.trailer["/Root"]
    assert catalog["/MarkInfo"]["/Marked"]
    assert catalog["/Lang"] == "en-US"
    tree = catalog["/StructTreeRoot"]
    sections = tree["/K"][0].get_object()["/K"]
    assert len(sections) == 10
    figures = 0
    for page, section_ref in zip(pdf.pages, sections):
        assert "/StructParents" in page
        text = page.extract_text()
        assert "MakerGlance" in text
        assert not findings(text.encode())
        for element_ref in section_ref.get_object()["/K"]:
            element = element_ref.get_object()
            if element["/S"] == "/Figure":
                assert element.get("/Alt", "").strip()
                figures += 1
    assert figures >= 8
    assert pdf.metadata.author == "MakerGlance project"
    assert not findings(str(pdf.metadata).encode())
    with ZipFile(ROOT / "MakerGlance.pptx") as archive:
        slides = [n for n in archive.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)]
        assert len(slides) == 10
        descriptions = 0
        for name in archive.namelist():
            if name.endswith((".xml", ".rels")):
                data = archive.read(name)
                assert not findings(data), name
                node = ET.fromstring(data)
                if name.endswith(".rels"):
                    assert all(r.attrib.get("TargetMode") != "External" for r in node), name
                if name in slides:
                    for picture in node.findall(".//{http://schemas.openxmlformats.org/presentationml/2006/main}pic"):
                        label = picture.find(".//{http://schemas.openxmlformats.org/presentationml/2006/main}cNvPr")
                        assert label is not None and label.attrib.get("descr", "").strip()
                        descriptions += 1
        assert descriptions == figures
        assert not any(n.endswith((".bin", ".vba")) for n in archive.namelist())
    print(f"Verified 10 PDF pages, 10 editable slides and {figures} described figures; no external slide relationships or checked privacy patterns.")

if __name__ == "__main__":
    verify()
