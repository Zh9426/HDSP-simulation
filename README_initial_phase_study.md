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

The MATLAB entry script writes `C:\Users\Zh89\Desktop\transport\target_for_python.mat`, prints the Python command, and pauses. Run the printed PANN command manually in PowerShell, then return to MATLAB and press any key to continue.

The workflow uses:

- `PANN_Holography.py` for the pure Python initial phase. This keeps the established transport-file workflow.
- `run_iasa_phase_optimizer.m` for continuous IASA refinement.
- `run_kwave_pressure_scan.m` for homogeneous-water k-Wave pressure propagation.
- `calculate_pressure_metrics.m` for pressure-centered metrics.

## Outputs

Runtime outputs are written to `initial_phase_outputs/`. This directory is ignored by git. The expected output files are:

- `initial_phase_pressure_results.mat`
- `initial_phase_pressure_overview.png`
- `initial_phase_pressure_metrics.png`
- `pann_phase_output_snapshot.mat`
- `pann_training_history.csv`
- `pann_training_summary.json`
- `pann_training_metrics.png`
- `summary.txt`
- `summary.json`

The Python transport files are outside the repo:

- `C:\Users\Zh89\Desktop\transport\target_for_python.mat`
- `C:\Users\Zh89\Desktop\transport\dl_phase_init.mat`

Do not commit generated data or figures from this branch.

When asking Codex to evaluate a run, point it at `initial_phase_outputs/`. The analysis should combine these output files with the current git diff/log to decide the next phase-optimizer iteration.
