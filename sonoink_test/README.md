# Sonoink Test Workspace

This folder contains the dedicated full-flow validation entry for cure system #3
(`sonoink_self_enhancing`).

Entry script:
- `HDSP_sonoink_fullflow_validation.m`

Local phase helpers:
- `project_phase_to_board.m`
- `error_diffuse_quantize_layers.m`
- `compute_asm_focus_field.m`

Default workflow:
- Build the same scaffold target used by the HDSP workflow.
- Export `target_for_python.mat` for the Python initial phase step.
- Load `dl_phase_init.mat`.
- Run Python-initialized IASA.
- Build the phase board and propagate through board + water-rich sonoink medium.
- Apply the `sonoink_self_enhancing` cure system profile to the simulated focal pressure.
- Export `outputs/sonoink_fullflow_overview.png` and `outputs/sonoink_fullflow_validation.mat`.

External requirements:
- k-Wave must still be available on the MATLAB path for full simulation.
- The Python phase-generation step must still write `dl_phase_init.mat`.

Fast structural check:
```matlab
result = HDSP_sonoink_fullflow_validation('dry_run', true);
```

Full run:
```matlab
result = HDSP_sonoink_fullflow_validation();
```
