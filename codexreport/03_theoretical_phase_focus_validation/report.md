# Theoretical Phase And Focus Validation

## Source Snapshot

- Latest source: `../../codex_modules/02_phase_retrieval/v1_theoretical_iasa_focus/`
- Source branch: `codex/phase-board-modulation-diagnosis`
- Main exploratory entry: `../../codex_modules/02_phase_retrieval/v1_theoretical_iasa_focus/IASAdebug0420.m`
- Runtime outputs: generated locally and intentionally excluded from git

## Included Files

- `IASAdebug0420.m`
- `compute_asm_focus_field.m`
- `project_phase_to_board.m`
- `error_diffuse_quantize_layers.m`

## Output Contract

Running the module entry script writes local outputs with:

- `summary.txt` and `summary.json` for ASM/k-Wave scalar metrics;
- `phase_focus_validation_results.mat` for target, phase maps, layer maps,
  ASM fields and direct-phase k-Wave results;
- `phase_validation_overview.png` and
  `phase_validation_centerline_metrics.png`.

## Current Status

This work stream isolates the question of whether the design phase and focal plane are correct before blaming cure prediction or exit-field modulation.

The key distinction remains:

```text
16 mm design propagation distance != phase-board exit diagnostic plane
```

The focus validation should report:

- design z;
- best z;
- z-shift;
- scan radius;
- edge margin;
- whether the optimum is clipped by the scan boundary.

## Latest Conclusion

The previously observed `16.00 / 18.79 mm` gap should be handled as a real focus-shift diagnosis, not folded into cure threshold tuning.

## Decision

Keep this as a diagnostic work stream. It should not be merged into cure-model logic.
