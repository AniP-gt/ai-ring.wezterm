import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "shell" / "cc-glow-state.py"


class CcGlowStateTests(unittest.TestCase):
    def run_script(self, tmpdir, status="running", extra_env=None):
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(tmpdir),
                "XDG_STATE_HOME": str(tmpdir / "state"),
                "WEZTERM_PANE": "42",
                "CC_GLOW_WORKSPACE": "main",
                "PWD": "/tmp/project",
                "CC_GLOW_NOW": "1000",
                "CC_GLOW_AGENT_PID": str(os.getpid()),
            }
        )
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(SCRIPT), status, "claude"],
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )

    def read_state(self, tmpdir):
        path = tmpdir / "state" / "cc-glow" / "state.json"
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def test_writes_workspace_pane_state_and_osc(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            result = self.run_script(tmpdir, "running")
            self.assertEqual(result.returncode, 0, result.stderr)
            state = self.read_state(tmpdir)
            entry = state["sessions"]["main:42"]
            self.assertEqual(entry["workspace"], "main")
            self.assertEqual(entry["pane_id"], "42")
            self.assertEqual(entry["agent"], "claude")
            self.assertEqual(entry["status"], "running")
            self.assertEqual(entry["cwd"], "/tmp/project")
            self.assertIn("SetUserVar=AI_RING", result.stdout)
            self.assertIn("SetUserVar=CC_GLOW_STATE_VERSION", result.stdout)

    def test_preserves_started_at_on_update(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            self.run_script(tmpdir, "running")
            result = self.run_script(tmpdir, "done", {"CC_GLOW_NOW": "1100"})
            self.assertEqual(result.returncode, 0, result.stderr)
            entry = self.read_state(tmpdir)["sessions"]["main:42"]
            self.assertEqual(entry["started_at"], 1000)
            self.assertEqual(entry["updated_at"], 1100)
            self.assertEqual(entry["status"], "done")

    def test_waiting_state_is_persisted_and_emitted(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            result = self.run_script(tmpdir, "waiting")
            self.assertEqual(result.returncode, 0, result.stderr)
            entry = self.read_state(tmpdir)["sessions"]["main:42"]
            self.assertEqual(entry["status"], "waiting")
            self.assertIn("SetUserVar=AI_RING", result.stdout)

    def test_missing_pane_is_noop_success(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            result = self.run_script(tmpdir, "running", {"WEZTERM_PANE": ""})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertFalse((tmpdir / "state" / "cc-glow" / "state.json").exists())

    def test_cleans_expired_ended_entries(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            state_path = tmpdir / "state" / "cc-glow" / "state.json"
            state_path.parent.mkdir(parents=True)
            state_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "updated_at": 0,
                        "sessions": {
                            "old:1": {
                                "workspace": "old",
                                "pane_id": "1",
                                "agent": "claude",
                                "status": "ended",
                                "started_at": 1,
                                "updated_at": 1,
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            result = self.run_script(tmpdir, "running", {"CC_GLOW_NOW": "10000"})
            self.assertEqual(result.returncode, 0, result.stderr)
            sessions = self.read_state(tmpdir)["sessions"]
            self.assertNotIn("old:1", sessions)
            self.assertIn("main:42", sessions)


if __name__ == "__main__":
    unittest.main()
