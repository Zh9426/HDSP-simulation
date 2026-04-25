from pathlib import Path

import win32com.client


base = Path.home() / "Desktop" / "\u4e2d\u671f"
files = [
    base / "\u8d75\u946b\u715c_2225113536_\u5de5\u4f5c\u8fdb\u5c55\u60c5\u51b5\u8bb0\u5f55 (1).doc",
    base / "\u8d75\u946b\u715c_2225113536_\u4efb\u52a1\u4e66.doc",
    base / "\u8d75\u946b\u715c_2225113536_\u4e2d\u671f\u68c0\u67e5.doc",
]

out_dir = Path(r"F:\GitHub\HDSP-simulation\doc_text_extract")
out_dir.mkdir(parents=True, exist_ok=True)

word = win32com.client.Dispatch("Word.Application")
word.Visible = False
word.DisplayAlerts = 0
try:
    for path in files:
        doc = word.Documents.Open(str(path), False, True)
        try:
            out = out_dir / f"{path.stem}.txt"
            # 7 = wdFormatUnicodeText
            doc.SaveAs(str(out), 7)
            print(out)
        finally:
            doc.Close(False)
finally:
    word.Quit()
