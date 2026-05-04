# Cure Prediction Module

## Source Snapshot

- Stable source: `src_stable/`
- Source branch: `codex_managed`
- Tests: `src_stable/tests/`

## Included Files

- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_cure_feedback_terms.m`
- `compute_thermal_aux_increment.m`
- `evaluate_cure_prediction.m`
- `select_cure_threshold.m`

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

Keep this module stable while acoustic field correction remains exploratory. Future changes should include tests in `src_stable/tests/`.

