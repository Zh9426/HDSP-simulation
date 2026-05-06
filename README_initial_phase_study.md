# Initial Phase Study Branch

This branch is scoped to initial-phase calculation only. It compares three phase sources:

1. Pure Python continuous phase optimization.
2. Python initialization refined by continuous-phase IASA.
3. Pure IASA initialized from a random source phase.

The workflow stops at pressure-field analysis. It does not run curing, cavitation, thermal dose, thickness-board construction, or surrogate training.

## Entry Point

Run in MATLAB:

```matlab
run_initial_phase_study
```

The MATLAB entry script calls:

- `python_initial_phase_optimizer.py` for the pure Python initial phase.
- `run_iasa_phase_optimizer.m` for continuous IASA refinement.
- `run_kwave_pressure_scan.m` for homogeneous-water k-Wave pressure propagation.
- `calculate_pressure_metrics.m` for pressure-centered metrics.

## Outputs

Runtime outputs are written to `initial_phase_outputs/`. This directory is ignored by git. The expected output files are:

- `python_phase_input.mat`
- `python_phase_output.mat`
- `initial_phase_pressure_results.mat`
- `initial_phase_pressure_overview.png`
- `summary.txt`
- `summary.json`

Do not commit generated data or figures from this branch.
