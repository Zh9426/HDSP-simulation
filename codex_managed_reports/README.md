# Codex Managed Work Archive

This directory is organized as one folder per work stream. Each work folder contains:

- `report.md` - latest written status, conclusions, and next decision.
- `src_stable/` - stable source snapshot used by the current `codex_managed` branch, when available.
- `src_latest/` - latest exploratory source snapshot from the relevant research branch, when different from the stable version.
- `outputs/` - runtime-generated summaries, figures, and matrix data produced by the work stream's primary entry script.

`codex_managed_reports/*/outputs/` is allowed in git and is the only endorsed place for committed runtime artifacts.
`local_outputs/` is the dedicated ignored scratch area for branch-local runs that should not enter git.
Root-level experiment outputs, temporary datasets, checkpoints, and other ad hoc local output directories remain excluded.

## Output Rules

1. Data that must survive branch cleanup or branch switching belongs in `codex_managed_reports/<work>/outputs/` and should be tracked.
2. Data that is only for one local run belongs in `local_outputs/<branch-name>/` and is intentionally ignored.
3. Do not create new root-level `*_outputs/` folders for preserved results. Those are treated as disposable local scratch.
4. Run `tools/ensure_report_output_layout.ps1` after adding a new work stream so the archive `outputs/` folder and `.gitkeep` anchor exist immediately.

## Branch Hygiene

Run `tools/audit_branch_hygiene.ps1` to scan local branches for common cross-branch leftovers such as `__pycache__`, root output folders, `codex_analysis`, `codex_runs`, and preview files.

## Work Streams

| Directory | Purpose |
|---|---|
| `01_mainline_full_pipeline/` | Current HDSP mainline script and stable runnable pipeline. |
| `02_cure_prediction_module/` | Cavitation-led cure prediction and threshold selection. |
| `03_theoretical_phase_focus_validation/` | Theoretical phase and focal-plane validation. |
| `04_exit_field_diagnostics/` | Phase-board exit complex field diagnosis and repair validation. |
| `05_modulation_law_surrogate/` | Modulation-law dataset and surrogate model exploration. |
