# Current Integrated Status

Date: 2026-05-04

Branch: `codex_managed`

## High-Level Conclusion

The current branch should be treated as an integrated status branch for regular reporting and stable mainline work. Experimental outputs and model data stay local; reusable scripts and status notes are committed.

## Main Work Streams

| Stream | Status | Latest Decision |
|---|---|---|
| Main HDSP pipeline | Active in `HDSPdebug.m` | Preserve as current runnable mainline. |
| Cure prediction | Active | Current path uses cavitation-dose-led cure score with thermal terms as auxiliary/diagnostic support. |
| Focus validation | Diagnostic | The 16.00 mm design plane vs 18.79 mm best plane remains a separate focus-shift issue. |
| Exit-field analysis | Exploratory | Exit field cannot be treated as pure phase-only modulation. Field-level validation is required. |
| Modulation-law modeling | Paused for analysis | Local point models are insufficient; full-field U-Net improved but is not yet usable as an IASA compensator. |

## Latest Quantitative Anchors

- Main full-flow run previously showed best field distance `16.00 / 18.79 mm`, with target-field PCC around `0.6034` and cure IoU around `0.6597`.
- Corrected random-sampling point MLP reached only about `field R2 = 0.20`, exposing the old fixed-sampling result as leakage.
- Full-field U-Net using complex real/imag target reached about `R2 = 0.5397`, `phase_MAE = 0.7081 rad`, and `amp_R2 ~= 0`.
- `amp_only` U-Net reached about `amp_R2 = 0.3157`, showing amplitude is learnable but still weak.
- `phase_only` U-Net did not learn a useful phase predictor; `phase_MAE` stayed near random level.

## Immediate Recommendation

Pause model scaling. The next useful step is analysis, not more training:

1. Compare simple physics baselines such as `A = exp(-beta * thickness)` against learned amplitude.
2. Quantify per-case target distribution shift.
3. Recheck target definition: ratio field vs exit complex field vs correction map.
4. Only after that decide whether to integrate a surrogate into IASA/PANN.

