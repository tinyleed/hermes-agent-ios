import Foundation
import HermesAgentCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func mockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

let commandResponseJSON = """
{
  "thread": {
    "id": "thread_abc",
    "title": "check system status",
    "lane": "hermes-agent",
    "createdAt": "2026-06-02T12:00:00Z",
    "updatedAt": "2026-06-02T12:00:00Z",
    "projectId": null
  },
  "message": {
    "id": "msg_abc",
    "threadId": "thread_abc",
    "role": "assistant",
    "kind": "approval_card",
    "body": "Approval required before completing mock command.",
    "card": {"approvalId": "approval_abc", "runId": "run_abc"},
    "createdAt": "2026-06-02T12:00:00Z"
  },
  "run": {
    "id": "run_abc",
    "threadId": "thread_abc",
    "title": "Mock Hermes command run",
    "lane": "hermes-agent",
    "status": "waiting_for_approval",
    "currentStep": "Awaiting approval",
    "risk": "low",
    "startedAt": "2026-06-02T12:00:00Z",
    "updatedAt": "2026-06-02T12:00:00Z",
    "artifactIds": [],
    "approvalIds": ["approval_abc"]
  },
  "approval": {
    "id": "approval_abc",
    "runId": "run_abc",
    "title": "Approve mock command",
    "description": "Allow Hermes Agent mock gateway to complete command: check system status",
    "riskTier": 1,
    "scope": ["mock_gateway_state"],
    "reason": "Exercise the v0.1 command + approval loop",
    "rollback": "No real side effects; local mock state only",
    "actions": ["approve_once", "reject", "explain"],
    "status": "pending",
    "createdAt": "2026-06-02T12:00:00Z"
  }
}
""".data(using: .utf8)!

let pendingApprovalsJSON = """
{
  "approvals": [
    {
      "id": "approval_abc",
      "runId": "run_abc",
      "title": "Approve mock command",
      "description": "Allow Hermes Agent mock gateway to complete command: check system status",
      "riskTier": 1,
      "scope": ["mock_gateway_state"],
      "reason": "Exercise the v0.1 command + approval loop",
      "rollback": "No real side effects; local mock state only",
      "actions": ["approve_once", "reject", "explain"],
      "status": "pending",
      "createdAt": "2026-06-02T12:00:00Z"
    }
  ]
}
""".data(using: .utf8)!

let threadMessagesJSON = """
{
  "thread": {
    "id": "thread_abc",
    "title": "check system status",
    "lane": "hermes-agent",
    "createdAt": "2026-06-02T12:00:00Z",
    "updatedAt": "2026-06-02T12:01:00Z",
    "projectId": null
  },
  "messages": [
    {
      "id": "msg_abc",
      "threadId": "thread_abc",
      "role": "assistant",
      "kind": "approval_card",
      "body": "Approval required before completing mock command.",
      "card": {"approvalId": "approval_abc", "runId": "run_abc"},
      "createdAt": "2026-06-02T12:00:00Z"
    },
    {
      "id": "msg_result",
      "threadId": "thread_abc",
      "role": "assistant",
      "kind": "command_result",
      "body": "Mock command completed after approval.",
      "card": {"runId": "run_abc"},
      "createdAt": "2026-06-02T12:01:00Z"
    }
  ]
}
""".data(using: .utf8)!

let hermesCapabilitiesJSON = """
{
  "object": "hermes.api_server.capabilities",
  "platform": "hermes-agent",
  "model": "default",
  "auth": {"type": "bearer", "required": true},
  "runtime": {"mode": "server_agent", "tool_execution": "server", "split_runtime": false},
  "features": {"run_submission": true, "run_status": true, "run_approval_response": true},
  "endpoints": {
    "runs": {"method": "POST", "path": "/v1/runs"},
    "run_status": {"method": "GET", "path": "/v1/runs/{run_id}"},
    "run_approval": {"method": "POST", "path": "/v1/runs/{run_id}/approval"}
  }
}
""".data(using: .utf8)!

let hermesRunSubmissionJSON = """
{
  "run_id": "run_live_abc",
  "status": "started"
}
""".data(using: .utf8)!

let hermesRunStatusJSON = """
{
  "object": "hermes.run",
  "run_id": "run_live_abc",
  "status": "waiting_for_approval",
  "created_at": 1780401600.0,
  "updated_at": 1780401601.0,
  "session_id": "hermes-agent-ios",
  "model": "default",
  "last_event": "approval.request"
}
""".data(using: .utf8)!

let hermesApprovalResponseJSON = """
{
  "object": "hermes.run.approval_response",
  "run_id": "run_live_abc",
  "choice": "once",
  "resolved": 1
}
""".data(using: .utf8)!

let hermesCompletedRunStatusJSON = """
{
  "object": "hermes.run",
  "run_id": "run_live_abc",
  "status": "completed",
  "created_at": 1780401600.0,
  "updated_at": 1780401605.0,
  "session_id": "hermes-agent-ios",
  "model": "default",
  "last_event": "run.completed",
  "output": "done"
}
""".data(using: .utf8)!

let hermesRunEventsSSE = """
event: run.started
data: {"event":"run.started","run_id":"run_live_abc","timestamp":1780401600.0}

event: approval.request
data: {"event":"approval.request","run_id":"run_live_abc","timestamp":1780401601.5,"command":"rm -rf /tmp/hermes-agent-ios-smoke","description":"recursive delete command","risk_tier":3,"scope":["local_tmp_path","terminal_tool"],"reason":"Hermes needs permission before deleting a path","rollback":"Recreate the temporary directory if needed","pattern_key":"rm_rf","pattern_keys":["rm_rf"],"choices":["once","session","always","deny"]}

event: message.delta
data: {"event":"message.delta","run_id":"run_live_abc","timestamp":1780401601.0,"delta":"hello"}

event: run.completed
data: {"event":"run.completed","run_id":"run_live_abc","timestamp":1780401602.0,"output":"done"}

""".data(using: .utf8)!

