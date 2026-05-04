# Exit-Field Analysis Attempts

## Problem

The phase board cannot be treated as a pure phase-only plate. Exit amplitude and phase are both modulated by the physical board.

## Main Attempts

1. Reconstruct idealized field from measured exit phase plus theoretical amplitude.
2. Compare measured exit phase against theoretical/design phase.
3. Scan exit reconstruction sign conventions (`same` vs `opposite`).
4. Build sample-level and field-level validation for exit complex ratio.

## Important Findings

- Same/opposite sign convention matters substantially.
- Sample-level validation can be misleading when sampling coordinates leak across train and holdout cases.
- Field-level validation exposed that local point models do not generalize across the full aperture.

## Branch Origin

The newest exit-field scripts were explored on `codex/phase-board-modulation-diagnosis`, including:

- `phase_board_exit_repair_validation.m`
- `compare_phase_to_reference.m`
- `extract_local_exit_field.m`
- `make_idealized_exit_field.m`
- `validate_exit_complex_gpu.py`

These should be imported into `codex_managed` only when the branch is ready to promote a stable diagnostic workflow.

