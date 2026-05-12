# Codex Managed Work Archive

This directory is organized as one folder per work stream. Each work folder contains:

- `report.md` - latest written status, conclusions, and next decision.
- `src_stable/` - stable source snapshot used by the current `codex_managed` branch, when available.
- `src_latest/` - latest exploratory source snapshot from the relevant research branch, when different from the stable version.
- `outputs/` - local runtime-generated summaries, figures, and matrix data. The directory stays in git only through `.gitkeep`; the data files inside do not.

`codex_managed_reports/*/outputs/` is a local-only output area and should not be pushed to the remote.
`local_outputs/` is the dedicated ignored scratch area for branch-local runs that should not enter git.
Root-level experiment outputs, temporary datasets, checkpoints, and other ad hoc local output directories remain excluded.

## Output Rules

1. Workstream outputs go to `codex_managed_reports/<work>/outputs/`, but only `.gitkeep` remains tracked there.
2. Branch-global scratch data goes to `local_outputs/<branch-name>/` and is intentionally ignored.
3. Do not create new root-level `*_outputs/` folders for preserved results. Those are treated as disposable local scratch.
4. Run `tools/ensure_report_output_layout.ps1` after adding a new work stream so the local-only `outputs/` folder and `.gitkeep` anchor exist immediately.

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
