# Cure Prediction Module

## Source Snapshot

- Stable source: `src_stable/`
- Source branch: `codex_managed`
- Integration anchor: `01_mainline_full_pipeline/src_stable/HDSPdebug.m`
- Tests: `src_stable/tests/`
- Runtime outputs: `outputs/`

## Included Files

- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_cure_feedback_terms.m`
- `compute_thermal_aux_increment.m`
- `evaluate_cure_prediction.m`
- `select_cure_threshold.m`
- `tests/`

## Output Contract

This work stream does not use a separate demo script as its authoritative
entry. The real stable implementation is the helper set called by
`01_mainline_full_pipeline/src_stable/HDSPdebug.m`.

When the mainline pipeline is run, the cure-related exported matrices and
metrics are written under `01_mainline_full_pipeline/outputs/`.

## Current Status

The current cure pathway is cavitation-dose-led, with thermal terms used as auxiliary or diagnostic support.

The practical chain is:

```text
pressure field -> cavitation activity/dose -> thermal auxiliary -> cure_score -> threshold scan -> IoU/Dice/over/under
```

## Stable Interpretation

The cure module is now mature enough to report independently from the acoustic field-generation problem. When field quality changes, the cure metrics should be interpreted after separating:

1. acoustic field quality;
2. focus-plane shift;
3. cure-threshold selection.

## Decision

Keep this module aligned to the real mainline implementation instead of a
standalone synthetic demo. Future changes should update both the helper files
and the tests in `src_stable/tests/`.
