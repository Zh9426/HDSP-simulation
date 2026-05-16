import json
import unittest
from pathlib import Path

from tools.analyze_codex_run import analyze_run, write_analysis


class RuntimeExportTests(unittest.TestCase):
    def test_main_scripts_export_codex_runtime_json(self):
        root = Path(__file__).resolve().parents[1]
        hdsp_text = (root / "HDSPdebug.m").read_text(encoding="utf-8", errors="ignore")
        pann_text = (root / "PANN_Holography.py").read_text(encoding="utf-8", errors="ignore")

        self.assertIn("codex_runs", hdsp_text)
        self.assertIn("hdsp_latest_run.json", hdsp_text)
        self.assertIn("jsonencode", hdsp_text)
        self.assertIn("analyze_codex_run.py", hdsp_text)
        self.assertIn("latest_run_analysis.json", hdsp_text)
        self.assertIn("codex_runs", pann_text)
        self.assertIn("pann_latest_run.json", pann_text)
        self.assertIn("analyze_codex_run.py", pann_text)

    def test_analyze_run_turns_metrics_into_targeted_recommendations(self):
        fake_run = {
            "schema_version": "1.0",
            "source": "HDSPdebug.m",
            "metrics": {
                "best_corr": 0.45,
                "SSIM_val": 0.41,
                "NMSE": 0.38,
                "IoU": 0.31,
                "Dice": 0.43,
                "over_cure_ratio": 0.22,
                "under_cure_ratio": 0.37,
                "asm_kwave_corr": 0.21,
                "asm_kwave_nmse": 0.62,
                "board_exit_kwave_corr": 0.25,
            },
        }

        analysis = analyze_run(fake_run)

        self.assertEqual(analysis["source"], "HDSPdebug.m")
        self.assertGreaterEqual(len(analysis["recommendations"]), 3)
        self.assertEqual(analysis["recommendations"][0]["target_file"], "HDSPdebug.m")
        self.assertIn("domain_gap", {item["category"] for item in analysis["recommendations"]})
        self.assertIn("curing_gap", {item["category"] for item in analysis["recommendations"]})

        root = Path(__file__).resolve().parents[1]
        output_path = root / "codex_analysis" / "runtime_export_test_analysis.json"
        write_analysis(analysis, output_path)
        loaded = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(loaded["schema_version"], "1.0")


if __name__ == "__main__":
    unittest.main()
