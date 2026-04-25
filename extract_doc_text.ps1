$ErrorActionPreference = "Stop"

$outDir = "F:\GitHub\HDSP-simulation\doc_text_extract"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$files = @(
  "C:\Users\Zh89\Desktop\中期\赵鑫煜_2225113536_工作进展情况记录 (1).doc",
  "C:\Users\Zh89\Desktop\中期\赵鑫煜_2225113536_任务书.doc",
  "C:\Users\Zh89\Desktop\中期\赵鑫煜_2225113536_中期检查.doc"
)

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  foreach ($file in $files) {
    $doc = $word.Documents.Open($file, $false, $true)
    try {
      $base = [IO.Path]::GetFileNameWithoutExtension($file)
      $txt = Join-Path $outDir ($base + ".txt")
      # 7 = wdFormatUnicodeText
      $doc.SaveAs([ref]$txt, [ref]7)
      Write-Output $txt
    } finally {
      $doc.Close($false)
    }
  }
} finally {
  $word.Quit()
}
