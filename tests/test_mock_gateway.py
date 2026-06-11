import json
import threading
import unittest
from http.client import HTTPConnection
from urllib.parse import urlparse

from mock_gateway.server import make_server


class MockGatewayTestCase(unittest.TestCase):
    def setUp(self):
        self.server = make_server(("127.0.0.1", 0))
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()

    def request(self, method, path, body=None):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Content-Type": "application/json"} if body is not None else {}
        conn.request(method, path, body=payload, headers=headers)
        response = conn.getresponse()
        raw = response.read().decode("utf-8")
        conn.close()
        data = json.loads(raw) if raw else None
        return response.status, data

    def create_message(self):
        status, data = self.request("POST", "/v0/messages", {"text": "run status check"})
        self.assertEqual(status, 201)
        return data

    def test_post_message_creates_thread_run_and_approval(self):
        data = self.create_message()

        self.assertEqual(data["thread"]["lane"], "hermes-agent")
        self.assertEqual(data["message"]["role"], "assistant")
        self.assertEqual(data["message"]["kind"], "approval_card")
        self.assertEqual(data["run"]["status"], "waiting_for_approval")
        self.assertEqual(data["approval"]["status"], "pending")
        self.assertEqual(data["approval"]["riskTier"], 1)
        self.assertIn("approve_once", data["approval"]["actions"])

    def test_get_approvals_lists_pending_approval(self):
        created = self.create_message()

        status, data = self.request("GET", "/v0/approvals")

        self.assertEqual(status, 200)
        self.assertEqual(len(data["approvals"]), 1)
        self.assertEqual(data["approvals"][0]["id"], created["approval"]["id"])

    def test_get_thread_messages_returns_conversation_history(self):
        created = self.create_message()
        thread_id = created["thread"]["id"]
        approval_id = created["approval"]["id"]
        self.request("POST", f"/v0/approvals/{approval_id}/approve")

        status, data = self.request("GET", f"/v0/threads/{thread_id}/messages")

        self.assertEqual(status, 200)
        self.assertEqual(data["thread"]["id"], thread_id)
        self.assertEqual([message["kind"] for message in data["messages"]], ["approval_card", "command_result"])
        self.assertEqual(data["messages"][0]["threadId"], thread_id)

    def test_unknown_thread_messages_route_returns_404(self):
        status, data = self.request("GET", "/v0/threads/thread_missing/messages")

        self.assertEqual(status, 404)
        self.assertEqual(data["error"], "thread_not_found")

    def test_approve_pending_approval_completes_run(self):
        created = self.create_message()
        approval_id = created["approval"]["id"]

        status, data = self.request("POST", f"/v0/approvals/{approval_id}/approve")

        self.assertEqual(status, 200)
        self.assertEqual(data["approval"]["status"], "approved")
        self.assertEqual(data["run"]["status"], "done")
        self.assertEqual(data["result"]["kind"], "command_result")

    def test_reject_pending_approval_cancels_run(self):
        created = self.create_message()
        approval_id = created["approval"]["id"]

        status, data = self.request("POST", f"/v0/approvals/{approval_id}/reject")

        self.assertEqual(status, 200)
        self.assertEqual(data["approval"]["status"], "rejected")
        self.assertEqual(data["run"]["status"], "cancelled")

    def test_notification_token_registration_is_personal_team_gated_and_redacted(self):
        status, data = self.request("POST", "/v0/notification-tokens", {
            "deviceId": "iphone-local",
            "platform": "ios",
            "tokenRedacted": "<redacted>",
            "environment": "development",
            "enrolledDeveloperProgram": False,
        })

        self.assertEqual(status, 202)
        if data is None:
            self.fail("notification token registration should return JSON")
        self.assertEqual(data["notificationToken"]["deviceId"], "iphone-local")
        self.assertEqual(data["notificationToken"]["tokenState"], "redacted_present")
        self.assertFalse(data["notificationToken"]["apnsAvailable"])
        self.assertEqual(data["apnsGate"], "developer_program_required")
        self.assertNotIn("secret", json.dumps(data).lower())

    def test_unknown_route_returns_404(self):
        status, data = self.request("GET", "/v0/not-real")

        self.assertEqual(status, 404)
        self.assertEqual(data["error"], "not_found")


if __name__ == "__main__":
    unittest.main()
