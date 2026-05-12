param(
    [string[]]$Branches,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Branches -or $Branches.Count -eq 0) {
    $Branches = git for-each-ref --format="%(refname:short)" refs/heads
}

$suspiciousPatterns = @(
    '^__pycache__$',
    '^codex_analysis$',
    '^codex_runs$',
    '^phase_board_exit_repair_outputs$',
    '^sonoink_test$',
    '^.*_outputs$',
    '^untitled_.*\.png$',
    '^.*\.asv$',
    '^2\.fig$'
)

$report = foreach ($branch in $Branches) {
    $entries = @(git ls-tree --name-only $branch)
    $hits = @()
    foreach ($entry in $entries) {
        foreach ($pattern in $suspiciousPatterns) {
            if ($entry -match $pattern) {
                $hits += $entry
                break
            }
        }
    }

    [pscustomobject]@{
        Branch = $branch
        TopLevelEntryCount = $entries.Count
        SuspiciousEntries = @($hits | Sort-Object -Unique)
    }
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 4
    exit 0
}

foreach ($item in $report) {
    $suspiciousEntries = @($item.SuspiciousEntries)
    if ($suspiciousEntries.Count -eq 0) {
        Write-Output ("[{0}] clean" -f $item.Branch)
        continue
    }

    Write-Output ("[{0}] suspicious: {1}" -f $item.Branch, ($suspiciousEntries -join ', '))
}
