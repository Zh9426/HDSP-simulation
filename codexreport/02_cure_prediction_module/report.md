# Cure Prediction Module

## Source Snapshot

- Stable source: `../../codex_modules/05_cure_prediction/v1_direct_phase_cavitation/`
- Source branch: `codex/cure-analysis`
- Primary entry: `../../codex_modules/05_cure_prediction/v1_direct_phase_cavitation/IASAdebug0420_cure_validation.m`
- Auxiliary entry: `../../codex_modules/05_cure_prediction/v1_direct_phase_cavitation/run_cure_model_sanity_suite.m`
- Runtime outputs: generated locally and intentionally excluded from git

## Included Files

- `IASAdebug0420_cure_validation.m`
- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_cure_feedback_terms.m`
- `compute_thermal_aux_from_pressure_map.m`
- `compute_thermal_aux_increment.m`
- `default_cure_model_params.m`
- `evaluate_cure_prediction.m`
- `evaluate_cure_validation_cases.m`
- `build_hdsp_validation_target.m`
- `build_pressure_validation_cases.m`
- `run_cure_model_sanity_suite.m`
- `run_cure_prediction_demo.m`
- `select_cure_threshold.m`
- `select_cure_visualization_cases.m`
- `simulate_cure_from_pressure_map.m`
- `tests/`

## Output Contract

Running the module entry script writes local outputs with:

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

## Archive Gap

The historical local outputs contained the overview figure and MAT payload, but
do not include `summary.txt` or `summary.json`. The figure reports a stronger
direct-phase validation result than the mainline flow, but those metrics should
be exported as machine-readable files before they are used as thesis evidence.

## Decision

Keep the archive aligned to the real `codex/cure-analysis` workflow. Use
`run_cure_model_sanity_suite.m` for local helper checks, but treat
`IASAdebug0420_cure_validation.m` as the authoritative validation entry.
