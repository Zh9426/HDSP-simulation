# Codex Modules

This directory is code-only. Runtime data, figures, MAT files, checkpoints, and sweep outputs should stay outside git.

## Layout

| Directory | Role |
|---|---|
| `00_parameters/` | Parameter definitions and defaults. |
| `01_target_pattern/` | Target pattern definitions, such as `A_letter` or `grid_scaffold_circle_current`. |
| `02_initial_phase/` | Initial phase and phase-refinement schemes, such as `WIASA`, `IASA_python_1`, or `PANN_python_quantized_initial`. |
| `03_phase_board/` | Phase-to-board mapping and layer quantization helpers. |
| `04_kwave_simulation/` | Full-flow k-Wave simulation entries. |
| `05_cure_prediction/` | Cavitation-led cure models and validation scripts. |
| `06_result_metrics/` | Field and cure quality metrics. |
| `07_exit_field_diagnosis/` | Exit complex-field diagnosis and repair workflows. |
| `08_surrogate_model/` | Dataset generation and surrogate training code. |

## Running Profiles

Use `run_codex_module_pipeline.m` as the switchboard:

```matlab
run_codex_module_pipeline list
run_codex_module_pipeline KWAVE_full_pipeline_current
run_codex_module_pipeline IASA_python_1_focus_check
run_codex_module_pipeline cavitation_V1_direct_phase_threshold
run_codex_module_pipeline exit_complex_repair_V1
run_codex_module_pipeline exit_field_UNet_dataset_V1
```

The current profile system loads one self-contained version directory at a time. This prevents helper-name collisions while preserving old runnable scripts. Later versions can replace large scripts with standard function interfaces so that parameter, target, phase, board, k-Wave, cure, and metric modules can be mixed inside one run without copying helper files.

## Version Notes

- `01_target_pattern/grid_scaffold_circle_current/` is the current circular grid scaffold target. Add later targets as names such as `A_letter` or `Kou_frame`.
- `02_initial_phase/IASA_python_1_focus_check/` keeps the Python initial phase plus IASA focus-check workflow.
- `02_initial_phase/PANN_python_quantized_initial/` keeps the Python/PANN quantized initial-phase optimizer.
- `04_kwave_simulation/KWAVE_full_pipeline_current/` is the current full k-Wave workflow moved out of the repository root.
- `05_cure_prediction/cavitation/V1_direct_phase_threshold/` keeps the direct-phase cavitation workflow and MATLAB unit tests.
- `07_exit_field_diagnosis/exit_complex_repair/V1_phase_board_repair/` keeps the current exit complex-field repair workflow.
- `08_surrogate_model/exit_field_UNet/V1_dataset_and_train/` contains code only; generated datasets are intentionally excluded.
