import json
import unittest
from pathlib import Path

from tools.generate_codex_context import build_context, write_outputs


class GenerateCodexContextTests(unittest.TestCase):
    def test_build_context_emits_machine_readable_core_contract(self):
        root = Path(__file__).resolve().parents[1]

        context = build_context(root)

        self.assertEqual(context["schema_version"], "1.0")
        self.assertEqual(context["entrypoints"]["matlab_main"], "HDSPdebug.m")
        self.assertIn("HDSPdebug.m", context["files"]["by_path"])
        self.assertIn("PANN_Holography.py", context["files"]["by_path"])
        self.assertGreaterEqual(len(context["pipeline"]["stages"]), 6)
        self.assertGreaterEqual(len(context["task_alignment"]["gaps"]), 3)
        self.assertGreaterEqual(len(context["optimization_backlog"]), 3)

    def test_write_outputs_creates_json_and_markdown_for_codex_consumption(self):
        root = Path(__file__).resolve().parents[1]
        context = build_context(root)

        output_dir = root / "codex_analysis"
        written = write_outputs(context, output_dir)

        self.assertTrue((output_dir / "project_manifest.json").exists())
        self.assertTrue((output_dir / "task_alignment.json").exists())
        self.assertTrue((output_dir / "optimization_backlog.json").exists())
        self.assertTrue((output_dir / "metric_profiles.json").exists())
        self.assertTrue((output_dir / "analysis_index.md").exists())
        self.assertIn("project_manifest", written)

        loaded = json.loads((output_dir / "project_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(loaded["entrypoints"]["matlab_main"], "HDSPdebug.m")


if __name__ == "__main__":
    unittest.main()