let approvalDecisionJSON = """
{
  "approval": {
    "id": "approval_abc",
    "runId": "run_abc",
    "title": "Approve mock command",
    "description": "Allow Hermes Agent mock gateway to complete command: check system status",
    "riskTier": 1,
    "scope": ["mock_gateway_state"],
    "reason": "Exercise the v0.1 command + approval loop",
    "rollback": "No real side effects; local mock state only",
    "actions": ["approve_once", "reject", "explain"],
    "status": "approved",
    "createdAt": "2026-06-02T12:00:00Z"
  },
  "run": {
    "id": "run_abc",
    "threadId": "thread_abc",
    "title": "Mock Hermes command run",
    "lane": "hermes-agent",
    "status": "done",
    "currentStep": "Completed",
    "risk": "low",
    "startedAt": "2026-06-02T12:00:00Z",
    "updatedAt": "2026-06-02T12:01:00Z",
    "artifactIds": [],
    "approvalIds": ["approval_abc"]
  },
  "result": {
    "id": "msg_result",
    "threadId": "thread_abc",
    "role": "assistant",
    "kind": "command_result",
    "body": "Mock command completed after approval.",
    "card": {"runId": "run_abc"},
    "createdAt": "2026-06-02T12:01:00Z"
  }
}
""".data(using: .utf8)!

