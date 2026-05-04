# Mainline Pipeline Notes

Primary file: `HDSPdebug.m`

## Current Role

`HDSPdebug.m` remains the stable main workflow for design, k-Wave propagation, field assessment, and cure prediction.

## Important Supporting Files

- `PANN_Holography.py` - Python-side initial phase / holography support.
- `project_phase_to_board.m` - phase-to-layer projection.
- `error_diffuse_quantize_layers.m` - quantized layer error diffusion.
- `compute_asm_focus_field.m` - ASM field/focus helper.
- `build_exit_plane_analysis_defaults.m` - exit-plane analysis defaults.

## Reporting Focus

For regular reports, mainline status should include:

- design plane and best plane distance;
- k-Wave vs ASM field metrics;
- cure selection metrics;
- any parameter changes affecting physical interpretation.

## Current Caution

Do not mix exploratory surrogate results into `HDSPdebug.m` until field-level validation is convincing. The surrogate work is still research-side evidence, not a stable mainline correction.

