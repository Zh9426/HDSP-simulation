# A Letter IASA 0211 Smoke

This folder demonstrates the intended callable-module pattern:

1. Build a target pattern with `build_target_A_letter_edge_blur_0302`.
2. Pass only the target image and parameter struct into
   `compute_initial_phase_IASA_0211`.
3. Keep simulation, phase-board, cure, and metrics out of this smoke example.

Run through the switchboard:

```matlab
run_codex_module_pipeline A_letter_IASA_0211_smoke
```
