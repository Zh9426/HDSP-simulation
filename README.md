# HDSP Modular Codebase

This clean branch contains code only. It is organized as a modular HDSP kernel
for later APP use: one public entry script calls parameter, target, phase,
phase-board, simulation, optional exit-diagnostic, optional cure, and metrics
modules.

Run from MATLAB:

```matlab
result = run_hdsp_module_pipeline();
result = run_hdsp_module_pipeline("current_pdms_cavitation");
result = run_hdsp_module_pipeline("a_letter_arrhenius", struct("enable_cure", false));
```

The abandoned phase-board modulation-law surrogate work is intentionally not
part of this branch.

