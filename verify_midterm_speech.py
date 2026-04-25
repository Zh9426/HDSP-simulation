from pathlib import Path

from docx import Document


docx_path = (
    Path.home()
    / "Desktop"
    / "\u4e2d\u671f"
    / "\u4e2d\u671f0421.1_\u4e03\u5206\u949f\u9010\u9875\u8bb2\u7a3f.docx"
)

doc = Document(docx_path)
for para in doc.paragraphs:
    text = para.text.strip()
    if (
        "\u7b2c8\u9875" in text
        or "\u7b2c\u56db\u9636\u6bb5\u4e0d\u662f\u4e00\u6b21\u6027" in text
        or "\u7b2c12\u9875" in text
        or "\u6309\u7167\u4ee3\u7801\u8fed\u4ee3\u8bb0\u5f55" in text
    ):
        print(text)
