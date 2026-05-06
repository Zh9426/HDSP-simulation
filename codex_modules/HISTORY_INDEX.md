# Historical Module Index

This index records historical code versions exported from Git history. Files are kept as code-only snapshots: no MAT, image, dataset, checkpoint, or runtime output is stored here.

## 01 Target Pattern

| Folder | Source | Meaning |
|---|---|---|
| `grid_scaffold_circle_current/` | current organized code | Current circular grid scaffold target. |
| `A_letter_edge_blur_0302/` | `1225f33` | A-letter target definition with Gaussian edge blur / softening in the 0302-era main script. |

Later target copies can be added beside these with direct names such as `A_letter`, `Kou_frame`, or `grid_scaffold_circle_2x2_pool`.

## 02 Initial Phase

| Folder | Source | Meaning |
|---|---|---|
| `IASA_0211_basic/` | `4269d1c` | Early padded IASA implementation refactored into `compute_initial_phase_IASA_0211`. |
| `IASA_apod_unwrap_impedance_0223/` | `a67d2a5` | IASA-era script with amplitude compensation, apodization, phase unwrapping, and impedance matching toggles. |
| `IASA_python_1_focus_check/` | current organized code | Python initial phase plus IASA refinement used for focus validation. |
| `PANN_python_quantized_initial/` | current organized code | Current PANN/Python quantized initial phase optimizer. |
| `PANN_python_discrete_grid_loss/` | `93f87c1` | Python PANN loss update with discrete-grid constraints. |
| `GD_Holo_v5_physics_gradient/` | `babcb7c` | Pure physics-gradient GD-Holo v5 style phase optimization snapshot. |

## 03 Phase Board

| Folder | Source | Meaning |
|---|---|---|
| `thickness_built_first/` | `7b6f1de` | First tracked thickness builder. |
| `thickness_built_0203_2/` | `a98c0ce` | 0203.2 thickness builder snapshot. |
| `thickness_built_latest_before_projector/` | `a4a3cd8` | Later standalone thickness builder before the current projector helper style. |
| `phase_to_layers_inside_IASA_0223/` | `dbe202b` | Main script version that moved thickness discretization inside IASA. |
| `phase_to_layers_error_diffusion/` | current organized code | Current phase-to-layer mapping with error diffusion. |

## 04 k-Wave Simulation

| Folder | Source | Meaning |
|---|---|---|
| `HDSP_0209_early/` | `cc3dced` | Early HDSP 0209-era simulation script. |
| `KWAVE_full_pipeline_report_snapshot/` | report snapshot | Full pipeline archived with the report. |
| `KWAVE_full_pipeline_current/` | current organized code | Current full k-Wave workflow moved out of the repository root. |

## 05 Cure Prediction

| Folder | Source | Meaning |
|---|---|---|
| `thermal_Arrhenius/V1_tempdebug_2MPa_024s/` | `82dd56b` | Arrhenius thermal cure snapshot with stable 2 MPa / 0.24 s setting noted in commit history. |
| `cavitation/V0_trigger_activity_map/` | `3f84a40` | Trigger-led cavitation activity-map model, refactored to keep only `compute_cavitation_activity_map`. |
| `cavitation/V1_direct_phase_threshold/` | current organized code | Direct-phase cavitation threshold validation module. |
| `cavitation/V2_cloud_consistency_dose/` | `35df2a6` | Cavitation cloud consistency dose-rate model. |
| `cavitation/V3_dose_led_score/` | `bdce8db` | Cavitation dose-led cure score model. |
| `cure_system_profiles/V1_three_material_systems/` | `5e2692a` | Three material-system cure profile model. |
| `sonoink_Kuang_2024/V1_recalibrated/` | `1f45e74` | Sonoink model recalibrated against the Kuang paper path. |

## 07 Exit Field Diagnosis

| Folder | Source | Meaning |
|---|---|---|
| `phase_board_modulation_baseline/` | `fafc49a` | Baseline phase-board modulation diagnostic script. |
| `exit_complex_repair/V0_idealized_reconstruction/` | `d9114ea` | Idealized exit-field reconstruction workflow. |
| `exit_complex_repair/V1_phase_board_repair/` | current organized code | Current phase-board exit complex-field repair workflow. |
| `exit_complex_repair/V2_local_exit_surface/` | `1ec4edb` | Local exit-surface extraction diagnostic. |
| `exit_complex_repair/V3_diagnostic_phase_convention/` | `eb29a44` | Diagnostic phase-convention repair version. |

## 08 Surrogate Model

| Folder | Source | Meaning |
|---|---|---|
| `exit_field_point_MLP/V0_dataset_sweep/` | `2f21510` | Initial modulation-law dataset sweep and point MLP training code. |
| `exit_field_point_MLP/V1_complex_ratio_train/` | `25a5973` | Point model training for exit complex-field modulation ratio. |
| `exit_field_UNet/V0_complex_field/` | `051b534` | First full-field complex U-Net model. |
| `exit_field_UNet/V1_dataset_and_train/` | current organized code | Current U-Net dataset and training code. |
| `exit_field_UNet/V2_amp_priority_target/` | `61f3b9e` | Amplitude-priority full-field training target. |
| `exit_field_UNet/V3_split_amp_phase_target/` | `f292fcf` | Split amplitude and phase full-field training target. |

## Naming Rule

Use direct names that answer: what module, what method, and what version. Examples:

- `01_target_pattern/A_letter`
- `01_target_pattern/Kou_frame`
- `02_initial_phase/WIASA`
- `02_initial_phase/IASA_python_2`
- `05_cure_prediction/cavitation/V4_RP_bubble`
- `08_surrogate_model/exit_field_FNO/V1_complex_field`
