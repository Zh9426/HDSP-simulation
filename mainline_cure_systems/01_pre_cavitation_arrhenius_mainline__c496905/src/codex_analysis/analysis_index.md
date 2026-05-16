# Codex Analysis Index

This directory is generated sidecar context for Codex-driven HDSP iteration.
It does not modify the main MATLAB/Python simulation logic.

## Files

- `project_manifest.json`: static inventory, entrypoints, parameters, and pipeline summary.
- `pipeline_map.json`: compact stage map for direct code analysis.
- `task_alignment.json`: task-objective coverage and gaps.
- `optimization_backlog.json`: prioritized next work tied to gaps.
- `metric_profiles.json`: scoring profiles for comparing future run JSON files.

## Runtime Loop

- `HDSPdebug.m` writes `codex_runs/hdsp_latest_run.json` and timestamped archives after metric calculation, then automatically generates proposal-only analysis at `codex_analysis/latest_run_analysis.json`.
- `PANN_Holography.py` writes `codex_runs/pann_latest_run.json` and timestamped archives after phase initialization export, then automatically generates proposal-only analysis at `codex_analysis/pann_latest_run_analysis.json`.
- `tools/analyze_codex_run.py` can be rerun manually against any saved run JSON. It only proposes changes; it does not edit scripts.

```powershell
python tools/analyze_codex_run.py --run-json codex_runs/hdsp_latest_run.json
```

## Current Pipeline

target -> Python phase initialization -> MATLAB IASA refinement -> discrete thickness board -> k-Wave propagation -> exit/thermal/curing metrics

## Task Alignment

- `objective_full_chain`: covered (1.000) - Run a full HDSP simulation chain
- `objective_metrics`: covered (1.000) - Expose quantitative evaluation metrics
- `objective_domain_gap`: covered (1.000) - Diagnose ASM or design-model to k-Wave domain gap
- `objective_curing`: covered (0.800) - Connect acoustic pressure to curing result
- `objective_future_cavitation`: planned_not_implemented (0.500) - Prepare for cavitation-aware HDSP curing model

## Gaps

- `gap_machine_readable_run_outputs` [high]: Add a non-invasive MATLAB result export block after reporting, guarded by a flag so the main logic remains unchanged.
- `gap_effective_transmission_model` [high]: Use current exit-plane diagnostics and surrogate data to map thickness, local gradient, and edge distance to exit amplitude/phase correction.
- `gap_cavitation_branch_not_dynamic` [medium]: Prototype a sidecar cavitation score from p_3d_scaled, then compare pure thermal versus thermal+cavitation metrics.
- `gap_metric_decision_rule` [medium]: Create a score profile that prioritizes IoU/Dice and penalizes over-cure for curing prediction, while keeping ASM/k-Wave mismatch metrics for diagnosis.

## Suggested Iteration Backlog

- P1 `opt_001_run_result_json`: Make each simulation result directly readable by Codex without scraping console output.
- P2 `opt_002_metric_score_profile`: Turn many metrics into explicit optimization targets for task-aligned iteration.
- P3 `opt_003_effective_transmission_dataset`: Attack the current highest-value domain gap without changing the main algorithm first.
- P4 `opt_004_cavitation_sidecar_score`: Prepare the future cavitation module as an analyzable branch before integrating it into curing.

## Regenerate

```powershell
python tools/generate_codex_context.py
```
