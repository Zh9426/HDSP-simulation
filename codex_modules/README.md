# Codex Modules

This directory is code-only. Runtime data, figures, MAT files, checkpoints, and sweep outputs should stay outside git.

## Layout

| Directory | Role |
|---|---|
| `00_parameters/` | Parameter definitions and defaults. |
| `01_targets/` | Target and validation-case definitions. |
| `02_phase_retrieval/` | IASA and Python/PANN phase-design implementations. |
| `03_phase_board/` | Phase-to-board mapping and layer quantization helpers. |
| `04_kwave_modeling/` | Full-flow k-Wave pipeline snapshots. |
| `05_cure_prediction/` | Cavitation-led cure models and validation scripts. |
| `06_metrics/` | Field and cure quality metrics. |
| `07_exit_field_diagnostics/` | Exit complex-field diagnosis and repair workflows. |
| `08_modulation_surrogate/` | Dataset generation and surrogate training code. |

## Running Profiles

Use `run_codex_module_pipeline.m` as the switchboard:

```matlab
run_codex_module_pipeline list
run_codex_module_pipeline mainline_v2_current_root
run_codex_module_pipeline phase_focus_v1_theoretical_iasa
run_codex_module_pipeline cure_v1_direct_phase
run_codex_module_pipeline exit_field_v1_repair
run_codex_module_pipeline modulation_dataset_v1
```

The current profile system loads one self-contained version directory at a time. This prevents helper-name collisions while preserving old runnable scripts. Later versions can replace large scripts with standard function interfaces so that parameter, target, phase, board, k-Wave, cure, and metric modules can be mixed inside one run without copying helper files.

## Version Notes

- `04_kwave_modeling/v1_mainline_report_snapshot/` is the mainline snapshot previously archived with the reports.
- `04_kwave_modeling/v2_mainline_current_root/` is the newer root-level code moved out of the repository root.
- `05_cure_prediction/v1_direct_phase_cavitation/` keeps the direct-phase cavitation workflow and its MATLAB unit tests.
- `08_modulation_surrogate/v1_dataset_and_models/` contains code only; generated datasets are intentionally excluded.
