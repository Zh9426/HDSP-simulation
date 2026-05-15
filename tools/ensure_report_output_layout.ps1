Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$reportRoot = Join-Path $repoRoot 'codex_managed_reports'
$localOutputRoot = Join-Path $repoRoot 'local_outputs'

if (-not (Test-Path $localOutputRoot)) {
    New-Item -ItemType Directory -Path $localOutputRoot | Out-Null
}

$localOutputIgnore = Join-Path $localOutputRoot '.gitignore'
if (-not (Test-Path $localOutputIgnore)) {
    Set-Content -Path $localOutputIgnore -Value @(
        '# Branch-local scratch outputs live here and stay out of Git.'
        '*'
        '!.gitignore'
    )
}

$workDirs = Get-ChildItem -Path $reportRoot -Directory
foreach ($workDir in $workDirs) {
    $outputDir = Join-Path $workDir.FullName 'outputs'
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    $keepFile = Join-Path $outputDir '.gitkeep'
    if (-not (Test-Path $keepFile)) {
        New-Item -ItemType File -Path $keepFile | Out-Null
    }
}
