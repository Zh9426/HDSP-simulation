# Modulation-Law Model Exploration

## Goal

Learn a surrogate for phase-board exit complex modulation so it can eventually inform IASA/PANN or phase-board construction.

## Explored Models

| Model | Result | Interpretation |
|---|---|---|
| Random forest / PCA sample model | early positive but limited | Useful as baseline only. |
| Point MLP with fixed sampling | apparently high R2 | Invalid due sampling leakage. |
| Point MLP with case-independent random sampling | field R2 about `0.20` | Local point features are insufficient. |
| Full-field U-Net, complex target | R2 about `0.54`, phase_MAE about `0.71 rad` | Full spatial context helps. |
| Full-field U-Net, amp_phase target | amp_R2 improved but phase collapsed | Joint amplitude/phase target is unstable. |
| Full-field U-Net, amp_only | amp_R2 about `0.32` | Amplitude has learnable structure, but still weak. |
| Full-field U-Net, phase_only | near random phase | Phase-only target is not currently useful. |

## Current Conclusion

The most defensible conclusion is not that the surrogate is ready, but that the pure local mapping assumption is false. Exit modulation appears to include nonlocal field effects.

## Next Analysis Before More Training

1. Fit simple amplitude baselines: thickness-only, gradient-only, and thickness-plus-gradient.
2. Compare those baselines against `amp_only` U-Net.
3. Quantify per-case amplitude and phase distribution shift.
4. Reconsider target definition: absolute exit complex field, ratio field, or correction field.
5. Decide whether new data sweeps should vary physical parameters or geometry parameters first.

## Related Scripts From Exploration Branch

Explored on `codex/phase-board-modulation-diagnosis`:

- `modulation_law_dataset_sweep.m`
- `train_exit_complex_gpu.py`
- `train_exit_complex_unet.py`
- `validate_exit_complex_gpu.py`

Promotion to `codex_managed` should happen after the analysis target is clarified.

