# Mainline Full Pipeline

## Source Snapshot

- Stable source: `../../codex_modules/04_kwave_simulation/KWAVE_full_pipeline_report_snapshot/`
- Current root snapshot: `../../codex_modules/04_kwave_simulation/KWAVE_full_pipeline_current/`
- Source branch: `codex_managed`
- Primary entry: `../../codex_modules/04_kwave_simulation/KWAVE_full_pipeline_report_snapshot/HDSPdebug.m`
- Runtime outputs: generated locally and intentionally excluded from git

## Included Files

- `HDSPdebug.m`
- `PANN_Holography.py`
- `build_exit_plane_analysis_defaults.m`
- `compute_asm_focus_field.m`
- `compute_cavitation_activity_map.m`
- `compute_cavitation_cure_score.m`
- `compute_cavitation_dose_rate.m`
- `compute_cure_feedback_terms.m`
- `compute_thermal_aux_increment.m`
- `error_diffuse_quantize_layers.m`
- `evaluate_cure_prediction.m`
- `export_exit_amp_surrogate_run.m`
- `project_phase_to_board.m`
- `select_cure_threshold.m`

The module directory is intended to be runnable as a standalone mainline snapshot.
It duplicates the cure and export helpers used by `HDSPdebug.m` instead of
requiring sibling report directories to be added to the MATLAB path.

## Output Contract

Running the module entry script writes local outputs with:

- `summary.txt` and `summary.json` for printed scalar results;
- `mainline_full_pipeline_results.mat` for target, thickness, exit complex
  field, focal pressure, cure score, cured mask, z-scan records and selected
  scan record;
- `figure_*.png` snapshots of the generated MATLAB figures.

## Current Status

This is the stable main pipeline for periodic reporting. It remains the branch's authoritative workflow for:

1. target pattern and phase initialization;
2. phase-board construction;
3. k-Wave acoustic propagation;
4. field quality analysis;
5. cure prediction and final quality reporting.

## Latest Known Result Anchor

The current full-flow reference reported a design/best field distance gap around:

```text
16.00 / 18.79 mm
```

with a nontrivial focus shift that should be treated separately from cure-model tuning.

## Decision

Do not inject surrogate-model corrections into this pipeline yet. Keep `HDSPdebug.m` stable until exit-field surrogate validation is strong enough for closed-loop correction.
