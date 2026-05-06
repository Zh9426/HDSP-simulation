# Exit-Field Diagnostics

## Source Snapshot

- Latest source: `../../codex_modules/07_exit_field_diagnostics/v1_phase_board_repair/`
- Source branch: `codex/phase-board-modulation-diagnosis`
- Primary entry: `../../codex_modules/07_exit_field_diagnostics/v1_phase_board_repair/phase_board_exit_repair_validation.m`
- Runtime outputs: generated locally and intentionally excluded from git

## Included Files

- `phase_board_exit_repair_validation.m`
- `compare_phase_to_reference.m`
- `extract_local_exit_field.m`
- `make_idealized_exit_field.m`
- `validate_exit_complex_gpu.py`
- `compute_asm_focus_field.m`
- `project_phase_to_board.m`
- `error_diffuse_quantize_layers.m`
- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `evaluate_cure_prediction.m`

The module directory is intended to run without depending on `02_cure_prediction_module`
or the repository root being on the MATLAB path.

## Output Contract

Running the module entry script writes local outputs with:

- `summary.txt` and `summary.json` for exit-repair scalar diagnostics;
- `phase_board_exit_repair_results.mat` for thickness, layer map, exit complex
  field, repaired fields, local-exit diagnostics, focal field and cure result;
- `phase_board_exit_repair_overview.png`, `local_exit_diagnostic.png` and
  `exit_phase_probe_scan.png`.

## Current Status

This work stream tests whether the measured phase-board exit field can explain the observed target-plane degradation.

The main checks include:

1. measured exit phase plus theoretical amplitude;
2. same/opposite phase convention selection;
3. local exit extraction and compensation;
4. field-level validation rather than sample-only validation.

## Latest Conclusion

The exit field cannot be treated as pure phase-only modulation. Sample-point validation alone is not reliable; field-level validation is required.

## Decision

Keep this work stream exploratory. Promote scripts into the main branch only after the diagnostic workflow is stable and can be rerun without manual interpretation.
