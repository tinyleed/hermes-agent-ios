from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "verify_blocking_card_fixtures.py"
SPEC = importlib.util.spec_from_file_location("verify_blocking_card_fixtures", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
fixtures = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = fixtures
SPEC.loader.exec_module(fixtures)


class BlockingCardFixtureTests(unittest.TestCase):
    def test_fixture_set_covers_approval_sudo_and_secret(self):
        summaries = fixtures.validate_all()
        self.assertEqual(
            {item["event"] for item in summaries},
            {"approval.request", "sudo.request", "secret.request"},
        )
        self.assertTrue(all(item["value_state"] == "metadata-only/redacted" for item in summaries))

    def test_fixtures_do_not_carry_secret_bearing_payload_keys(self):
        for fixture in fixtures.FIXTURES:
            payload = fixtures.payload_from_frame(fixture.frame)
            lowered_keys = {key.lower() for key in payload}
            self.assertFalse(
                lowered_keys & fixtures.FORBIDDEN_PAYLOAD_KEYS,
                f"{fixture.name} contains secret-bearing payload keys",
            )

    def test_fixtures_do_not_look_like_raw_credentials(self):
        for fixture in fixtures.FIXTURES:
            serialized = json.dumps(fixture.frame, sort_keys=True)
            self.assertIsNone(
                fixtures.FORBIDDEN_TEXT_RE.search(serialized),
                f"{fixture.name} looks like it contains a raw credential",
            )

    def test_cli_outputs_redacted_summary(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "verify_blocking_card_fixtures.py")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OK blocking-card fixtures", result.stdout)
        self.assertIn("approval.request", result.stdout)
        self.assertIn("sudo.request", result.stdout)
        self.assertIn("secret.request", result.stdout)
        self.assertNotIn("password=", result.stdout.lower())
        self.assertNotIn("token=", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()
