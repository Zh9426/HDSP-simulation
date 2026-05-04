# Codex Managed Work Archive

This directory is organized as one folder per work stream. Each work folder contains:

- `report.md` - latest written status, conclusions, and next decision.
- `src_stable/` - stable source snapshot used by the current `codex_managed` branch, when available.
- `src_latest/` - latest exploratory source snapshot from the relevant research branch, when different from the stable version.
- `outputs/` - runtime-generated summaries, figures, and matrix data produced by the work stream's primary entry script.

Generated data, MAT files, figures, checkpoints, and local output directories remain intentionally excluded from git.

## Work Streams

| Directory | Purpose |
|---|---|
| `01_mainline_full_pipeline/` | Current HDSP mainline script and stable runnable pipeline. |
| `02_cure_prediction_module/` | Cavitation-led cure prediction and threshold selection. |
| `03_theoretical_phase_focus_validation/` | Theoretical phase and focal-plane validation. |
| `04_exit_field_diagnostics/` | Phase-board exit complex field diagnosis and repair validation. |
| `05_modulation_law_surrogate/` | Modulation-law dataset and surrogate model exploration. |