do {
    let command = try JSONDecoder.hermesAgentGateway.decode(CommandRunResponse.self, from: commandResponseJSON)
    expect(command.thread.title == "check system status", "thread should decode")
    expect(command.run.status == .waitingForApproval, "run status should decode")
    expect(command.approval.riskTier == 1, "approval risk tier should decode")
    expect(command.approval.scope == ["mock_gateway_state"], "approval scope should decode")

    let pending = try JSONDecoder.hermesAgentGateway.decode(PendingApprovalsResponse.self, from: pendingApprovalsJSON)
    expect(pending.approvals.count == 1, "pending approvals response should decode")
    expect(pending.approvals[0].status == .pending, "pending approval status should decode")

    let history = try JSONDecoder.hermesAgentGateway.decode(ThreadMessagesResponse.self, from: threadMessagesJSON)
    expect(history.thread.id == "thread_abc", "thread history should include thread metadata")
    expect(history.messages.map(\.kind) == ["approval_card", "command_result"], "thread history should preserve message order")

    let payload = CommandMessagePayload(text: "run smoke test")
    let encoded = try JSONEncoder.hermesAgentGateway.encode(payload)
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    expect(json?["text"] as? String == "run smoke test", "command payload text should encode")
    expect(json?["kind"] as? String == "command", "command payload kind should encode")

    let approvalEndpoint = GatewayEndpoint.approvalDecision(id: "approval_abc", decision: .approve)
    let approvalRequest = try approvalEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8787")!)
    expect(approvalRequest.httpMethod == "POST", "approval decision should be POST")
    expect(approvalRequest.url?.path == "/v0/approvals/approval_abc/approve", "approval decision path should match contract")
    expect(approvalRequest.value(forHTTPHeaderField: "Content-Type") == "application/json", "approval decision should set content type")
    expect(approvalRequest.httpBody == Data("{}".utf8), "approval decision should send empty JSON body")

    let pendingEndpoint = GatewayEndpoint.pendingApprovals
    let pendingRequest = try pendingEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8787")!)
    expect(pendingRequest.httpMethod == "GET", "pending approvals should be GET")
    expect(pendingRequest.url?.path == "/v0/approvals", "pending approvals path should match contract")
    expect(pendingRequest.httpBody == nil, "pending approvals should not send a body")

    let historyEndpoint = GatewayEndpoint.threadMessages(threadId: "thread_abc")
    let historyRequest = try historyEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8787")!)
    expect(historyRequest.httpMethod == "GET", "thread messages should be GET")
    expect(historyRequest.url?.path == "/v0/threads/thread_abc/messages", "thread messages path should match contract")

    let tokenPayload = NotificationTokenRegistrationPayload(deviceId: "iphone-local", enrolledDeveloperProgram: false)
    let tokenEndpoint = GatewayEndpoint.registerNotificationToken(tokenPayload)
    let tokenRequest = try tokenEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8787")!)
    expect(tokenRequest.httpMethod == "POST", "notification token registration should be POST")
    expect(tokenRequest.url?.path == "/v0/notification-tokens", "notification token registration path should be scaffolded")
    let tokenJSON = try JSONSerialization.jsonObject(with: tokenRequest.httpBody ?? Data()) as? [String: Any]
    expect(tokenJSON?["tokenRedacted"] as? String == "<redacted>", "notification registration must only carry redacted token state")
    expect(tokenJSON?["enrolledDeveloperProgram"] as? Bool == false, "Personal Team lane should explicitly mark Developer Program as absent")

    let readiness = NotificationReadinessState(enrollment: .personalTeam, localPermissionStatus: "authorized", hasRemoteDeviceToken: false, lastLocalNotificationAt: 1780477200.0)
    expect(readiness.apnsGateLabel.contains("Apple Developer Program enrollment required"), "Personal Team notification readiness should expose the APNs enrollment gate")
    expect(readiness.localNotificationLabel == "Local notifications: authorized", "local notification permission state should be operator-readable")

    let apnsPayload = APNsApprovalNotificationPayload(runId: "run_live_abc", approvalId: "approval_123", command: "Review terminal command")
    let apnsEncoded = try JSONEncoder.hermesAgentGateway.encode(apnsPayload)
    let apnsJSON = try JSONSerialization.jsonObject(with: apnsEncoded) as? [String: Any]
    let apsJSON = apnsJSON?["aps"] as? [String: Any]
    let alertJSON = apsJSON?["alert"] as? [String: Any]
    expect(alertJSON?["title"] as? String == "Hermes Agent approval required", "APNs approval payload should carry approval title")
    expect(apnsJSON?["route"] as? String == "hermes-agent-ios://approval/approval_123", "APNs payload should carry app route without secrets")
    expect(!String(data: apnsEncoded, encoding: .utf8)!.contains("secret"), "APNs payload skeleton must not include secrets")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "POST", "client should POST command")
        expect(request.url?.path == "/v0/messages", "client should hit create message endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
        return (response, commandResponseJSON)
    }
    let client = GatewayClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: mockedSession())
    let created = try await client.createCommand(text: "check system status")
    expect(created.approval.id == "approval_abc", "client should decode command response approval")
    expect(created.run.currentStep == "Awaiting approval", "client should decode run step")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "POST", "client should POST approval decision")
        expect(request.url?.path == "/v0/approvals/approval_abc/approve", "client should hit approval decision endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, approvalDecisionJSON)
    }
    let decision = try await client.decideApproval(id: "approval_abc", decision: .approve)
    expect(decision.approval.status == .approved, "client should decode approved status")
    expect(decision.run.status == .done, "client should decode completed run")
    expect(decision.result.body.contains("completed"), "client should decode result message")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "GET", "client should GET pending approvals")
        expect(request.url?.path == "/v0/approvals", "client should hit pending approvals endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, pendingApprovalsJSON)
    }
    let refreshedApprovals = try await client.fetchPendingApprovals()
    expect(refreshedApprovals.approvals.map(\.id) == ["approval_abc"], "client should decode refreshed pending approvals")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "GET", "client should GET thread messages")
        expect(request.url?.path == "/v0/threads/thread_abc/messages", "client should hit thread messages endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, threadMessagesJSON)
    }
    let refreshedHistory = try await client.fetchThreadMessages(threadId: "thread_abc")
    expect(refreshedHistory.messages.last?.kind == "command_result", "client should decode refreshed thread history")

    let capabilities = try JSONDecoder.hermesAgentGateway.decode(HermesAPICapabilities.self, from: hermesCapabilitiesJSON)
    expect(capabilities.platform == "hermes-agent", "Hermes capabilities should decode platform")
    expect(capabilities.features.runSubmission == true, "Hermes capabilities should expose run submission")
    expect(capabilities.endpoints.runs.path == "/v1/runs", "Hermes capabilities should decode run endpoint")

    let hermesRun = try JSONDecoder.hermesAgentGateway.decode(HermesRunSubmission.self, from: hermesRunSubmissionJSON)
    expect(hermesRun.runId == "run_live_abc", "Hermes run submission should decode run id")
    expect(hermesRun.status == "started", "Hermes run submission should decode status")

    let hermesStatus = try JSONDecoder.hermesAgentGateway.decode(HermesRunStatus.self, from: hermesRunStatusJSON)
    expect(hermesStatus.runId == "run_live_abc", "Hermes run status should decode run id")
    expect(hermesStatus.status == "waiting_for_approval", "Hermes run status should decode")
    expect(hermesStatus.lastEvent == "approval.request", "Hermes run last event should decode")

    let runCard = HermesRunCard(submission: hermesRun, title: "Check open projects")
    expect(runCard.id == "run_live_abc", "Hermes run card id should use run id")
    expect(runCard.title == "Check open projects", "Hermes run card should preserve submitted title")
    expect(runCard.status == "started", "Hermes run card should start from submission status")
    expect(!runCard.isTerminal, "submitted run card should be active")

    let waitingCard = runCard.updated(with: hermesStatus)
    expect(waitingCard.status == "waiting_for_approval", "Hermes run card should update from run status")
    expect(waitingCard.lastEvent == "approval.request", "Hermes run card should preserve last event")
    expect(waitingCard.isWaitingForApproval, "Hermes run card should expose waiting-for-approval state")
    expect(waitingCard.operatorStateLabel == "Waiting for iPhone approval", "Hermes run card should expose an operator waiting label")
    expect(waitingCard.operatorDetail.contains("approval"), "Hermes run card should explain approval wait state")
    expect(waitingCard.lastCheckedLabel == "Last checked: 2026-06-02 12:00:01 UTC", "Hermes run card should format last checked time")

    let fallbackCard = HermesRunCard(id: "run_live_fallback", title: "Fallback", status: "started", lastEvent: "SSE fallback active", updatedAt: 1780401601.0)
    expect(fallbackCard.operatorStateLabel == "Polling run status", "SSE fallback cards should expose polling affordance")
    expect(fallbackCard.operatorDetail.contains("SSE fallback active"), "SSE fallback cards should explain polling fallback")

    let completedStatus = try JSONDecoder.hermesAgentGateway.decode(HermesRunStatus.self, from: hermesCompletedRunStatusJSON)
    let completedCard = waitingCard.updated(with: completedStatus)
    expect(completedCard.status == "completed", "Hermes run card should update to completed")
    expect(completedCard.output == "done", "Hermes run card should preserve output")
    expect(completedCard.isTerminal, "completed run card should be terminal")

    let failedCard = HermesRunCard(id: "run_failed", title: "Broken run", status: "failed", lastEvent: "run.failed", error: "boom", updatedAt: 1780401603.0)
    let activeCard = HermesRunCard(id: "run_active", title: "Active run", status: "started", lastEvent: "run.started", updatedAt: 1780401602.0)
    let runHistory = [completedCard, waitingCard, failedCard, activeCard]
    expect(HermesRunCardFilter.all.label == "All", "All run filter should expose operator label")
    expect(HermesRunCardFilter.needsAttention.label == "Needs Attention", "Attention filter should expose operator label")
    expect(HermesRunCardFilter.active.label == "Active", "Active filter should expose operator label")
    expect(HermesRunCardFilter.completed.label == "Completed", "Completed filter should expose operator label")
    expect(HermesRunCardFilter.needsAttention.matches(waitingCard), "Waiting approval cards should need attention")
    expect(HermesRunCardFilter.needsAttention.matches(failedCard), "Failed cards should need attention")
    expect(!HermesRunCardFilter.needsAttention.matches(completedCard), "Completed cards should not need attention")
    expect(HermesRunCard.filteredAndPrioritized(runHistory, filter: .needsAttention).map(\.id) == ["run_failed", "run_live_abc"], "Attention filter should show failed/waiting cards newest first")
    expect(HermesRunCard.filteredAndPrioritized(runHistory, filter: .active).map(\.id) == ["run_active", "run_live_abc"], "Active filter should include active and waiting cards newest first")
    expect(HermesRunCard.filteredAndPrioritized(runHistory, filter: .completed).map(\.id) == ["run_live_abc"], "Completed filter should include terminal success only")
    expect(HermesRunCard.operatorSummary(cards: runHistory, visible: [failedCard, waitingCard]) == "Showing 2 of 4 · Attention first", "Run cockpit summary should explain filtered history")

    let encodedRunCards = try JSONEncoder.hermesAgentGateway.encode([completedCard])
    let decodedRunCards = try JSONDecoder.hermesAgentGateway.decode([HermesRunCard].self, from: encodedRunCards)
    expect(decodedRunCards == [completedCard], "Hermes run cards should round-trip for local cockpit persistence")

    let decodedHermesApproval = try JSONDecoder.hermesAgentGateway.decode(HermesApprovalResolution.self, from: hermesApprovalResponseJSON)
    expect(decodedHermesApproval.choice == .once, "Hermes approval response should decode choice")
    expect(decodedHermesApproval.resolved == 1, "Hermes approval response should decode resolved count")

    let hermesRunEndpoint = HermesAPIEndpoint.submitRun(input: "check status", sessionId: "hermes-agent-ios")
    let hermesRunRequest = try hermesRunEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8642")!, bearerToken: "test-token")
    expect(hermesRunRequest.httpMethod == "POST", "Hermes run submission should be POST")
    expect(hermesRunRequest.url?.path == "/v1/runs", "Hermes run submission should hit /v1/runs")
    expect(hermesRunRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "Hermes API requests should attach bearer token when provided")
    let hermesRunBody = try JSONSerialization.jsonObject(with: hermesRunRequest.httpBody ?? Data()) as? [String: Any]
    expect(hermesRunBody?["input"] as? String == "check status", "Hermes run body should include input")
    expect(hermesRunBody?["session_id"] as? String == "hermes-agent-ios", "Hermes run body should include session id")

    expect(HermesLiveSmoke.commandPrompt == "Reply exactly: HERMES_AGENT_IOS_LIVE_SMOKE_OK", "Command smoke prompt should remain deterministic")
    expect(HermesLiveSmoke.approvalSentinel == "HERMES_AGENT_IOS_APPROVAL_SMOKE_OK", "Approval smoke sentinel should be explicit")
    expect(HermesLiveSmoke.approvalCommand == "rm -rf /tmp/hermes-agent-ios-approval-smoke", "Approval smoke should use a known low-impact dangerous command")
    expect(HermesLiveSmoke.approvalPrompt.contains(HermesLiveSmoke.approvalCommand), "Approval smoke prompt should ask Hermes to execute the approval-gated command")
    expect(HermesLiveSmoke.approvalPrompt.contains(HermesLiveSmoke.approvalSentinel), "Approval smoke prompt should require a deterministic final sentinel")
    expect(HermesLiveSmoke.approvalCard.runId == "pending", "Approval smoke fallback card should have a placeholder run id")
    expect(HermesLiveSmoke.approvalCard.command == HermesLiveSmoke.approvalCommand, "Approval smoke fallback card should expose the known command")
    expect(HermesLiveSmoke.approvalCard.riskTier == 1, "Approval smoke fallback card should expose low risk tier")
    expect(HermesLiveSmoke.approvalCard.scope == ["/tmp/hermes-agent-ios-approval-smoke"], "Approval smoke fallback card should expose scoped path")
    expect(HermesLiveSmoke.approvalCard.rollback.contains("No production"), "Approval smoke fallback card should expose rollback guidance")
    expect(HermesLiveSmoke.approvalCard.choices == [.once, .deny], "Approval smoke fallback card should keep approval choices conservative")

    let hermesApprovalEndpoint = HermesAPIEndpoint.resolveApproval(runId: "run_live_abc", choice: .once)
    let hermesApprovalRequest = try hermesApprovalEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8642")!, bearerToken: nil)
    expect(hermesApprovalRequest.httpMethod == "POST", "Hermes approval resolution should be POST")
    expect(hermesApprovalRequest.url?.path == "/v1/runs/run_live_abc/approval", "Hermes approval path should match API server")
    let hermesApprovalBody = try JSONSerialization.jsonObject(with: hermesApprovalRequest.httpBody ?? Data()) as? [String: Any]
    expect(hermesApprovalBody?["choice"] as? String == "once", "Hermes approval body should encode choice")

    let hermesEventsEndpoint = HermesAPIEndpoint.runEvents(runId: "run_live_abc")
    let hermesEventsRequest = try hermesEventsEndpoint.urlRequest(baseURL: URL(string: "http://127.0.0.1:8642")!, bearerToken: "test-token")
    expect(hermesEventsRequest.httpMethod == "GET", "Hermes run events should be GET")
    expect(hermesEventsRequest.url?.path == "/v1/runs/run_live_abc/events", "Hermes run events path should match API server")
    expect(hermesEventsRequest.value(forHTTPHeaderField: "Accept") == "text/event-stream", "Hermes run events should request SSE")

    let parsedHermesEvents = try HermesRunEvent.parseSSEEvents(from: hermesRunEventsSSE)
    expect(parsedHermesEvents.map(\.event) == ["run.started", "approval.request", "message.delta", "run.completed"], "Hermes SSE parser should preserve event order")
    expect(parsedHermesEvents[1].command == "rm -rf /tmp/hermes-agent-ios-smoke", "Hermes SSE parser should decode approval command")
    expect(parsedHermesEvents[1].description == "recursive delete command", "Hermes SSE parser should decode approval description")
    expect(parsedHermesEvents[1].riskTier == 3, "Hermes SSE parser should decode approval risk tier")
    expect(parsedHermesEvents[1].scope == ["local_tmp_path", "terminal_tool"], "Hermes SSE parser should decode approval scope")
    expect(parsedHermesEvents[1].reason == "Hermes needs permission before deleting a path", "Hermes SSE parser should decode approval reason")
    expect(parsedHermesEvents[1].rollback == "Recreate the temporary directory if needed", "Hermes SSE parser should decode approval rollback")
    expect(parsedHermesEvents[1].patternKeys == ["rm_rf"], "Hermes SSE parser should decode approval pattern keys")
    expect(parsedHermesEvents[2].delta == "hello", "Hermes SSE parser should decode message delta")
    expect(parsedHermesEvents[3].output == "done", "Hermes SSE parser should decode completion output")

    let approvalCards = HermesApprovalCard.cards(from: parsedHermesEvents)
    expect(approvalCards.count == 1, "Hermes approval cards should derive from approval.request events")
    expect(approvalCards[0].id == "run_live_abc:rm_rf", "Hermes approval card should have stable id from run and pattern")
    expect(approvalCards[0].title == "Approval required", "Hermes approval card should expose operator title")
    expect(approvalCards[0].command == "rm -rf /tmp/hermes-agent-ios-smoke", "Hermes approval card should expose command")
    expect(approvalCards[0].riskTier == 3, "Hermes approval card should expose risk tier")
    expect(approvalCards[0].scope == ["local_tmp_path", "terminal_tool"], "Hermes approval card should expose scope")
    expect(approvalCards[0].reason == "Hermes needs permission before deleting a path", "Hermes approval card should explain why it is waiting")
    expect(approvalCards[0].rollback == "Recreate the temporary directory if needed", "Hermes approval card should expose rollback guidance")
    expect(approvalCards[0].riskLabel == "Risk tier 3", "Hermes approval card should provide an operator risk label")
    expect(approvalCards[0].choices == [.once, .session, .always, .deny], "Hermes approval card should expose typed approval choices")

    let auditEntry = HermesApprovalAuditEntry(card: approvalCards[0], choice: .once, resolvedAt: 1780476600.0, outcomeStatus: "completed", outcomeOutput: "done")
    expect(auditEntry.id == "run_live_abc:rm_rf:once:1780476600", "Approval audit entry should have a stable decision id")
    expect(auditEntry.decisionLabel == "Decision: approve once", "Approval audit entry should label the operator choice")
    expect(auditEntry.contextSummary.contains("Risk tier 3"), "Approval audit entry should summarize risk context")
    expect(auditEntry.contextSummary.contains("local_tmp_path"), "Approval audit entry should summarize scope context")
    expect(auditEntry.resultSummary == "Outcome: completed · done", "Approval audit entry should summarize the run outcome")
    expect(auditEntry.resolvedAtLabel == "Resolved at: 2026-06-03 08:50:00 UTC", "Approval audit entry should format resolution time")
    let encodedAudit = try JSONEncoder.hermesAgentGateway.encode([auditEntry])
    let decodedAudit = try JSONDecoder.hermesAgentGateway.decode([HermesApprovalAuditEntry].self, from: encodedAudit)
    expect(decodedAudit == [auditEntry], "Approval audit entries should persist through JSON round-trip")

    let operatorLog = HermesOperatorLogEntry(category: .approvalDecision, title: "Approval decision", detail: "Approved run run_live_abc", timestamp: 1780476900.0, runId: "run_live_abc")
    expect(operatorLog.id == "approvalDecision:run_live_abc:1780476900", "Operator log should have stable category/run/timestamp id")
    expect(operatorLog.categoryLabel == "Approval decision", "Operator log should label approval decisions")
    expect(operatorLog.detailLabel == "Approved run run_live_abc", "Operator log should expose detail text")
    expect(operatorLog.timestampLabel == "2026-06-03 08:55:00 UTC", "Operator log should format timestamps")
    let encodedOperatorLog = try JSONEncoder.hermesAgentGateway.encode([operatorLog])
    let decodedOperatorLog = try JSONDecoder.hermesAgentGateway.decode([HermesOperatorLogEntry].self, from: encodedOperatorLog)
    expect(decodedOperatorLog == [operatorLog], "Operator debug log should persist through JSON round-trip")

    let timeline = HermesOperatorTimelineItem.makeTimeline(audits: [auditEntry], logs: [operatorLog])
    expect(timeline.map(\.kindLabel) == ["Debug", "Approval"], "Operator timeline should merge and sort debug/audit events newest first")
    expect(HermesOperatorTimelineFilter.all.label == "All", "Timeline all filter should expose label")
    expect(HermesOperatorTimelineFilter.approvals.label == "Approvals", "Timeline approvals filter should expose label")
    expect(HermesOperatorTimelineFilter.debug.label == "Debug", "Timeline debug filter should expose label")
    expect(HermesOperatorTimelineItem.filteredTimeline(timeline, filter: .approvals).map(\.id) == [auditEntry.id], "Timeline approvals filter should include only audit entries")
    expect(HermesOperatorTimelineItem.filteredTimeline(timeline, filter: .debug).map(\.id) == [operatorLog.id], "Timeline debug filter should include only operator log entries")
    expect(HermesOperatorTimelineItem.timelineSummary(all: timeline, visible: [timeline[0]]) == "Showing 1 of 2 timeline events", "Timeline summary should explain filtered event count")

    let approvalTimelineDetail = HermesOperatorTimelineDetail(item: timeline[1])
    expect(approvalTimelineDetail.replayTitle == "Replay context: Approval", "Timeline approval detail should identify replay context")
    expect(approvalTimelineDetail.contextDetail.contains("Risk tier 3"), "Timeline approval detail should preserve approval context")
    expect(approvalTimelineDetail.outcomeDetail.contains("Outcome: completed"), "Timeline approval detail should preserve outcome")

    let debugTimelineDetail = HermesOperatorTimelineDetail(item: timeline[0])
    expect(debugTimelineDetail.replayTitle == "Replay context: Debug", "Timeline debug detail should identify debug context")
    expect(debugTimelineDetail.contextDetail == "Approved run run_live_abc", "Timeline debug detail should expose log detail")
    expect(debugTimelineDetail.outcomeDetail == "No outcome attached", "Timeline debug detail should avoid inventing outcomes")

    let timelineExport = HermesOperatorTimelineExport(items: timeline)
    expect(timelineExport.markdownSnapshot.contains("# Hermes Agent Operator Timeline"), "Timeline export should include a markdown title")
    expect(timelineExport.markdownSnapshot.contains("Approval decision"), "Timeline export should include debug titles")
    expect(timelineExport.markdownSnapshot.contains("Decision: approve once"), "Timeline export should include approval decisions")
    expect(timelineExport.markdownSnapshot.contains("Run ID: run_live_abc"), "Timeline export should include run ids")
    expect(!timelineExport.markdownSnapshot.contains("secret-token"), "Timeline export must not expose bearer tokens")

    let liveSnapshot = HermesAgentLiveActivitySnapshot(runId: "run_live_abc", title: "Check system status", state: .waitingForApproval, detail: HermesAgentLiveActivityState.waitingForApproval.defaultDetail, updatedAt: 1780477200.0)
    expect(liveSnapshot.statusLabel == "Approval Required", "Live Activity snapshot should expose operator status label")
    expect(liveSnapshot.dynamicIslandCompactLabel == "APPROVE", "Dynamic Island compact label should make approvals obvious")
    expect(liveSnapshot.dynamicIslandCompactLeadingLabel == "AN", "Dynamic Island compact leading label should be short enough to render in the island")
    expect(liveSnapshot.dynamicIslandCompactTrailingLabel == "OK?", "Dynamic Island compact trailing label should fit the compact island approval slot")
    expect(liveSnapshot.dynamicIslandMinimalSymbolName == "hand.raised.circle.fill", "Dynamic Island minimal symbol should reflect attention state")
    expect(liveSnapshot.detail.contains("Paused for approval"), "Live Activity waiting copy should explain the approval gate")
    expect(!HermesAgentLiveActivityState.waitingForApproval.shouldEndLiveActivityAfterUpdate, "Waiting approvals should keep the Live Activity visible")
    expect(HermesAgentLiveActivityState.completed.defaultDetail.contains("Approved and completed"), "Completed Live Activity copy should confirm approval completion")
    expect(HermesAgentLiveActivityState.failed.defaultDetail.contains("Run failed"), "Failed Live Activity copy should direct inspection")
    expect(HermesAgentLiveActivityState.completed.shouldEndLiveActivityAfterUpdate, "Completed Live Activities should end after their final update")
    expect(HermesAgentLiveActivityState.failed.shouldEndLiveActivityAfterUpdate, "Failed Live Activities should end after their final update")
    expect(liveSnapshot.stalenessLabel == "Updated 2026-06-03 09:00:00 UTC", "Live Activity snapshot should format update timestamp")
    let completedLiveSnapshot = HermesAgentLiveActivitySnapshot(card: completedCard)
    expect(completedLiveSnapshot.statusLabel == "Approved · Done", "Completed run cards should produce approved/done Live Activity copy")
    expect(completedLiveSnapshot.detail.contains("Approved and completed"), "Completed Live Activity detail should confirm the approval path completed")
    let failedLiveSnapshot = HermesAgentLiveActivitySnapshot(card: failedCard)
    expect(failedLiveSnapshot.dynamicIslandCompactLabel == "FAILED", "Failed Live Activity compact copy should be explicit")
    expect(failedLiveSnapshot.dynamicIslandCompactTrailingLabel == "ERR", "Failed compact island copy should fit in the island")
    expect(failedLiveSnapshot.detail.contains("boom"), "Failed Live Activity detail should preserve the error")
    let encodedLiveSnapshot = try JSONEncoder.hermesAgentGateway.encode(liveSnapshot)
    let decodedLiveSnapshot = try JSONDecoder.hermesAgentGateway.decode(HermesAgentLiveActivitySnapshot.self, from: encodedLiveSnapshot)
    expect(decodedLiveSnapshot == liveSnapshot, "Live Activity snapshot should persist through JSON round-trip")

    let bootstrapURL = HermesDeviceBootstrapLink.url(
        baseURL: URL(string: "https://hermes-host.example:8642")!,
        bearerToken: "secret-token",
        gatewayRemoteBaseURL: URL(string: "https://hermes-host.example:9119")!,
        gatewayWebSocketToken: "gateway-secret-token"
    )
    expect(bootstrapURL?.scheme == "hermes-agent-ios", "Physical-device bootstrap link should use Hermes Agent URL scheme")
    expect(bootstrapURL?.host == "hermes-api", "Physical-device bootstrap link should target Hermes API settings")
    let parsedBootstrap = HermesDeviceBootstrapLink.parse(bootstrapURL!)
    expect(parsedBootstrap?.baseURL == URL(string: "https://hermes-host.example:8642")!, "Bootstrap link should carry the live Hermes API base URL")
    expect(parsedBootstrap?.bearerToken == "secret-token", "Bootstrap link should carry bearer token for app storage without manual copying")
    expect(parsedBootstrap?.gatewayRemoteBaseURL == URL(string: "https://hermes-host.example:9119")!, "Bootstrap link should carry the Hermes dashboard gateway base URL")
    expect(parsedBootstrap?.gatewayWebSocketToken == "gateway-secret-token", "Bootstrap link should carry the Hermes gateway WebSocket token for chat runtime")
    expect(parsedBootstrap?.redactedTokenSummary == "Bearer token configured (<redacted>)", "Bootstrap status must not expose token value")
    expect(parsedBootstrap?.redactedGatewayTokenSummary == "Gateway token configured (<redacted>)", "Gateway bootstrap status must not expose token value")
    expect(HermesDeviceBootstrapLink.parse(URL(string: "https://example.com/?base_url=http://bad&token=x")!) == nil, "Bootstrap parser should reject non-Hermes Agent URL schemes")

    let missingDiagnostics = HermesDeviceDiagnostics(baseURL: URL(string: "http://10.0.0.20:8642")!, hasBearerToken: false, lastCapabilityCheckAt: nil, isWirelessHandoff: true)
    expect(missingDiagnostics.apiURLLabel == "Current API URL: http://10.0.0.20:8642", "Diagnostics should expose the current device-facing API URL")
    expect(missingDiagnostics.tokenStateLabel == "Token: missing", "Diagnostics should explain missing token without exposing secrets")
    expect(missingDiagnostics.capabilityCheckLabel == "Last capability check: not yet", "Diagnostics should expose empty capability-check state")
    expect(missingDiagnostics.handoffStateLabel == "Wi‑Fi/CoreDevice: wireless handoff ready", "Diagnostics should expose wireless handoff state")

    let checkedDiagnostics = HermesDeviceDiagnostics(baseURL: URL(string: "http://10.0.0.20:8642")!, hasBearerToken: true, lastCapabilityCheckAt: 1780476000.0, isWirelessHandoff: true)
    expect(checkedDiagnostics.tokenStateLabel == "Token: configured (<redacted>)", "Diagnostics must redact configured token state")
    expect(checkedDiagnostics.capabilityCheckLabel == "Last capability check: 2026-06-03 08:40:00 UTC", "Diagnostics should format capability-check time")

    let askRoute = HermesAgentAppIntentRoute.askHermesAgent(prompt: " brief me ")
    expect(askRoute.kind == .askHermesAgent, "Ask Hermes Agent route should preserve kind")
    expect(askRoute.prompt == "brief me", "Ask Hermes Agent route should trim prompt")
    expect(askRoute.storageValue.contains("hermes-agent-intent://askHermesAgent"), "App Intent route should use a non-secret route scheme")
    expect(HermesAgentAppIntentRoute.parse(askRoute.storageValue) == askRoute, "App Intent route should round-trip through storage")
    expect(askRoute.operatorLabel == "Ask Hermes Agent: brief me", "Ask route should expose operator label")
    expect(askRoute.confirmationDialog.contains("Opening Hermes Agent"), "Ask route should expose shortcut dialog copy")
    expect(askRoute.isSecretSafeForDisplay, "App Intent routes should be safe to acknowledge")
    expect(HermesAgentAppIntentKind.allCases.map(\.title) == ["Ask Hermes Agent", "Run Live Smoke", "Open Needs Attention", "Check Hermes Capability"], "App Intent kinds should define the v0 shortcut set")
    expect(HermesAgentAppIntentRoute.runLiveSmoke.operatorLabel == "Open live Hermes smoke action", "Live smoke route should identify target")
    expect(HermesAgentAppIntentRoute.openNeedsAttention.kind == .openNeedsAttention, "Needs Attention route should be available")
    expect(HermesAgentAppIntentRoute.checkHermesCapability.kind == .checkHermesCapability, "Hermes capability route should be available")
    expect(HermesAgentAppIntentRoute.parse("hermes-agent-intent://askHermesAgent?token=secret") == nil, "Route parser should reject secret-like query keys")

    let sharePayload = HermesAgentSharePayload(text: " useful article ", url: URL(string: "https://example.com/post")!, title: " Signal ")
    expect(sharePayload.text == "useful article", "Share payload should trim shared text")
    expect(sharePayload.title == "Signal", "Share payload should trim shared title")
    expect(sharePayload.handoffURL?.absoluteString.contains("hermes-agent-ios://share") == true, "Share payload should use the app URL scheme")
    expect(HermesAgentSharePayload.parse(sharePayload.handoffURL!) == sharePayload, "Share payload should round-trip through handoff URL")
    expect(sharePayload.operatorLabel == "Shared: Signal", "Share payload should expose redaction-safe operator label")
    expect(sharePayload.commandPrompt.contains("Review this shared item"), "Share payload should create Hermes Agent command prompt")
    expect(sharePayload.commandPrompt.contains("https://example.com/post"), "Share payload prompt should preserve URL")
    expect(sharePayload.isSecretSafeForChrome, "Share payload handoff chrome should be safe for display")
    expect(HermesAgentSharePayload.parse(URL(string: "hermes-agent-ios://share?token=secret")!) == nil, "Share payload parser should reject secret-like query keys")
    expect(HermesAgentSharePayload.parse(URL(string: "hermes-agent-ios://share?url=file:///tmp/secret")!) == nil, "Share payload parser should reject non-web URLs")

    var incrementalBuffer = HermesSSEEventBuffer()
    var incrementalEvents: [HermesRunEvent] = []
    for line in String(data: hermesRunEventsSSE, encoding: .utf8)!.split(separator: "\n", omittingEmptySubsequences: false) {
        if let event = try incrementalBuffer.appendLine(String(line)) {
            incrementalEvents.append(event)
        }
    }
    if let event = try incrementalBuffer.finish() {
        incrementalEvents.append(event)
    }
    expect(incrementalEvents.map(\.event) == parsedHermesEvents.map(\.event), "Incremental SSE buffer should emit the same event order as batch parser")
    expect(incrementalEvents[1].command == "rm -rf /tmp/hermes-agent-ios-smoke", "Incremental SSE buffer should emit approval.request before stream completion")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "GET", "Hermes client should GET capabilities")
        expect(request.url?.path == "/v1/capabilities", "Hermes client should hit capabilities endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, hermesCapabilitiesJSON)
    }
    let hermesClient = HermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8642")!, bearerToken: "test-token", session: mockedSession())
    let fetchedCapabilities = try await hermesClient.fetchCapabilities()
    expect(fetchedCapabilities.features.runApprovalResponse == true, "Hermes client should decode capabilities")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "POST", "Hermes client should POST run")
        expect(request.url?.path == "/v1/runs", "Hermes client should hit run endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        return (response, hermesRunSubmissionJSON)
    }
    let submittedHermesRun = try await hermesClient.submitRun(input: "check status", sessionId: "hermes-agent-ios")
    expect(submittedHermesRun.runId == "run_live_abc", "Hermes client should decode submitted run")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "GET", "Hermes client should GET run status")
        expect(request.url?.path == "/v1/runs/run_live_abc", "Hermes client should hit run status endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, hermesRunStatusJSON)
    }
    let fetchedHermesStatus = try await hermesClient.fetchRunStatus(runId: "run_live_abc")
    expect(fetchedHermesStatus.status == "waiting_for_approval", "Hermes client should decode run status")

    MockURLProtocol.requestHandler = { request in
        expect(request.httpMethod == "POST", "Hermes client should POST approval choice")
        expect(request.url?.path == "/v1/runs/run_live_abc/approval", "Hermes client should hit approval resolution endpoint")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, hermesApprovalResponseJSON)
    }
    let hermesApproval = try await hermesClient.resolveApproval(runId: "run_live_abc", choice: .once)
    expect(hermesApproval.resolved == 1, "Hermes client should decode approval resolution")

    let startedAt = Date(timeIntervalSince1970: 100)
    let completedAt = Date(timeIntervalSince1970: 100.442)
    var runtimeState = HermesChatRuntimeState()
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "message.start"), now: startedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "tool.start", payload: ["tool_id": "patch-1", "name": "Patch"]), now: startedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "tool.complete", payload: ["tool_id": "patch-1", "name": "Patch"]), now: Date(timeIntervalSince1970: 100.234))
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "tool.start", payload: ["tool_id": "skill-1", "name": "Skill View"]), now: Date(timeIntervalSince1970: 100.300))
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "tool.complete", payload: ["tool_id": "skill-1", "name": "Skill View"]), now: Date(timeIntervalSince1970: 100.328))
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "reasoning.delta", payload: ["text": "(¬_¬) formulating..."]), now: Date(timeIntervalSince1970: 100.350))
    expect(runtimeState.assistantText.isEmpty, "Hermes chat reducer should not render reasoning/thinking deltas as assistant message text")
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "message.delta", payload: ["text": "Done"]), now: completedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "approval.request", sessionId: "session_abc", payload: ["request_id": "approval-1", "command": "rm -rf /tmp/hermes-agent-ios-smoke", "risk_tier": "3", "reason": "needs approval", "choices": "once,deny"]), now: completedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "clarify.request", payload: ["request_id": "clarify-1", "question": "Which project?", "choices": "Hermes Agent iOS, Hermes"]), now: completedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "sudo.request", payload: ["request_id": "sudo-1"]), now: completedAt)
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "secret.request", payload: ["request_id": "secret-1", "env_var": "TEST_SECRET", "prompt": "Enter token"]), now: completedAt)
    expect(runtimeState.blockingRequests.map(\.kind) == [.approval, .clarify, .sudo, .secret], "Hermes chat reducer should promote blocking request events into inline cards")
    expect(runtimeState.blockingRequests[0].choices == ["once", "deny"], "Approval blocking card should preserve choices")
    expect(runtimeState.blockingRequests[0].detailRows.contains("Reason: needs approval"), "Approval blocking card should expose reason context")
    expect(runtimeState.blockingRequests[1].prompt == "Which project?", "Clarify blocking card should expose question prompt")
    expect(runtimeState.blockingRequests[3].detailRows.contains("Variable: TEST_SECRET"), "Secret blocking card should expose variable label without value")
    runtimeState = HermesChatRuntimeReducer.reduce(runtimeState, event: HermesGatewayEvent(type: "response.complete", payload: ["text": "Done"]), now: completedAt)
    expect(runtimeState.assistantText == "Done", "Hermes chat reducer should accumulate and complete assistant text")
    expect(runtimeState.toolGroup?.stepCount == 2, "Hermes chat reducer should group tool actions")
    expect(runtimeState.toolGroup?.summaryLabel.hasPrefix("Tool actions — 2 steps — ") == true, "Hermes chat reducer should render desktop-style tool action summary")
    expect(runtimeState.toolGroup?.summaryLabel.hasSuffix("ms") == true, "Hermes chat reducer should include tool action duration")
    expect(runtimeState.toolGroup?.actions.first?.durationLabel.hasSuffix("ms") == true, "Hermes chat reducer should preserve individual tool durations")

    let remoteSessionList = HermesGatewayRPCClient.parseSessionListResult([
        "sessions": [
            [
                "session_id": "stored-alpha",
                "title": "Remote Alpha",
                "message_count": 3,
                "last_active": 1_780_000_001.0
            ],
            [
                "stored_session_id": "stored-beta",
                "messages": [["role": "user", "content": "one"], ["role": "assistant", "content": "two"]],
                "created_at": 1_780_000_002.0
            ],
            ["title": "missing id should drop"]
        ]
    ])
    expect(remoteSessionList.map(\.id) == ["stored-alpha", "stored-beta"], "session.list parser should accept id aliases and drop rows without an id")
    expect(remoteSessionList[0].title == "Remote Alpha", "session.list parser should preserve titles")
    expect(remoteSessionList[0].displayIdentity == "Remote Alpha", "remote session identity should prefer safe titles")
    expect(remoteSessionList[0].messageCount == 3, "session.list parser should preserve message_count")
    expect(remoteSessionList[0].updatedAt == 1_780_000_001.0, "session.list parser should accept last_active timestamp alias")
    expect(remoteSessionList[1].messageCount == 2, "session.list parser should fall back to messages count")
    expect(HermesRemoteSessionSummary(id: "stored-secret-title", title: "wss://hermes-host.example/api/ws?token=secret", messageCount: 1, updatedAt: 0).displayIdentity == "stored-s…", "remote session identity should fall back when title looks tokenized")
    expect(remoteSessionList[1].updatedAt == 1_780_000_002.0, "session.list parser should accept created_at timestamp alias")

    let remoteResume = try HermesGatewayRPCClient.parseSessionResumeResult([
        "session_id": "runtime-abc",
        "session_key": "stored-from-alias",
        "messages": [
            ["id": "msg-user", "role": "user", "body": "hello from body"],
            ["role": "assistant", "text": "hello from text"],
            ["id": "msg-parts", "role": "assistant", "content": [["type": "text", "text": "first"], ["type": "image_url"], ["type": "input_audio"]]],
            ["id": "msg-object", "role": "assistant", "content": ["type": "tool_result"]],
            ["id": "msg-empty", "role": "assistant", "content": "   "],
            ["id": "msg-missing-role", "content": "ignored"]
        ]
    ], fallbackStoredSessionId: "fallback-stored")
    expect(remoteResume.sessionId == "runtime-abc", "session.resume parser should require and preserve runtime session id")
    expect(remoteResume.storedSessionId == "stored-from-alias", "session.resume parser should accept stored id aliases")
    expect(remoteResume.messages.map(\.id) == ["msg-user", "stored-from-alias-msg-1", "msg-parts", "msg-object"], "session.resume parser should generate fallback ids and filter invalid messages")
    expect(remoteResume.messages.map(\.content) == ["hello from body", "hello from text", "first\n[image]\n[audio]", "[tool_result]"], "session.resume parser should accept content aliases and degrade structured content to placeholders")

    do {
        _ = try HermesGatewayRPCClient.parseSessionResumeResult(["messages": []], fallbackStoredSessionId: "fallback-stored")
        expect(false, "session.resume parser should reject missing runtime session id")
    } catch HermesGatewayRPCError.missingSessionId {
        // Expected.
    }

    let remoteBaseURL = try HermesGatewayRemoteConnection.normalizeBaseURL("https://hermes-host.example:9119/")
    expect(remoteBaseURL.absoluteString == "https://hermes-host.example:9119", "Remote gateway base URL should normalize like Hermes Desktop")
    let remoteWSURL = try HermesGatewayRemoteConnection.webSocketURL(baseURL: remoteBaseURL, sessionToken: "stable-session-token")
    expect(remoteWSURL.absoluteString == "wss://hermes-host.example:9119/api/ws?token=stable-session-token", "Remote gateway should build Desktop-style token WS URL")
    let encodedTokenURL = try HermesGatewayRemoteConnection.webSocketURL(baseURL: remoteBaseURL, sessionToken: "plus+and=equals")
    expect(encodedTokenURL.absoluteString.contains("token=plus%2Band%3Dequals"), "Remote gateway should percent-encode token query values like browser/Desktop clients")
    let prefixedBaseURL = try HermesGatewayRemoteConnection.normalizeBaseURL("http://hermes-host.local:9119/hermes")
    let prefixedWSURL = try HermesGatewayRemoteConnection.webSocketURL(baseURL: prefixedBaseURL, sessionToken: "abc 123")
    expect(prefixedWSURL.absoluteString.contains("/hermes/api/ws?token="), "Remote gateway should preserve dashboard path prefixes")

    let parsedEvent = HermesGatewayRPCClient.parseEventFrame("""
    {"jsonrpc":"2.0","method":"event","params":{"type":"tool.complete","session_id":"session_abc","payload":{"tool_id":"skill-1","name":"Skill View","duration_ms":28}}}
    """)
    expect(parsedEvent?.type == "tool.complete", "Hermes gateway should parse JSON-RPC event frames")
    expect(parsedEvent?.sessionId == "session_abc", "Hermes gateway should preserve event session id")
    expect(parsedEvent?.toolName == "Skill View", "Hermes gateway should flatten event payload tool name")
    expect(parsedEvent?.payload["duration_ms"] == "28", "Hermes gateway should stringify numeric payload fields")

    print("OK HermesAgentCore contract tests passed")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
