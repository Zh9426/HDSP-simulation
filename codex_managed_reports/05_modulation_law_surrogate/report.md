# Modulation-Law Surrogate Exploration

## Source Snapshot

- Latest source: `src_latest/`
- Source branch: `codex/phase-board-modulation-diagnosis`

## Included Files

- `modulation_law_dataset_sweep.m`
- `export_exit_amp_surrogate_run.m`
- `train_exit_amp_surrogate.py`
- `train_exit_complex_gpu.py`
- `train_exit_complex_unet.py`
- `validate_exit_complex_gpu.py`
- `project_phase_to_board.m`
- `error_diffuse_quantize_layers.m`
- `compute_asm_focus_field.m`

`src_latest/` contains the MATLAB helpers needed by the sweep script, so the
surrogate work directory can be copied or run independently from the root
workspace.

## Current Status

This work stream explores whether a learned surrogate can predict phase-board exit complex modulation.

## Model Findings

| Attempt | Latest Result | Interpretation |
|---|---|---|
| Fixed-sampling point MLP | high apparent R2 | Invalid due sampling leakage. |
| Case-independent random point MLP | field R2 about `0.20` | Local point model is insufficient. |
| U-Net complex target | field R2 about `0.54`, phase_MAE about `0.71 rad` | Full-field context helps. |
| U-Net amp_phase target | amp_R2 improved, phase collapsed | Joint target is unstable. |
| U-Net amp_only target | amp_R2 about `0.32` | Amplitude has learnable structure but remains weak. |
| U-Net phase_only target | phase_MAE near random | Standalone phase target is not useful. |

## Latest Conclusion

The useful result is not a ready correction model, but a model-selection conclusion:

```text
local point mapping is not enough;
full-field context matters;
amplitude and phase should not be forced into a naive joint target.
```

## Decision

Pause model scaling. Before further training, run physics and data diagnostics:

1. thickness-only amplitude baseline;
2. gradient/edge amplitude baseline;
3. per-case distribution shift analysis;
4. target-definition review: ratio field vs absolute exit field vs correction map.
