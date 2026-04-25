"""Generate machine-readable project context for Codex-guided HDSP iteration.

This tool is intentionally sidecar-only. It reads the current project files and
writes analysis artifacts under codex_analysis/ without changing the MATLAB or
Python simulation path.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1.0"
OUTPUT_DIR = "codex_analysis"
EXCLUDED_DIRS = {
    ".git",
    "__pycache__",
    "tmp",
    "tmp_surrogate_outputs",
    "tmp_surrogate_outputs_fast",
    "tmp_surrogate_outputs_v2",
    "tmp_surrogate_smoke",
    "codex_analysis",
}
SOURCE_SUFFIXES = {".m", ".py", ".ps1", ".md", ".txt"}
MAIN_SCRIPT = "HDSPdebug.m"
PYTHON_OPTIMIZER = "PANN_Holography.py"


TASK_OBJECTIVES = [
    {
        "id": "objective_full_chain",
        "title": "Run a full HDSP simulation chain",
        "expected_evidence": [
            "imag_target",
            "PANN_Holography.py",
            "project_phase_to_board",
            "kWaveGrid",
            "Arrhenius",
        ],
    },
    {
        "id": "objective_metrics",
        "title": "Expose quantitative evaluation metrics",
        "expected_evidence": [
            "PCC",
            "SSIM",
            "NMSE",
            "EE",
            "IoU",
            "Dice",
            "over_cure_ratio",
            "under_cure_ratio",
        ],
    },
    {
        "id": "objective_domain_gap",
        "title": "Diagnose ASM or design-model to k-Wave domain gap",
        "expected_evidence": [
            "Python ASM",
            "IASA ASM",
            "k-Wave Focal",
            "Exit-field ASM",
        ],
    },
    {
        "id": "objective_curing",
        "title": "Connect acoustic pressure to curing result",
        "expected_evidence": [
            "Arrhenius",
            "Omega",
            "temperature",
            "IoU",
            "Dice",
        ],
    },
    {
        "id": "objective_future_cavitation",
        "title": "Prepare for cavitation-aware HDSP curing model",
        "expected_evidence": [
            "cavitation",
            "sonochemical",
            "2 MPa",
            "threshold",
        ],
    },
]


PIPELINE_PATTERNS = [
    ("target_definition", "Target pattern and design precompensation", ["imag_target", "imag_target_design"]),
    ("python_optimizer", "Python PAPO or PANN phase initialization", ["PANN_Holography.py", "dl_phase_init.mat"]),
    ("iasa_refinement", "MATLAB IASA refinement on projected board phase", ["IASA", "project_phase_to_board"]),
    ("thickness_quantization", "Discrete layer and thickness construction", ["net_num_board", "thickness_map"]),
    ("kwave_forward", "k-Wave 3D propagation through discrete board", ["kWaveGrid", "kspaceFirstOrder3D"]),
    ("exit_plane_diagnosis", "Exit-plane ASM and k-Wave domain-gap diagnosis", ["Exit-field", "board_exit"]),
    ("thermal_curing", "Thermal diffusion and Arrhenius curing prediction", ["Arrhenius", "Omega", "IoU"]),
    ("reporting", "Metric reporting and visual diagnostics", ["PCC", "SSIM", "NMSE", "Dice"]),
]


def read_text(path: Path) -> str:
    for encoding in ("utf-8", "utf-8-sig", "gb18030", "latin-1"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    return path.read_text(errors="replace")


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def iter_project_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in EXCLUDED_DIRS for part in path.relative_to(root).parts):
            continue
        if path.suffix.lower() in SOURCE_SUFFIXES or path.name in {MAIN_SCRIPT, PYTHON_OPTIMIZER}:
            files.append(path)
    return sorted(files, key=lambda item: rel(item, root).lower())


def classify_file(path: Path, root: Path) -> str:
    relative = rel(path, root)
    suffix = path.suffix.lower()
    if relative == MAIN_SCRIPT:
        return "matlab_main"
    if suffix == ".m":
        return "matlab_helper"
    if relative == PYTHON_OPTIMIZER:
        return "python_phase_optimizer"
    if suffix == ".py":
        return "python_tool_or_experiment"
    if suffix in {".md", ".txt"}:
        return "document_or_extracted_text"
    if suffix == ".ps1":
        return "powershell_tool"
    return "other"


def is_analysis_subject(path: Path, root: Path) -> bool:
    parts = path.relative_to(root).parts
    if parts and parts[0] in {"tools", "tests"}:
        return False
    return path.suffix.lower() in {".m", ".py", ".md", ".txt"}


def summarize_files(root: Path) -> dict[str, Any]:
    by_path: dict[str, Any] = {}
    by_role: dict[str, list[str]] = {}
    for path in iter_project_files(root):
        text = read_text(path)
        relative = rel(path, root)
        role = classify_file(path, root)
        by_path[relative] = {
            "role": role,
            "suffix": path.suffix,
            "bytes": path.stat().st_size,
            "line_count": text.count("\n") + (1 if text else 0),
            "last_modified": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(),
        }
        by_role.setdefault(role, []).append(relative)
    return {"by_path": by_path, "by_role": by_role}


def find_line_numbers(text: str, patterns: list[str]) -> dict[str, list[int]]:
    lines = text.splitlines()
    result: dict[str, list[int]] = {}
    for pattern in patterns:
        hits = [index + 1 for index, line in enumerate(lines) if pattern.lower() in line.lower()]
        if hits:
            result[pattern] = hits[:20]
    return result


def parse_matlab_sections(text: str) -> list[dict[str, Any]]:
    lines = text.splitlines()
    sections: list[dict[str, Any]] = []
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("%%"):
            starts.append((index, stripped.lstrip("%").strip()))
    for pos, (start, title) in enumerate(starts):
        end = starts[pos + 1][0] - 1 if pos + 1 < len(starts) else len(lines)
        sections.append({"start": start, "end": end, "title": title})
    return sections


def extract_assignments(text: str, names: list[str]) -> dict[str, Any]:
    assignments: dict[str, Any] = {}
    for name in names:
        match = re.search(rf"^\s*{re.escape(name)}\s*=\s*([^;\n]+)", text, flags=re.MULTILINE)
        if match:
            assignments[name] = match.group(1).strip().strip("'")
    return assignments


def summarize_entrypoints(root: Path) -> dict[str, Any]:
    main_path = root / MAIN_SCRIPT
    optimizer_path = root / PYTHON_OPTIMIZER
    main_text = read_text(main_path) if main_path.exists() else ""
    optimizer_text = read_text(optimizer_path) if optimizer_path.exists() else ""

    return {
        "matlab_main": MAIN_SCRIPT if main_path.exists() else None,
        "python_phase_optimizer": PYTHON_OPTIMIZER if optimizer_path.exists() else None,
        "matlab_main_sections": parse_matlab_sections(main_text),
        "important_parameters": extract_assignments(
            main_text,
            [
                "Nx",
                "Lx",
                "z_target_dist",
                "f0",
                "phase_refine_mode",
                "iasa_epoch",
                "pdms_thickness",
                "cavitation_limit",
            ],
        ),
        "python_optimizer_parameters": extract_assignments(
            optimizer_text,
            [
                "transport_dir",
                "epochs",
                "pad_factor",
                "min_base_layers",
            ],
        ),
    }


def build_pipeline(root: Path) -> dict[str, Any]:
    searchable = "\n".join(read_text(path) for path in iter_project_files(root) if is_analysis_subject(path, root))
    stages: list[dict[str, Any]] = []
    for stage_id, title, markers in PIPELINE_PATTERNS:
        hits = {marker: searchable.lower().count(marker.lower()) for marker in markers}
        stages.append(
            {
                "id": stage_id,
                "title": title,
                "status": "present" if any(count > 0 for count in hits.values()) else "not_detected",
                "evidence_markers": hits,
            }
        )
    return {
        "summary": "target -> Python phase initialization -> MATLAB IASA refinement -> discrete thickness board -> k-Wave propagation -> exit/thermal/curing metrics",
        "stages": stages,
    }


def build_task_alignment(root: Path) -> dict[str, Any]:
    files = iter_project_files(root)
    searchable = "\n".join(read_text(path) for path in files if is_analysis_subject(path, root))
    code_searchable = "\n".join(
        read_text(path)
        for path in files
        if is_analysis_subject(path, root) and path.suffix.lower() in {".m", ".py"}
    )
    lower_text = searchable.lower()
    lower_code = code_searchable.lower()
    objective_rows = []
    for objective in TASK_OBJECTIVES:
        marker_hits = {
            marker: lower_text.count(marker.lower())
            for marker in objective["expected_evidence"]
        }
        implementation_hits = {
            marker: lower_code.count(marker.lower())
            for marker in objective["expected_evidence"]
        }
        hit_count = sum(1 for count in marker_hits.values() if count > 0)
        implementation_hit_count = sum(1 for count in implementation_hits.values() if count > 0)
        coverage = hit_count / len(objective["expected_evidence"])
        implementation_coverage = implementation_hit_count / len(objective["expected_evidence"])
        status = "covered" if coverage >= 0.75 else "partial" if coverage >= 0.35 else "gap"
        if (
            objective["id"] == "objective_future_cavitation"
            and (implementation_coverage <= 0.5 or implementation_hits.get("sonochemical", 0) == 0)
        ):
            status = "planned_not_implemented"
        objective_rows.append(
            {
                "id": objective["id"],
                "title": objective["title"],
                "coverage": round(coverage, 3),
                "implementation_coverage": round(implementation_coverage, 3),
                "status": status,
                "marker_hits": marker_hits,
                "implementation_hits": implementation_hits,
            }
        )

    gaps = [
        {
            "id": "gap_machine_readable_run_outputs",
            "severity": "high",
            "task_relation": "Metrics exist in script output, but Codex needs stable JSON snapshots to compare runs.",
            "current_evidence": "HDSPdebug.m prints PCC/SSIM/NMSE/IoU/Dice/over/under values, but no stable run manifest is detected.",
            "target_state": "Every run writes one JSON result with parameters, metric values, artifact paths, git revision, and timestamp.",
            "next_action": "Add a non-invasive MATLAB result export block after reporting, guarded by a flag so the main logic remains unchanged.",
        },
        {
            "id": "gap_effective_transmission_model",
            "severity": "high",
            "task_relation": "The task goal depends on reducing forward-design to k-Wave domain mismatch.",
            "current_evidence": "Existing handoff identifies ASM/ideal phase to 3D discrete k-Wave mismatch as the main problem.",
            "target_state": "Use exported exit-plane samples to fit or validate an effective transmission model for discrete thickness voxels.",
            "next_action": "Use current exit-plane diagnostics and surrogate data to map thickness, local gradient, and edge distance to exit amplitude/phase correction.",
        },
        {
            "id": "gap_cavitation_branch_not_dynamic",
            "severity": "medium",
            "task_relation": "HDSP/DSP literature points to cavitation-driven sonochemistry, while current implementation is thermal-dose dominant.",
            "current_evidence": "cavitation_limit is detected as a static pressure cap before heat-source and Arrhenius curing calculations.",
            "target_state": "Introduce a threshold-triggered cavitation activation field with saturation/penalty, fused with the existing thermal dose.",
            "next_action": "Prototype a sidecar cavitation score from p_3d_scaled, then compare pure thermal versus thermal+cavitation metrics.",
        },
        {
            "id": "gap_metric_decision_rule",
            "severity": "medium",
            "task_relation": "Task materials mention multiple target metrics but no single optimization decision rule.",
            "current_evidence": "PCC/SSIM/NMSE/EE/IoU/Dice/Over-cure/Under-cure are present, but tradeoff priority is not machine-readable.",
            "target_state": "Define a weighted score or Pareto rule for model selection by experiment type.",
            "next_action": "Create a score profile that prioritizes IoU/Dice and penalizes over-cure for curing prediction, while keeping ASM/k-Wave mismatch metrics for diagnosis.",
        },
    ]
    return {
        "objectives": objective_rows,
        "gaps": gaps,
        "source_documents": [
            rel(path, root)
            for path in files
            if classify_file(path, root) == "document_or_extracted_text"
        ],
    }


def build_backlog() -> list[dict[str, Any]]:
    return [
        {
            "id": "opt_001_run_result_json",
            "priority": 1,
            "purpose": "Make each simulation result directly readable by Codex without scraping console output.",
            "linked_gaps": ["gap_machine_readable_run_outputs", "gap_metric_decision_rule"],
            "type": "instrumentation",
            "suggested_scope": "Add sidecar result export after the existing final metric reporting block.",
            "acceptance_criteria": [
                "A JSON file contains phase_refine_mode, pressure/exposure/cooling choice, PCC, SSIM, NMSE, EE, IoU, Dice, over_cure, under_cure.",
                "Export can be disabled and does not alter the numerical path.",
            ],
        },
        {
            "id": "opt_002_metric_score_profile",
            "priority": 2,
            "purpose": "Turn many metrics into explicit optimization targets for task-aligned iteration.",
            "linked_gaps": ["gap_metric_decision_rule"],
            "type": "analysis_policy",
            "suggested_scope": "Create codex_analysis/metric_profiles.json and use it when comparing run_result JSON files.",
            "acceptance_criteria": [
                "Curing profile rewards IoU/Dice and penalizes over-cure/under-cure.",
                "Propagation profile rewards ASM-kWave agreement and target PCC/SSIM while penalizing NMSE.",
            ],
        },
        {
            "id": "opt_003_effective_transmission_dataset",
            "priority": 3,
            "purpose": "Attack the current highest-value domain gap without changing the main algorithm first.",
            "linked_gaps": ["gap_effective_transmission_model"],
            "type": "model_diagnosis",
            "suggested_scope": "Standardize exit-plane sample export into a dataset manifest with feature definitions.",
            "acceptance_criteria": [
                "Each sample records local thickness, layer count, thickness gradient, board mask distance, exit amplitude, and exit phase residual.",
                "Dataset summary reports sample count, feature ranges, and held-out validation split.",
            ],
        },
        {
            "id": "opt_004_cavitation_sidecar_score",
            "priority": 4,
            "purpose": "Prepare the future cavitation module as an analyzable branch before integrating it into curing.",
            "linked_gaps": ["gap_cavitation_branch_not_dynamic"],
            "type": "physics_extension",
            "suggested_scope": "Compute cavitation activation from pressure threshold and saturation parameters as a sidecar map.",
            "acceptance_criteria": [
                "Sidecar map is exported separately from thermal Omega.",
                "Comparison report shows thermal-only versus thermal+cavitation IoU/Dice/over/under deltas.",
            ],
        },
    ]


def build_metric_profiles() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "profiles": [
            {
                "id": "curing_prediction",
                "purpose": "Select changes that improve printed/solidified shape against the target.",
                "maximize": ["IoU", "Dice", "cured_coverage"],
                "minimize": ["over_cure_ratio", "under_cure_ratio", "NMSE"],
                "primary_score": {
                    "formula": "0.40*IoU + 0.30*Dice - 0.15*over_cure_ratio - 0.15*under_cure_ratio",
                    "required_inputs": ["IoU", "Dice", "over_cure_ratio", "under_cure_ratio"],
                },
                "decision_rule": "Prefer higher primary_score. Reject runs that improve IoU only by expanding over_cure_ratio.",
            },
            {
                "id": "propagation_domain_gap",
                "purpose": "Select changes that reduce ASM/design-model to k-Wave mismatch before changing curing physics.",
                "maximize": ["asm_kwave_corr", "board_exit_kwave_corr", "best_corr", "SSIM_val"],
                "minimize": ["asm_kwave_nmse", "asm_python_kwave_nmse", "NMSE"],
                "primary_score": {
                    "formula": "0.35*asm_kwave_corr + 0.25*board_exit_kwave_corr + 0.20*best_corr + 0.20*SSIM_val - 0.20*asm_kwave_nmse",
                    "required_inputs": ["asm_kwave_corr", "board_exit_kwave_corr", "best_corr", "SSIM_val", "asm_kwave_nmse"],
                },
                "decision_rule": "Prefer changes that improve k-Wave agreement without lowering Python/IASA ASM target quality.",
            },
            {
                "id": "cavitation_extension",
                "purpose": "Compare thermal-only curing with future threshold-triggered cavitation-assisted curing.",
                "maximize": ["IoU_delta", "Dice_delta"],
                "minimize": ["over_cure_delta", "under_cure_delta", "activation_outside_target"],
                "primary_score": {
                    "formula": "0.35*IoU_delta + 0.25*Dice_delta - 0.20*over_cure_delta - 0.20*activation_outside_target",
                    "required_inputs": ["IoU_delta", "Dice_delta", "over_cure_delta", "activation_outside_target"],
                },
                "decision_rule": "Accept only if cavitation improves target curing without large outside-target activation.",
            },
        ],
    }


def build_machine_readability(root: Path) -> dict[str, Any]:
    expected_outputs = [
        "project_manifest.json",
        "task_alignment.json",
        "optimization_backlog.json",
        "pipeline_map.json",
        "metric_profiles.json",
        "analysis_index.md",
    ]
    return {
        "analysis_directory": OUTPUT_DIR,
        "expected_outputs": expected_outputs,
        "consumer_contract": {
            "project_manifest.json": "Static repo inventory, entrypoints, parameters, and pipeline summary.",
            "task_alignment.json": "Task objective coverage, detected evidence, and actionable gaps.",
            "optimization_backlog.json": "Prioritized next iterations tied to detected gaps.",
            "pipeline_map.json": "Stage-by-stage flow readable without opening the main script.",
            "metric_profiles.json": "Machine-readable scoring profiles for targeted iteration.",
            "analysis_index.md": "Human-readable index for the generated machine-readable files.",
        },
        "regeneration_command": "python tools/generate_codex_context.py",
        "non_intrusive_policy": "Generated analysis artifacts must not change HDSPdebug.m, PANN_Holography.py, or MATLAB helper logic.",
    }


def build_context(root: Path) -> dict[str, Any]:
    root = root.resolve()
    files = summarize_files(root)
    main_text = read_text(root / MAIN_SCRIPT) if (root / MAIN_SCRIPT).exists() else ""
    metric_line_hits = find_line_numbers(
        main_text,
        ["PCC", "SSIM", "NMSE", "IoU", "Dice", "over_cure_ratio", "under_cure_ratio", "cavitation_limit"],
    )
    pipeline = build_pipeline(root)
    task_alignment = build_task_alignment(root)
    suffix_counts = Counter(Path(path).suffix.lower() or "<none>" for path in files["by_path"])
    role_counts = {role: len(paths) for role, paths in files["by_role"].items()}

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "project_root": str(root),
        "entrypoints": summarize_entrypoints(root),
        "files": files,
        "repository_summary": {
            "file_count": len(files["by_path"]),
            "suffix_counts": dict(sorted(suffix_counts.items())),
            "role_counts": dict(sorted(role_counts.items())),
        },
        "pipeline": pipeline,
        "metric_line_hits": metric_line_hits,
        "task_alignment": task_alignment,
        "machine_readability": build_machine_readability(root),
        "optimization_backlog": build_backlog(),
        "metric_profiles": build_metric_profiles(),
    }


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_markdown_index(context: dict[str, Any], output_dir: Path) -> None:
    objective_lines = []
    for objective in context["task_alignment"]["objectives"]:
        objective_lines.append(
            f"- `{objective['id']}`: {objective['status']} ({objective['coverage']:.3f}) - {objective['title']}"
        )

    gap_lines = []
    for gap in context["task_alignment"]["gaps"]:
        gap_lines.append(f"- `{gap['id']}` [{gap['severity']}]: {gap['next_action']}")

    backlog_lines = []
    for item in context["optimization_backlog"]:
        backlog_lines.append(f"- P{item['priority']} `{item['id']}`: {item['purpose']}")

    text = "\n".join(
        [
            "# Codex Analysis Index",
            "",
            "This directory is generated sidecar context for Codex-driven HDSP iteration.",
            "It does not modify the main MATLAB/Python simulation logic.",
            "",
            "## Files",
            "",
            "- `project_manifest.json`: static inventory, entrypoints, parameters, and pipeline summary.",
            "- `pipeline_map.json`: compact stage map for direct code analysis.",
            "- `task_alignment.json`: task-objective coverage and gaps.",
            "- `optimization_backlog.json`: prioritized next work tied to gaps.",
            "- `metric_profiles.json`: scoring profiles for comparing future run JSON files.",
            "",
            "## Current Pipeline",
            "",
            context["pipeline"]["summary"],
            "",
            "## Task Alignment",
            "",
            *objective_lines,
            "",
            "## Gaps",
            "",
            *gap_lines,
            "",
            "## Suggested Iteration Backlog",
            "",
            *backlog_lines,
            "",
            "## Regenerate",
            "",
            "```powershell",
            "python tools/generate_codex_context.py",
            "```",
            "",
        ]
    )
    (output_dir / "analysis_index.md").write_text(text, encoding="utf-8")


def write_outputs(context: dict[str, Any], output_dir: Path) -> dict[str, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "project_manifest": output_dir / "project_manifest.json",
        "pipeline_map": output_dir / "pipeline_map.json",
        "task_alignment": output_dir / "task_alignment.json",
        "optimization_backlog": output_dir / "optimization_backlog.json",
        "metric_profiles": output_dir / "metric_profiles.json",
    }
    write_json(outputs["project_manifest"], context)
    write_json(outputs["pipeline_map"], context["pipeline"])
    write_json(outputs["task_alignment"], context["task_alignment"])
    write_json(outputs["optimization_backlog"], context["optimization_backlog"])
    write_json(outputs["metric_profiles"], context["metric_profiles"])
    write_markdown_index(context, output_dir)
    outputs["analysis_index"] = output_dir / "analysis_index.md"
    return {key: str(path) for key, path in outputs.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Codex-readable HDSP project context.")
    parser.add_argument("--root", default=".", help="Project root. Defaults to current directory.")
    parser.add_argument("--output-dir", default=OUTPUT_DIR, help="Output directory for generated analysis files.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    context = build_context(root)
    written = write_outputs(context, root / args.output_dir)
    for key, path in written.items():
        print(f"{key}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
