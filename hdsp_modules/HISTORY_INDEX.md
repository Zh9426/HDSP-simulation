# Historical Source Index

This branch refactors major historical ideas into module functions. It does not
copy full historical scripts as runnable modules.

| Module area | Refactored version | Historical source |
| --- | --- | --- |
| Target | `kou_frame_0209` | `cc3dced` / early `HDSP_debug0209.m` square-ring target |
| Target | `A_letter_binary_0223` | `a4a3cd8` / `thickness_built.m` A-letter target |
| Target | `A_letter_edge_blur_0302` | `1225f33` / blurred A-letter target |
| Target | `grid_scaffold_circle_current` | cure-analysis validation target |
| Phase | `IASA_basic_0211` | `4269d1c` early IASA |
| Phase | `WIASA_weighted_0209` | early weighted weak-spot IASA behavior |
| Phase | `python_handoff_or_fallback_0315` | `1bddebd`, `79d204a` MATLAB/Python handoff boundary |
| Phase | `BIASA_board_constrained_0508` | `03dfe86`, `8414cd7` BIASA and board-constrained direction |
| Phase board | `continuous_late_round_0223` | early continuous phase-to-thickness late rounding |
| Phase board | `projector_error_diffusion_current` | current global phase-bias projection and error diffusion |
| Simulation | `asm_focus_scan` | common ASM focus validation extracted from multiple scripts |
| Cure | `thermal_arrhenius_dose_0318` | `2a953a3`, `82dd56b` Arrhenius thermal-dose direction |
| Cure | `cavitation_dose_led_score_0501` | `bdce8db`, `59097d9` cavitation-dose-led cure criterion |

Abandoned for this branch: phase-board modulation-law surrogate models and
training datasets.

