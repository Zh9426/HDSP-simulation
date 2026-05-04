# Exit-Field Diagnostics

## Source Snapshot

- Latest source: `src_latest/`
- Source branch: `codex/phase-board-modulation-diagnosis`

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

`src_latest/` is intended to run without depending on `02_cure_prediction_module`
or the repository root being on the MATLAB path.

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
