# Cure Prediction Module Status

## Current Model

The current branch uses a cavitation-dose-led cure score, with thermal terms retained as auxiliary/diagnostic terms rather than the sole cure criterion.

## Active Files

- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_thermal_aux_increment.m`
- `compute_cure_feedback_terms.m`
- `evaluate_cure_prediction.m`
- `select_cure_threshold.m`

## Current Interpretation

The cure module should be described independently from the acoustic field-generation problem:

`p -> cavitation activity/dose + thermal auxiliary -> cure_score -> threshold selection -> IoU/Dice/over/under`

## Latest Stable Direction

Keep IoU/Dice and over/under-cure metrics as the reporting basis. Avoid changing the top-level selection metric while acoustic field modeling remains under investigation.

