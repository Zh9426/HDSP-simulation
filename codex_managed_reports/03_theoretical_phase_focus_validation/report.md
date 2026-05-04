# Theoretical Phase And Focus Validation

## Source Snapshot

- Latest source: `src_latest/`
- Source branch: `codex/phase-board-modulation-diagnosis`
- Main exploratory entry: `src_latest/IASAdebug0420.m`

## Included Files

- `IASAdebug0420.m`
- `compute_asm_focus_field.m`
- `project_phase_to_board.m`
- `error_diffuse_quantize_layers.m`

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

