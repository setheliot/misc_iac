"""Exercise the real Terraform hash expressions without providers or AWS calls."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]


class BuildHashTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="agentcore-hashes-")
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        shutil.copytree(PROJECT / "runtime-sources", self.workspace / "runtime-sources")
        shutil.copytree(PROJECT / "scripts", self.workspace / "scripts")
        # These locals use only filesystem functions, so they need no providers.
        configuration = "\n".join(
            (PROJECT / name).read_text().split('\nresource "', 1)[0]
            for name in ("container_build.tf", "code_build.tf")
        )
        (self.workspace / "main.tf").write_text(configuration)
        self.baseline = self.hashes()

    def evaluate(self):
        return subprocess.run(
            ["terraform", f"-chdir={self.workspace}", "console", "-no-color"],
            input=(
                "jsonencode({container = local.container_build_id, "
                "code = local.code_build_id})\n"
            ),
            capture_output=True,
            text=True,
            timeout=30,
        )

    def hashes(self):
        result = self.evaluate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Error:", result.stderr)
        return json.loads(json.loads(result.stdout.strip()))

    def test_unchanged_inputs_and_timestamps_do_not_change_hashes(self):
        self.assertEqual(self.hashes(), self.baseline)
        for path in self.workspace.rglob("*"):
            if path.is_file():
                stat = path.stat()
                os.utime(path, (stat.st_atime + 60, stat.st_mtime + 60))
        self.assertEqual(self.hashes(), self.baseline)

    def test_generated_files_and_documentation_do_not_change_hashes(self):
        for runtime in ("container-agent", "code-agent"):
            for relative in (
                "__pycache__/app.cpython-314.pyc",
                ".app.py.swp",
                "app.py~",
                "README.md",
                ".venv/lib/dependency.py",
            ):
                path = self.workspace / "runtime-sources" / runtime / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("generated content\n")
        self.assertEqual(self.hashes(), self.baseline)

    def test_each_build_input_changes_only_its_runtime_hash(self):
        inputs = {
            "container": ("container-agent", ("Dockerfile", "app.py", "requirements.txt")),
            "code": ("code-agent", ("agent.py", "requirements.txt")),
        }
        for runtime, (directory, names) in inputs.items():
            for name in names:
                with self.subTest(runtime=runtime, file=name):
                    path = self.workspace / "runtime-sources" / directory / name
                    original = path.read_bytes()
                    try:
                        path.write_bytes(original + b"\n# Changed input\n")
                        updated = self.hashes()
                        self.assertNotEqual(updated[runtime], self.baseline[runtime])
                        other = "code" if runtime == "container" else "container"
                        self.assertEqual(updated[other], self.baseline[other])
                    finally:
                        path.write_bytes(original)

    def test_missing_required_source_reports_an_error(self):
        (self.workspace / "runtime-sources/container-agent/app.py").unlink()
        # Terraform console can return zero even when local evaluation failed.
        result = self.evaluate()
        self.assertIn("Error in function call", result.stderr)
        self.assertIn("no such file or directory", result.stderr)

    def test_recipe_changes_only_its_runtime_build_id(self):
        for runtime in ("container", "code"):
            with self.subTest(runtime=runtime):
                path = self.workspace / "scripts" / f"build-{runtime}.sh"
                original = path.read_bytes()
                try:
                    path.write_bytes(original + b"\n# Changed recipe\n")
                    updated = self.hashes()
                    self.assertNotEqual(updated[runtime], self.baseline[runtime])
                    other = "code" if runtime == "container" else "container"
                    self.assertEqual(updated[other], self.baseline[other])
                finally:
                    path.write_bytes(original)

    def test_renaming_identical_source_changes_only_its_runtime_build_id(self):
        configuration = self.workspace / "main.tf"
        original = configuration.read_text()
        for runtime, filename in (("container", "app.py"), ("code", "agent.py")):
            with self.subTest(runtime=runtime):
                source = self.workspace / "runtime-sources" / f"{runtime}-agent" / filename
                renamed = source.with_name("renamed.py")
                source.rename(renamed)
                try:
                    configuration.write_text(original.replace(f'"{filename}"', '"renamed.py"'))
                    updated = self.hashes()
                    self.assertNotEqual(updated[runtime], self.baseline[runtime])
                    other = "code" if runtime == "container" else "container"
                    self.assertEqual(updated[other], self.baseline[other])
                finally:
                    renamed.rename(source)
                    configuration.write_text(original)


if __name__ == "__main__":
    unittest.main()
