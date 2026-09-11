"""Run the real Bash scripts with fake AWS/Docker/pip and real filesystem tools.

Set BASH_TEST_EXECUTABLE to also exercise an older Bash, such as Bash 3.2.
No AWS calls, Docker daemon, package downloads, or credentials are needed.
"""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import unittest
import zipfile


PROJECT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH_TEST_EXECUTABLE") or shutil.which("bash")


class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="agent core's $test-")
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.bin = self.workspace / "bin"
        self.bin.mkdir()
        self.source = self.workspace / "source files"
        self.source.mkdir()
        self.output = self.workspace / "build output" / "source.zip"
        self.calls = self.workspace / "calls.jsonl"
        self.published = self.workspace / "published"
        self.environment = {
            **os.environ,
            "PATH": str(self.bin),
            "BUILD_SOURCE_DIR": str(self.source),
            "BUILD_ZIP_PATH": str(self.output),
            "BUILD_SOURCE_FILES": "agent.py\nnested data/weather.txt\nrequirements.txt",
            "BUILD_REPOSITORY_URL": "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo/agent",
            "BUILD_IMAGE_TAG": "build-example",
            "BUILD_AWS_REGION": "us-east-1",
            "MOCK_CALLS": str(self.calls),
            "MOCK_PUBLISHED": str(self.published),
        }
        for command in ("zip", "mktemp", "mkdir", "cp", "mv", "rm", "find", "dirname"):
            executable = shutil.which(command)
            if not executable:
                self.skipTest(f"Script smoke tests require {command}")
            (self.bin / command).symlink_to(executable)
        (self.source / "agent.py").write_text("print('hello')\n")
        (self.source / "requirements.txt").write_text("demo-package\n")
        (self.source / "Dockerfile").write_text("FROM scratch\n")
        (self.source / "nested data").mkdir()
        (self.source / "nested data/weather.txt").write_text("data\n")
        (self.source / "ignored.txt").write_text("not a build input\n")
        self.stub("sleep", "pass")
        self.stub("python3", """
            if sys.argv[1:] == ['-m', 'pip', '--version']:
                sys.exit(int(os.environ.get('MOCK_NO_PIP', '0')))
            assert sys.argv[1:4] == ['-m', 'pip', 'install']
            target = Path(sys.argv[sys.argv.index('--target') + 1])
            (target / 'dependency.py').write_text('dependency')
            (target / '__pycache__').mkdir()
            (target / '__pycache__/dependency.pyc').write_bytes(b'host bytecode')
            (target / 'legacy.pyc').write_bytes(b'host bytecode')
            if os.environ.get('MOCK_INTERRUPT'):
                import signal
                os.kill(os.getppid(), signal.SIGTERM)
            sys.exit(int(os.environ.get('MOCK_PIP_FAIL', '0')))
        """)
        self.stub("aws", """
            if sys.argv[1:3] == ['ecr', 'describe-images']:
                if os.environ.get('MOCK_AWS_DENIED'):
                    print('(AccessDeniedException): access denied', file=sys.stderr)
                    sys.exit(254)
                if Path(os.environ['MOCK_PUBLISHED']).exists() and not os.environ.get('MOCK_NOT_VISIBLE'):
                    print('sha256:example')
                else:
                    print('(ImageNotFoundException): image not found', file=sys.stderr)
                    sys.exit(254)
            elif sys.argv[1:3] == ['ecr', 'get-login-password']:
                if os.environ.get('MOCK_LOGIN_FAIL'):
                    sys.exit(1)
                print('fake-test-password')
            else:
                raise AssertionError(sys.argv)
        """)
        self.stub("docker", """
            if sys.argv[1:] == ['info']:
                sys.exit(int(os.environ.get('MOCK_DAEMON_FAIL', '0')))
            elif sys.argv[1:] == ['buildx', 'version']:
                sys.exit(int(os.environ.get('MOCK_BUILDX_FAIL', '0')))
            elif sys.argv[1:] == ['buildx', 'inspect', '--bootstrap']:
                print('Platforms: ' + os.environ.get('MOCK_PLATFORMS', 'linux/amd64, linux/arm64'))
            elif sys.argv[1] == 'login':
                sys.stdin.read()
            elif sys.argv[1:3] == ['buildx', 'build']:
                if os.environ.get('MOCK_BUILD_FAIL'):
                    sys.exit(1)
                Path(os.environ['MOCK_PUBLISHED']).touch()
            else:
                raise AssertionError(sys.argv)
        """)

    def stub(self, name, body):
        path = self.bin / name
        if path.is_symlink():
            path.unlink()
        path.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\nfrom pathlib import Path\n"
            "with open(os.environ['MOCK_CALLS'], 'a') as log:\n"
            "    log.write(json.dumps([Path(sys.argv[0]).name] + sys.argv[1:]) + '\\n')\n"
            + textwrap.dedent(body)
        )
        path.chmod(0o755)

    def run_script(self, runtime, **environment):
        return subprocess.run(
            [BASH, str(PROJECT / "scripts" / f"build-{runtime}.sh")],
            env={**self.environment, **environment},
            cwd=self.workspace,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def recorded_calls(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def assert_no_staging_files(self):
        self.assertEqual(list(self.output.parent.glob(".code-agent.*")), [])

    def test_code_packages_selected_files_with_spaces_and_removes_bytecode(self):
        result = self.run_script("code")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.output) as archive:
            files = {name for name in archive.namelist() if not name.endswith("/")}
            self.assertEqual(files, {"agent.py", "dependency.py", "nested data/weather.txt"})
        install = next(call for call in self.recorded_calls() if call[:4] == ["python3", "-m", "pip", "install"])
        for flag, value in (("--platform", "manylinux2014_aarch64"), ("--python-version", "3.11"), ("--abi", "cp311")):
            self.assertEqual(install[install.index(flag) + 1], value)
        self.assert_no_staging_files()

    def test_code_rebuild_replaces_zip_without_stale_entries(self):
        self.output.parent.mkdir()
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("removed-module.py", "stale")
        result = self.run_script("code")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.output) as archive:
            self.assertNotIn("removed-module.py", archive.namelist())

    def test_code_failures_preserve_previous_zip_and_clean_staging(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"previous ZIP")
        for failure in ("pip", "zip"):
            with self.subTest(failure=failure):
                if failure == "zip":
                    self.stub("zip", "sys.exit(1)")
                result = self.run_script("code", MOCK_PIP_FAIL="1" if failure == "pip" else "0")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.output.read_bytes(), b"previous ZIP")
                self.assert_no_staging_files()

    def test_code_missing_dependencies_fail_before_staging(self):
        for dependency in ("python3", "zip"):
            with self.subTest(dependency=dependency):
                path = self.bin / dependency
                saved = self.bin / f"saved-{dependency}"
                path.rename(saved)
                try:
                    result = self.run_script("code")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"Required command '{dependency}'", result.stderr)
                    self.assertFalse(self.output.parent.exists())
                finally:
                    saved.rename(path)
        result = self.run_script("code", MOCK_NO_PIP="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pip is unavailable", result.stderr)
        self.assertFalse(self.output.parent.exists())

    def test_code_termination_cleans_staging_and_preserves_previous_zip(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"previous ZIP")
        result = self.run_script("code", MOCK_INTERRUPT="1")
        self.assertEqual(result.returncode, 128 + signal.SIGTERM)
        self.assertEqual(self.output.read_bytes(), b"previous ZIP")
        self.assert_no_staging_files()

    def test_code_invalid_or_missing_inputs_fail_before_staging(self):
        for files in ("../outside.py", "/absolute.py", "missing.py", "agent.py\n\nrequirements.txt"):
            with self.subTest(files=files):
                result = self.run_script("code", BUILD_SOURCE_FILES=files)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.parent.exists())

    def test_container_reuses_existing_tag_without_docker(self):
        self.published.touch()
        (self.bin / "docker").unlink()
        result = self.run_script("container")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Using existing image", result.stdout)
        self.assertFalse(any(call[:3] == ["aws", "ecr", "get-login-password"] for call in self.recorded_calls()))

    def test_container_pushes_arm64_image_and_retry_reuses_it(self):
        result = self.run_script("container")
        self.assertEqual(result.returncode, 0, result.stderr)
        build = next(call for call in self.recorded_calls() if call[:3] == ["docker", "buildx", "build"])
        self.assertEqual(build[build.index("--platform") + 1], "linux/arm64")
        self.assertIn("--provenance=false", build)
        self.assertIn("--push", build)
        self.assertEqual(build[-1], str(self.source))
        self.assertEqual(build[build.index("--tag") + 1], self.environment["BUILD_REPOSITORY_URL"] + ":build-example")
        result = self.run_script("container")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(call[:3] == ["docker", "buildx", "build"] for call in self.recorded_calls()), 1)

    def test_container_missing_commands_are_explained(self):
        for dependency in ("aws", "docker"):
            with self.subTest(dependency=dependency):
                path = self.bin / dependency
                saved = self.bin / f"saved-{dependency}"
                path.rename(saved)
                try:
                    result = self.run_script("container")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"Required command '{dependency}'", result.stderr)
                    self.assertFalse(self.published.exists())
                finally:
                    saved.rename(path)

    def test_container_preflight_and_build_failures_are_explained(self):
        cases = (
            ({"MOCK_AWS_DENIED": "1"}, "Cannot inspect"),
            ({"MOCK_DAEMON_FAIL": "1"}, "Docker daemon is unavailable"),
            ({"MOCK_BUILDX_FAIL": "1"}, "Docker buildx is unavailable"),
            ({"MOCK_PLATFORMS": "linux/amd64"}, "lacks linux/arm64"),
            ({"MOCK_LOGIN_FAIL": "1"}, "ECR login failed"),
            ({"MOCK_BUILD_FAIL": "1"}, "Container build or ECR push failed"),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                result = self.run_script("container", **environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.published.exists())

    def test_container_times_out_if_pushed_image_is_not_visible(self):
        result = self.run_script("container", MOCK_NOT_VISIBLE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not visible in ECR", result.stderr)


if __name__ == "__main__":
    unittest.main()
