# Mainline Full Pipeline

## Source Snapshot

- Stable source: `src_stable/`
- Source branch: `codex_managed`
- Primary entry: `src_stable/HDSPdebug.m`

## Included Files

- `HDSPdebug.m`
- `PANN_Holography.py`
- `build_exit_plane_analysis_defaults.m`
- `compute_asm_focus_field.m`
- `error_diffuse_quantize_layers.m`
- `project_phase_to_board.m`

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

