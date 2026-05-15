# HDSP Modules

## Contract

Every module receives and returns one `ctx` struct. The main entrypoint is
`run_hdsp_module_pipeline.m`; module files are tools only.

Required stages:

| Stage | Required output fields |
| --- | --- |
| parameters | `ctx.params` |
| target | `ctx.target.amp`, `ctx.target.mask`, `ctx.target.source_mask` |
| phase | `ctx.phase.phase_map`, `ctx.phase.source_mask` |
| phase_board | `ctx.board.actual_phase`, `ctx.board.thickness_map`, `ctx.board.layer_map` |
| simulation | `ctx.field.focus_amp`, `ctx.field.exit_amp`, `ctx.field.status` |
| metrics | `ctx.metrics` |

Optional stages:

| Stage | Disabled behavior |
| --- | --- |
| exit_diagnostic | returns `ctx.exit_diagnostic.enabled = false` |
| cure | returns `ctx.cure.enabled = false`, empty masks, and NaN scores |

## Compatibility Rules

- All distances are meters, pressure is Pa, time is seconds, frequency is Hz.
- All 2D maps must be `Nx` by `Ny`; modules resize only through explicit target
  builders, not silently inside later stages.
- Missing optional data must be represented by empty arrays or `NaN`, not by
  missing fields.
- Historical code is refactored by function, not copied as full scripts.
- Runtime data must be written outside `hdsp_modules/` if a future module needs
  files.

