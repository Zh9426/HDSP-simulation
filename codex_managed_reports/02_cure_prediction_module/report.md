# Cure Prediction Module

## Source Snapshot

- Stable source: `src_stable/`
- Source branch: `codex/cure-analysis`
- Primary entry: `src_stable/IASAdebug0420_cure_validation.m`
- Auxiliary entry: `src_stable/run_cure_model_sanity_suite.m`
- Runtime outputs: `outputs/`

## Included Files

- `IASAdebug0420_cure_validation.m`
- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_thermal_aux_from_pressure_map.m`
- `compute_thermal_aux_increment.m`
- `default_cure_model_params.m`
- `evaluate_cure_prediction.m`
- `evaluate_cure_validation_cases.m`
- `build_hdsp_validation_target.m`
- `build_pressure_validation_cases.m`
- `run_cure_model_sanity_suite.m`
- `select_cure_visualization_cases.m`
- `simulate_cure_from_pressure_map.m`

## Output Contract

Running `src_stable/IASAdebug0420_cure_validation.m` writes `outputs/` with:

- `python_iasa_cure_validation_overview.png`
- `python_iasa_cure_validation.mat`
- console summary for acoustic-field and cure-model metrics

The MAT file contains the target, phase map, k-Wave field result, scan records,
best cure case, cavitation model, and cure model parameters.

## Current Status

This work stream validates the cavitation-led cure logic on the direct
Python+IASA acoustic field, without introducing the physical thickness board.

The practical chain is:

```text
target -> Python+IASA phase -> direct-phase k-Wave field -> pressure scan/exposure scan -> cavitation cure score -> IoU/Dice
```

## Latest Conclusion

This module is not an abstract demo. The current stable validation path on this
branch is `IASAdebug0420_cure_validation.m`, and the report archive should
mirror that exact workflow.

## Decision

Keep the archive aligned to the real `codex/cure-analysis` workflow. Use
`run_cure_model_sanity_suite.m` for local helper checks, but treat
`IASAdebug0420_cure_validation.m` as the authoritative validation entry.
