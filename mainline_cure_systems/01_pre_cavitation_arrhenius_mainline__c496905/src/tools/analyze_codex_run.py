"""Analyze Codex runtime exports and produce targeted iteration guidance."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1.0"


def number(metrics: dict[str, Any], key: str, default: float = 0.0) -> float:
    value = metrics.get(key, default)
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def analyze_run(run: dict[str, Any]) -> dict[str, Any]:
    metrics = run.get("metrics", {})
    recommendations: list[dict[str, Any]] = []
    source = run.get("source", "unknown")

    if source == "PANN_Holography.py":
        best_loss = number(metrics, "best_loss")
        layer_min = metrics.get("layer_min")
        layer_max = metrics.get("layer_max")
        recommendations.append(
            {
                "priority": 1,
                "category": "phase_initialization",
                "target_file": "PANN_Holography.py",
                "target_area": "loss terms and quantized layer export",
                "reason": "PANN finished and exported a quantized phase initialization. Review loss and layer statistics before changing MATLAB refinement.",
                "evidence": {
                    "best_loss": best_loss,
                    "layer_min": layer_min,
                    "layer_max": layer_max,
                    "layer_mean": metrics.get("layer_mean"),
                },
                "proposed_change": "Only modify PANN weights or target shaping after comparing this initialization against the next HDSP k-Wave run.",
            }
        )
        return {
            "schema_version": SCHEMA_VERSION,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "source": source,
            "input_run_id": run.get("run_id"),
            "execution_policy": "proposal_only",
            "recommendations": recommendations,
        }

    asm_kwave_corr = number(metrics, "asm_kwave_corr")
    asm_kwave_nmse = number(metrics, "asm_kwave_nmse")
    board_exit_kwave_corr = number(metrics, "board_exit_kwave_corr")
    iou = number(metrics, "IoU")
    dice = number(metrics, "Dice")
    over_cure = number(metrics, "over_cure_ratio")
    under_cure = number(metrics, "under_cure_ratio")

    if asm_kwave_corr < 0.65 or board_exit_kwave_corr < 0.65 or asm_kwave_nmse > 0.25:
        recommendations.append(
            {
                "priority": 1,
                "category": "domain_gap",
                "target_file": "HDSPdebug.m",
                "target_area": "exit-plane diagnostics and discrete-board transmission",
                "reason": "ASM/design-model to k-Wave agreement is weak, so algorithm changes should first reduce forward-model mismatch.",
                "evidence": {
                    "asm_kwave_corr": asm_kwave_corr,
                    "asm_kwave_nmse": asm_kwave_nmse,
                    "board_exit_kwave_corr": board_exit_kwave_corr,
                },
                "proposed_change": "Export or fit an effective transmission correction using thickness, gradient, aperture-edge distance, exit amplitude, and exit phase residual.",
            }
        )

    if iou < 0.55 or dice < 0.65 or over_cure > 0.12 or under_cure > 0.18:
        recommendations.append(
            {
                "priority": 2,
                "category": "curing_gap",
                "target_file": "HDSPdebug.m",
                "target_area": "thermal dose and curing decision block",
                "reason": "Curing shape metrics are below a useful target or the model is trading target fill for over/under-cure.",
                "evidence": {
                    "IoU": iou,
                    "Dice": dice,
                    "over_cure_ratio": over_cure,
                    "under_cure_ratio": under_cure,
                },
                "proposed_change": "Compare thermal-only result against sidecar cavitation activation and metric profiles before changing the main Arrhenius path.",
            }
        )

    if not run.get("artifacts"):
        recommendations.append(
            {
                "priority": 3,
                "category": "machine_readability",
                "target_file": "HDSPdebug.m",
                "target_area": "runtime artifact export",
                "reason": "The run does not describe figure, MAT, or sample artifacts, limiting follow-up analysis.",
                "evidence": {"artifacts_present": False},
                "proposed_change": "Add artifact paths for figures, MAT outputs, and sample exports to the runtime JSON.",
            }
        )

    if not recommendations:
        recommendations.append(
            {
                "priority": 1,
                "category": "next_experiment",
                "target_file": "HDSPdebug.m",
                "target_area": "controlled parameter sweep",
                "reason": "No critical metric gap was detected from configured thresholds.",
                "evidence": metrics,
                "proposed_change": "Run a controlled ablation and compare with codex_analysis/metric_profiles.json.",
            }
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": source,
        "input_run_id": run.get("run_id"),
        "execution_policy": "proposal_only",
        "recommendations": sorted(recommendations, key=lambda item: item["priority"]),
    }


def write_analysis(analysis: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(analysis, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown_path = output_path.with_suffix(".md")
    lines = [
        "# Codex Run Analysis",
        "",
        f"- Source: `{analysis.get('source')}`",
        f"- Run id: `{analysis.get('input_run_id')}`",
        f"- Policy: `{analysis.get('execution_policy', 'proposal_only')}`",
        "",
        "## Recommendations",
        "",
    ]
    for item in analysis.get("recommendations", []):
        lines.extend(
            [
                f"### P{item.get('priority')} {item.get('category')}",
                "",
                f"- Target: `{item.get('target_file')}` / {item.get('target_area')}",
                f"- Reason: {item.get('reason')}",
                f"- Proposed change: {item.get('proposed_change')}",
                f"- Evidence: `{json.dumps(item.get('evidence', {}), ensure_ascii=False)}`",
                "",
            ]
        )
    markdown_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze a Codex runtime JSON export.")
    parser.add_argument("--run-json", default="codex_runs/hdsp_latest_run.json")
    parser.add_argument("--output", default="codex_analysis/latest_run_analysis.json")
    args = parser.parse_args()

    run_path = Path(args.run_json)
    run = json.loads(run_path.read_text(encoding="utf-8"))
    analysis = analyze_run(run)
    write_analysis(analysis, Path(args.output))
    print(f"analysis: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
