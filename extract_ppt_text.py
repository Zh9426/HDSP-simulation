from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET


pptx_path = (
    Path.home()
    / "Desktop"
    / "\u4e2d\u671f"
    / "\u4e2d\u671f0422.pptx"
)

ns = {"a": "http://schemas.openxmlformats.org/drawingml/2006/main"}

with ZipFile(pptx_path) as zf:
    slide_names = sorted(
        [n for n in zf.namelist() if n.startswith("ppt/slides/slide") and n.endswith(".xml")],
        key=lambda n: int(n.rsplit("slide", 1)[1].split(".xml")[0]),
    )
    for idx, name in enumerate(slide_names, 1):
        root = ET.fromstring(zf.read(name))
        texts = []
        for t in root.findall(".//a:t", ns):
            if t.text and t.text.strip():
                texts.append(t.text.strip())
        print(f"\n--- SLIDE {idx} ---")
        print("\n".join(texts))
