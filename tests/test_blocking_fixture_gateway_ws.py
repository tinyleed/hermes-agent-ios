import json
import unittest

from mock_gateway.ws_fixture import BlockingFixtureRunState, BlockingFixtureWebSocket


class BlockingFixtureGatewayContractTestCase(unittest.TestCase):
    def test_fixture_request_payloads_are_metadata_only(self):
        state = BlockingFixtureRunState()
        sent = []

        class Recorder(BlockingFixtureWebSocket):
            def __init__(self):
                self.state = state

            def send_text(self, text):
                sent.append(text)

        recorder = Recorder()
        recorder.send_approval_request()
        recorder.send_sudo_request()
        recorder.send_secret_request()

        rendered = "\n".join(sent).lower()
        for forbidden in ("password=", "token=", "api_key", "secret_value", "super-secret"):
            self.assertNotIn(forbidden, rendered)

        frames = [json.loads(item) for item in sent]
        self.assertEqual([frame["params"]["type"] for frame in frames], ["approval.request", "sudo.request", "secret.request"])
        self.assertEqual(frames[2]["params"]["payload"]["env_var"], "HERMES_AGENT_IOS_FAKE_MOCK_GATEWAY_SECRET")

    def test_response_summary_records_redacted_state_only(self):
        state = BlockingFixtureRunState()
        state.record_response("sudo", request_id=state.sudo_request_id)
        summary = state.response_summary()
        self.assertEqual(summary["responses"][0]["value_state"], "redacted_present")
        self.assertNotIn("password", json.dumps(summary).lower())
        self.assertNotIn("token", json.dumps(summary).lower())


if __name__ == "__main__":
    unittest.main()
