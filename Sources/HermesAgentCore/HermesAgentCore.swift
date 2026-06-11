import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

public struct GatewayThread: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let lane: String
    public let createdAt: Date
    public let updatedAt: Date
    public let projectId: String?
}

public struct GatewayMessage: Codable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let role: String
    public let kind: String
    public let body: String
    public let card: [String: String]
    public let createdAt: Date
}

public struct GatewayRun: Codable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let title: String
    public let lane: String
    public let status: RunStatus
    public let currentStep: String
    public let risk: String
    public let startedAt: Date
    public let updatedAt: Date
    public let artifactIds: [String]
    public let approvalIds: [String]
}

public enum RunStatus: String, Codable, Sendable {
    case waitingForApproval = "waiting_for_approval"
    case done
    case cancelled
}

public struct ApprovalRequest: Codable, Equatable, Sendable {
    public let id: String
    public let runId: String
    public let title: String
    public let description: String
    public let riskTier: Int
    public let scope: [String]
    public let reason: String
    public let rollback: String
    public let actions: [String]
    public let status: ApprovalStatus
    public let createdAt: Date
}

public enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
}

public struct CommandRunResponse: Codable, Equatable, Sendable {
    public let thread: GatewayThread
    public let message: GatewayMessage
    public let run: GatewayRun
    public let approval: ApprovalRequest
}

public struct ApprovalDecisionResponse: Codable, Equatable, Sendable {
    public let approval: ApprovalRequest
    public let run: GatewayRun
    public let result: GatewayMessage
}

public struct PendingApprovalsResponse: Codable, Equatable, Sendable {
    public let approvals: [ApprovalRequest]
}

public struct ThreadMessagesResponse: Codable, Equatable, Sendable {
    public let thread: GatewayThread
    public let messages: [GatewayMessage]
}

public struct CommandMessagePayload: Encodable, Equatable, Sendable {
    public let kind = "command"
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum NotificationEnrollmentState: String, Codable, Equatable, Sendable {
    case personalTeam
    case developerProgramRequired
    case developerProgramReady

    public var operatorLabel: String {
        switch self {
        case .personalTeam:
            return "Personal Team · APNs gated"
        case .developerProgramRequired:
            return "Apple Developer Program required"
        case .developerProgramReady:
            return "Developer Program ready"
        }
    }
}

public struct NotificationReadinessState: Codable, Equatable, Sendable {
    public let enrollment: NotificationEnrollmentState
    public let localPermissionStatus: String
    public let hasRemoteDeviceToken: Bool
    public let lastLocalNotificationAt: Double?

    public init(enrollment: NotificationEnrollmentState, localPermissionStatus: String, hasRemoteDeviceToken: Bool, lastLocalNotificationAt: Double?) {
        self.enrollment = enrollment
        self.localPermissionStatus = localPermissionStatus
        self.hasRemoteDeviceToken = hasRemoteDeviceToken
        self.lastLocalNotificationAt = lastLocalNotificationAt
    }

    public var apnsGateLabel: String {
        switch enrollment {
        case .personalTeam, .developerProgramRequired:
            return "Push notifications unavailable — Apple Developer Program enrollment required"
        case .developerProgramReady:
            return hasRemoteDeviceToken ? "APNs device token captured (<redacted>)" : "APNs ready — waiting for device token"
        }
    }

    public var localNotificationLabel: String {
        "Local notifications: \(localPermissionStatus)"
    }
}

public struct NotificationTokenRegistrationPayload: Encodable, Equatable, Sendable {
    public let deviceId: String
    public let platform: String
    public let tokenRedacted: String
    public let environment: String
    public let enrolledDeveloperProgram: Bool

    public init(deviceId: String, platform: String = "ios", tokenRedacted: String = "<redacted>", environment: String = "development", enrolledDeveloperProgram: Bool) {
        self.deviceId = deviceId
        self.platform = platform
        self.tokenRedacted = tokenRedacted
        self.environment = environment
        self.enrolledDeveloperProgram = enrolledDeveloperProgram
    }
}

public struct APNsApprovalNotificationPayload: Codable, Equatable, Sendable {
    public let aps: APS
    public let runId: String
    public let approvalId: String
    public let route: String

    public struct APS: Codable, Equatable, Sendable {
        public let alert: Alert
        public let sound: String
        public let category: String
        public let threadId: String

        private enum CodingKeys: String, CodingKey {
            case alert
            case sound
            case category
            case threadId = "thread-id"
        }
    }

    public struct Alert: Codable, Equatable, Sendable {
        public let title: String
        public let body: String
    }

    private enum CodingKeys: String, CodingKey {
        case aps
        case runId = "run_id"
        case approvalId = "approval_id"
        case route
    }

    public init(runId: String, approvalId: String, command: String) {
        self.aps = APS(
            alert: Alert(title: "Hermes Agent approval required", body: command),
            sound: "default",
            category: "HERMES_AGENT_APPROVAL",
            threadId: runId
        )
        self.runId = runId
        self.approvalId = approvalId
        self.route = "hermes-agent-ios://approval/\(approvalId)"
    }
}

public enum ApprovalDecision: Sendable {
    case approve
    case reject

    var pathComponent: String {
        switch self {
        case .approve: "approve"
        case .reject: "reject"
        }
    }
}

public enum GatewayEndpoint: Sendable {
    case createMessage(CommandMessagePayload)
    case approvalDecision(id: String, decision: ApprovalDecision)
    case pendingApprovals
    case threadMessages(threadId: String)
    case registerNotificationToken(NotificationTokenRegistrationPayload)

    public func urlRequest(baseURL: URL) throws -> URLRequest {
        let path: String
        let method: String
        let body: Data?

        switch self {
        case .createMessage(let payload):
            path = "/v0/messages"
            method = "POST"
            body = try JSONEncoder.hermesAgentGateway.encode(payload)
        case .approvalDecision(let id, let decision):
            path = "/v0/approvals/\(id)/\(decision.pathComponent)"
            method = "POST"
            body = Data("{}".utf8)
        case .pendingApprovals:
            path = "/v0/approvals"
            method = "GET"
            body = nil
        case .threadMessages(let threadId):
            path = "/v0/threads/\(threadId)/messages"
            method = "GET"
            body = nil
        case .registerNotificationToken(let payload):
            path = "/v0/notification-tokens"
            method = "POST"
            body = try JSONEncoder.hermesAgentGateway.encode(payload)
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

public enum GatewayClientError: Error, Equatable, Sendable {
    case nonHTTPResponse
    case unacceptableStatus(Int)
}

public struct HermesAPICapabilities: Codable, Equatable, Sendable {
    public let object: String
    public let platform: String
    public let model: String
    public let auth: HermesAPIAuth
    public let runtime: HermesAPIRuntime
    public let features: HermesAPIFeatures
    public let endpoints: HermesAPIEndpoints
}

public struct HermesAPIAuth: Codable, Equatable, Sendable {
    public let type: String
    public let required: Bool
}

public struct HermesAPIRuntime: Codable, Equatable, Sendable {
    public let mode: String
    public let toolExecution: String
    public let splitRuntime: Bool

    private enum CodingKeys: String, CodingKey {
        case mode
        case toolExecution = "tool_execution"
        case splitRuntime = "split_runtime"
    }
}

public struct HermesAPIFeatures: Codable, Equatable, Sendable {
    public let runSubmission: Bool
    public let runStatus: Bool
    public let runApprovalResponse: Bool

    private enum CodingKeys: String, CodingKey {
        case runSubmission = "run_submission"
        case runStatus = "run_status"
        case runApprovalResponse = "run_approval_response"
    }
}

public struct HermesAPIEndpoints: Codable, Equatable, Sendable {
    public let runs: HermesAPIEndpointDescription
    public let runStatus: HermesAPIEndpointDescription
    public let runApproval: HermesAPIEndpointDescription

    private enum CodingKeys: String, CodingKey {
        case runs
        case runStatus = "run_status"
        case runApproval = "run_approval"
    }
}

public struct HermesAPIEndpointDescription: Codable, Equatable, Sendable {
    public let method: String
    public let path: String
}

public struct HermesRunSubmission: Codable, Equatable, Sendable {
    public let runId: String
    public let status: String

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}

public struct HermesRunStatus: Codable, Equatable, Sendable {
    public let object: String
    public let runId: String
    public let status: String
    public let createdAt: Double?
    public let updatedAt: Double
    public let sessionId: String?
    public let model: String?
    public let lastEvent: String?
    public let output: String?
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case object
        case runId = "run_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionId = "session_id"
        case model
        case lastEvent = "last_event"
        case output
        case error
    }
}

public enum HermesApprovalChoice: String, Codable, Equatable, Sendable {
    case once
    case session
    case always
    case deny
}

public struct HermesApprovalResolution: Codable, Equatable, Sendable {
    public let object: String
    public let runId: String
    public let choice: HermesApprovalChoice
    public let resolved: Int

    private enum CodingKeys: String, CodingKey {
        case object
        case runId = "run_id"
        case choice
        case resolved
    }
}

public enum HermesRunCardFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case needsAttention
    case active
    case completed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:
            return "All"
        case .needsAttention:
            return "Needs Attention"
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        }
    }

    public func matches(_ card: HermesRunCard) -> Bool {
        switch self {
        case .all:
            return true
        case .needsAttention:
            return card.needsAttention
        case .active:
            return !card.isTerminal
        case .completed:
            return card.status == "completed"
        }
    }
}

public struct HermesRunCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let lastEvent: String?
    public let output: String?
    public let error: String?
    public let updatedAt: Double?

    public init(id: String, title: String, status: String, lastEvent: String? = nil, output: String? = nil, error: String? = nil, updatedAt: Double? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.lastEvent = lastEvent
        self.output = output
        self.error = error
        self.updatedAt = updatedAt
    }

    public init(submission: HermesRunSubmission, title: String) {
        self.init(id: submission.runId, title: title, status: submission.status)
    }

    public var isTerminal: Bool {
        ["completed", "failed", "cancelled"].contains(status)
    }

    public var isWaitingForApproval: Bool {
        status == "waiting_for_approval"
    }

    public var isPollingFallbackActive: Bool {
        lastEvent == "SSE fallback active"
    }

    public var needsAttention: Bool {
        isWaitingForApproval || status == "failed"
    }

    public var operatorStateLabel: String {
        if isPollingFallbackActive {
            return "Polling run status"
        }
        if isWaitingForApproval {
            return "Waiting for iPhone approval"
        }
        if status == "completed" {
            return "Completed"
        }
        if status == "failed" {
            return "Failed"
        }
        if status == "cancelled" {
            return "Cancelled"
        }
        return "Active Run"
    }

    public var operatorDetail: String {
        if isPollingFallbackActive {
            return "SSE fallback active; polling the authoritative run status so the iPhone does not spin forever."
        }
        if isWaitingForApproval {
            return "Hermes is paused at an approval gate. Review the approval card, then approve once/session/always or deny."
        }
        if status == "completed" {
            return "Run finished and the latest output is shown below."
        }
        if status == "failed" {
            return "Run failed; inspect the error before retrying."
        }
        if status == "cancelled" {
            return "Run was cancelled before completion."
        }
        return "Hermes is still working; refresh if this card looks stale."
    }

    public var liveActivityDetail: String {
        if isWaitingForApproval {
            return HermesAgentLiveActivityState.waitingForApproval.defaultDetail
        }
        if status == "completed" {
            if let output, !output.isEmpty {
                return "Approved and completed. \(output)"
            }
            return HermesAgentLiveActivityState.completed.defaultDetail
        }
        if status == "failed" {
            if let error, !error.isEmpty {
                return "Run failed. \(error)"
            }
            return HermesAgentLiveActivityState.failed.defaultDetail
        }
        if status == "cancelled" {
            return "Run cancelled before completion. Open Hermes Agent iOS for details."
        }
        return operatorDetail
    }

    public var lastCheckedLabel: String {
        guard let updatedAt else {
            return "Last checked: not yet"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return "Last checked: \(formatter.string(from: Date(timeIntervalSince1970: updatedAt)))"
    }

    public func updated(with status: HermesRunStatus) -> HermesRunCard {
        HermesRunCard(
            id: status.runId,
            title: title,
            status: status.status,
            lastEvent: status.lastEvent,
            output: status.output,
            error: status.error,
            updatedAt: status.updatedAt
        )
    }

    public static func filteredAndPrioritized(_ cards: [HermesRunCard], filter: HermesRunCardFilter) -> [HermesRunCard] {
        cards
            .filter { filter.matches($0) }
            .sorted { left, right in
                if (filter == .all || filter == .needsAttention), left.needsAttention != right.needsAttention {
                    return left.needsAttention && !right.needsAttention
                }
                return (left.updatedAt ?? 0) > (right.updatedAt ?? 0)
            }
    }

    public static func operatorSummary(cards: [HermesRunCard], visible: [HermesRunCard]) -> String {
        "Showing \(visible.count) of \(cards.count) · Attention first"
    }
}

public struct HermesRunEvent: Codable, Equatable, Sendable {
    public let event: String
    public let runId: String
    public let timestamp: Double?
    public let delta: String?
    public let output: String?
    public let error: String?
    public let tool: String?
    public let command: String?
    public let description: String?
    public let riskTier: Int?
    public let scope: [String]?
    public let reason: String?
    public let rollback: String?
    public let patternKey: String?
    public let patternKeys: [String]?
    public let choices: [String]?

    private enum CodingKeys: String, CodingKey {
        case event
        case runId = "run_id"
        case timestamp
        case delta
        case output
        case error
        case tool
        case command
        case description
        case riskTier = "risk_tier"
        case scope
        case reason
        case rollback
        case patternKey = "pattern_key"
        case patternKeys = "pattern_keys"
        case choices
    }

    public static func parseSSEEvents(from data: Data) throws -> [HermesRunEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return try parseSSEEvents(from: text)
    }

    public static func parseSSEEvents(from text: String) throws -> [HermesRunEvent] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var events: [HermesRunEvent] = []

        for block in blocks {
            let dataLines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .compactMap { line -> String? in
                    guard line.hasPrefix("data:") else { return nil }
                    return String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                }
            guard !dataLines.isEmpty else { continue }
            let payload = dataLines.joined(separator: "\n")
            guard let payloadData = payload.data(using: .utf8) else { continue }
            events.append(try JSONDecoder.hermesAgentGateway.decode(HermesRunEvent.self, from: payloadData))
        }

        return events
    }
}

public struct HermesSSEEventBuffer: Sendable {
    private var dataLines: [String] = []

    public init() {}

    public mutating func appendLine(_ line: String) throws -> HermesRunEvent? {
        let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if normalized.isEmpty {
            return try emitIfReady()
        }
        guard normalized.hasPrefix("data:") else {
            return nil
        }
        dataLines.append(String(normalized.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        return nil
    }

    public mutating func finish() throws -> HermesRunEvent? {
        try emitIfReady()
    }

    private mutating func emitIfReady() throws -> HermesRunEvent? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines = []
        guard let data = payload.data(using: .utf8) else { return nil }
        return try JSONDecoder.hermesAgentGateway.decode(HermesRunEvent.self, from: data)
    }
}

public struct HermesApprovalCard: Equatable, Identifiable, Sendable {
    public let id: String
    public let runId: String
    public let title: String
    public let command: String
    public let description: String
    public let riskTier: Int?
    public let scope: [String]
    public let reason: String
    public let rollback: String
    public let patternKeys: [String]
    public let choices: [HermesApprovalChoice]

    public var riskLabel: String {
        if let riskTier {
            return "Risk tier \(riskTier)"
        }
        return "Risk unknown"
    }

    public static func genericApprovalCard(runId: String) -> HermesApprovalCard {
        HermesApprovalCard(
            id: "\(runId):generic-approval",
            runId: runId,
            title: "Approval required",
            command: "Approval details were not delivered by the event stream.",
            description: "Hermes is waiting for approval before continuing. Use this fallback card to resolve the pending run.",
            riskTier: nil,
            scope: [],
            reason: "Run status is waiting_for_approval, but the event stream did not provide approval details.",
            rollback: "Deny the approval if scope or side effects are unclear.",
            patternKeys: [],
            choices: [.once, .session, .always, .deny]
        )
    }

    public static func cards(from events: [HermesRunEvent]) -> [HermesApprovalCard] {
        events.compactMap { event in
            guard event.event == "approval.request" else { return nil }
            let keys = event.patternKeys ?? event.patternKey.map { [$0] } ?? []
            let stablePattern = keys.first ?? "approval"
            let typedChoices = (event.choices ?? []).compactMap(HermesApprovalChoice.init(rawValue:))
            return HermesApprovalCard(
                id: "\(event.runId):\(stablePattern)",
                runId: event.runId,
                title: "Approval required",
                command: event.command ?? "Unknown command",
                description: event.description ?? "Hermes is waiting for approval before continuing.",
                riskTier: event.riskTier,
                scope: event.scope ?? [],
                reason: event.reason ?? "Hermes is waiting for operator approval before continuing.",
                rollback: event.rollback ?? "Deny the approval if the requested action is unclear.",
                patternKeys: keys,
                choices: typedChoices.isEmpty ? [.once, .deny] : typedChoices
            )
        }
    }
}

public struct HermesApprovalAuditEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let runId: String
    public let approvalCardId: String
    public let command: String
    public let riskLabel: String
    public let scope: [String]
    public let reason: String
    public let rollback: String
    public let patternKeys: [String]
    public let choice: HermesApprovalChoice
    public let resolvedAt: Double
    public let outcomeStatus: String
    public let outcomeOutput: String?

    public init(card: HermesApprovalCard, choice: HermesApprovalChoice, resolvedAt: Double, outcomeStatus: String, outcomeOutput: String?) {
        self.id = "\(card.id):\(choice.rawValue):\(Int(resolvedAt))"
        self.runId = card.runId
        self.approvalCardId = card.id
        self.command = card.command
        self.riskLabel = card.riskLabel
        self.scope = card.scope
        self.reason = card.reason
        self.rollback = card.rollback
        self.patternKeys = card.patternKeys
        self.choice = choice
        self.resolvedAt = resolvedAt
        self.outcomeStatus = outcomeStatus
        self.outcomeOutput = outcomeOutput
    }

    public var decisionLabel: String {
        switch choice {
        case .once:
            return "Decision: approve once"
        case .session:
            return "Decision: trust session"
        case .always:
            return "Decision: always allow"
        case .deny:
            return "Decision: deny"
        }
    }

    public var contextSummary: String {
        let scopeText = scope.isEmpty ? "scope unknown" : scope.joined(separator: ", ")
        return "\(riskLabel) · \(scopeText)"
    }

    public var resultSummary: String {
        let trimmedOutput = outcomeOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedOutput.isEmpty {
            return "Outcome: \(outcomeStatus)"
        }
        return "Outcome: \(outcomeStatus) · \(trimmedOutput)"
    }

    public var resolvedAtLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return "Resolved at: \(formatter.string(from: Date(timeIntervalSince1970: resolvedAt)))"
    }
}

public enum HermesOperatorLogCategory: String, Codable, Equatable, Sendable {
    case capabilityCheck
    case bootstrap
    case approvalDecision
    case runSubmitted

    public var label: String {
        switch self {
        case .capabilityCheck:
            return "Capability check"
        case .bootstrap:
            return "Bootstrap"
        case .approvalDecision:
            return "Approval decision"
        case .runSubmitted:
            return "Run submitted"
        }
    }
}

public struct HermesOperatorLogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let category: HermesOperatorLogCategory
    public let title: String
    public let detail: String
    public let timestamp: Double
    public let runId: String?

    public init(category: HermesOperatorLogCategory, title: String, detail: String, timestamp: Double, runId: String? = nil) {
        self.category = category
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.runId = runId
        self.id = "\(category.rawValue):\(runId ?? "global"):\(Int(timestamp))"
    }

    public var categoryLabel: String {
        category.label
    }

    public var detailLabel: String {
        detail
    }

    public var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

public enum HermesOperatorTimelineFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case approvals
    case debug

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:
            return "All"
        case .approvals:
            return "Approvals"
        case .debug:
            return "Debug"
        }
    }

    public func matches(_ item: HermesOperatorTimelineItem) -> Bool {
        switch self {
        case .all:
            return true
        case .approvals:
            return item.kind == .approval
        case .debug:
            return item.kind == .debug
        }
    }
}

public enum HermesOperatorTimelineKind: String, Codable, Equatable, Sendable {
    case approval
    case debug

    public var label: String {
        switch self {
        case .approval:
            return "Approval"
        case .debug:
            return "Debug"
        }
    }
}

public struct HermesOperatorTimelineItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: HermesOperatorTimelineKind
    public let title: String
    public let detail: String
    public let timestamp: Double
    public let runId: String?

    public init(id: String, kind: HermesOperatorTimelineKind, title: String, detail: String, timestamp: Double, runId: String?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.runId = runId
    }

    public init(audit: HermesApprovalAuditEntry) {
        self.init(
            id: audit.id,
            kind: .approval,
            title: audit.decisionLabel,
            detail: "\(audit.contextSummary) · \(audit.resultSummary)",
            timestamp: audit.resolvedAt,
            runId: audit.runId
        )
    }

    public init(log: HermesOperatorLogEntry) {
        self.init(
            id: log.id,
            kind: .debug,
            title: log.categoryLabel,
            detail: log.detailLabel,
            timestamp: log.timestamp,
            runId: log.runId
        )
    }

    public var kindLabel: String {
        kind.label
    }

    public var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    public static func makeTimeline(audits: [HermesApprovalAuditEntry], logs: [HermesOperatorLogEntry]) -> [HermesOperatorTimelineItem] {
        (audits.map(HermesOperatorTimelineItem.init(audit:)) + logs.map(HermesOperatorTimelineItem.init(log:)))
            .sorted { $0.timestamp > $1.timestamp }
    }

    public static func filteredTimeline(_ items: [HermesOperatorTimelineItem], filter: HermesOperatorTimelineFilter) -> [HermesOperatorTimelineItem] {
        items.filter { filter.matches($0) }
    }

    public static func timelineSummary(all: [HermesOperatorTimelineItem], visible: [HermesOperatorTimelineItem]) -> String {
        "Showing \(visible.count) of \(all.count) timeline events"
    }
}

public struct HermesOperatorTimelineDetail: Equatable, Sendable {
    public let item: HermesOperatorTimelineItem

    public init(item: HermesOperatorTimelineItem) {
        self.item = item
    }

    public var replayTitle: String {
        "Replay context: \(item.kindLabel)"
    }

    public var contextDetail: String {
        item.detail
    }

    public var outcomeDetail: String {
        guard item.kind == .approval else {
            return "No outcome attached"
        }
        if let outcomeRange = item.detail.range(of: "Outcome:") {
            return String(item.detail[outcomeRange.lowerBound...])
        }
        return "Outcome detail unavailable"
    }
}

public struct HermesOperatorTimelineExport: Equatable, Sendable {
    public let items: [HermesOperatorTimelineItem]

    public init(items: [HermesOperatorTimelineItem]) {
        self.items = items
    }

    public var markdownSnapshot: String {
        var lines = ["# Hermes Agent Operator Timeline", "", "Events: \(items.count)"]
        for item in items {
            lines.append("")
            lines.append("## \(item.timestampLabel) · \(item.kindLabel)")
            lines.append("- Title: \(item.title)")
            lines.append("- Detail: \(item.detail)")
            if let runId = item.runId {
                lines.append("- Run ID: \(runId)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum HermesAgentLiveActivityState: String, Codable, Equatable, Hashable, Sendable {
    case running
    case waitingForApproval = "waiting_for_approval"
    case completed
    case failed

    public var statusLabel: String {
        switch self {
        case .running:
            return "Running"
        case .waitingForApproval:
            return "Approval Required"
        case .completed:
            return "Approved · Done"
        case .failed:
            return "Failed"
        }
    }

    public var compactLabel: String {
        switch self {
        case .running:
            return "RUN"
        case .waitingForApproval:
            return "APPROVE"
        case .completed:
            return "DONE"
        case .failed:
            return "FAILED"
        }
    }

    public var dynamicIslandLeadingLabel: String {
        switch self {
        case .running, .waitingForApproval, .completed, .failed:
            return "AN"
        }
    }

    public var dynamicIslandTrailingLabel: String {
        switch self {
        case .running:
            return "RUN"
        case .waitingForApproval:
            return "OK?"
        case .completed:
            return "OK"
        case .failed:
            return "ERR"
        }
    }

    public var symbolName: String {
        switch self {
        case .running:
            return "bolt.horizontal.circle.fill"
        case .waitingForApproval:
            return "hand.raised.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    public var defaultDetail: String {
        switch self {
        case .running:
            return "Hermes is working. I’ll keep this run visible until it needs you or finishes."
        case .waitingForApproval:
            return "Paused for approval. Review the iPhone card, then approve once or deny."
        case .completed:
            return "Approved and completed. Result is ready in Hermes Agent iOS."
        case .failed:
            return "Run failed. Open Hermes Agent iOS to inspect the error before retrying."
        }
    }

    public var shouldEndLiveActivityAfterUpdate: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .running, .waitingForApproval:
            return false
        }
    }
}

public struct HermesAgentLiveActivitySnapshot: Codable, Equatable, Hashable, Sendable {
    public let runId: String
    public let title: String
    public let state: HermesAgentLiveActivityState
    public let detail: String
    public let updatedAt: Double

    public init(runId: String, title: String, state: HermesAgentLiveActivityState, detail: String, updatedAt: Double) {
        self.runId = runId
        self.title = title
        self.state = state
        self.detail = detail
        self.updatedAt = updatedAt
    }

    public init(card: HermesRunCard) {
        let state: HermesAgentLiveActivityState
        if card.isWaitingForApproval {
            state = .waitingForApproval
        } else if card.status == "completed" {
            state = .completed
        } else if card.status == "failed" {
            state = .failed
        } else {
            state = .running
        }
        self.init(
            runId: card.id,
            title: card.title,
            state: state,
            detail: card.liveActivityDetail,
            updatedAt: card.updatedAt ?? Date().timeIntervalSince1970
        )
    }

    public var statusLabel: String { state.statusLabel }
    public var dynamicIslandCompactLabel: String { state.compactLabel }
    public var dynamicIslandCompactLeadingLabel: String { state.dynamicIslandLeadingLabel }
    public var dynamicIslandCompactTrailingLabel: String { state.dynamicIslandTrailingLabel }
    public var dynamicIslandMinimalSymbolName: String { state.symbolName }

    public var stalenessLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return "Updated \(formatter.string(from: Date(timeIntervalSince1970: updatedAt)))"
    }
}

#if os(iOS) && canImport(ActivityKit)
@available(iOS 16.1, *)
public struct HermesAgentLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = HermesAgentLiveActivitySnapshot

    public let runId: String
    public let title: String

    public init(runId: String, title: String) {
        self.runId = runId
        self.title = title
    }
}
#endif

public enum HermesLiveSmoke: Sendable {
    public static let commandSentinel = "HERMES_AGENT_IOS_LIVE_SMOKE_OK"
    public static let commandPrompt = "Reply exactly: \(commandSentinel)"
    public static let approvalSentinel = "HERMES_AGENT_IOS_APPROVAL_SMOKE_OK"
    public static let approvalCommand = "rm -rf /tmp/hermes-agent-ios-approval-smoke"
    public static let approvalPrompt = """
    Run a live approval smoke test for Hermes Agent iOS. Use the terminal tool to run exactly this command:
    \(approvalCommand)

    If the command is approved and executes, reply exactly: \(approvalSentinel)
    """

    public static var approvalCard: HermesApprovalCard {
        approvalCard(runId: "pending")
    }

    public static func approvalCard(runId: String) -> HermesApprovalCard {
        HermesApprovalCard(
            id: "\(runId):hermes-agent-ios-approval-smoke",
            runId: runId,
            title: "Approval smoke pending",
            command: approvalCommand,
            description: "Hermes is waiting for iPhone approval before running the approval smoke command.",
            riskTier: 1,
            scope: ["/tmp/hermes-agent-ios-approval-smoke"],
            reason: "Deterministic low-impact approval smoke test for the iPhone cockpit.",
            rollback: "No production state is affected; recreate the temporary smoke path if needed.",
            patternKeys: ["hermes-agent-ios-approval-smoke"],
            choices: [.once, .deny]
        )
    }
}

public struct HermesDeviceBootstrapSettings: Equatable, Sendable {
    public let baseURL: URL
    public let bearerToken: String
    public let gatewayRemoteBaseURL: URL?
    public let gatewayWebSocketToken: String?

    public init(baseURL: URL, bearerToken: String, gatewayRemoteBaseURL: URL? = nil, gatewayWebSocketToken: String? = nil) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.gatewayRemoteBaseURL = gatewayRemoteBaseURL
        self.gatewayWebSocketToken = gatewayWebSocketToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var redactedTokenSummary: String {
        bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Bearer token missing"
            : "Bearer token configured (<redacted>)"
    }

    public var redactedGatewayTokenSummary: String {
        gatewayWebSocketToken == nil ? "Gateway token missing" : "Gateway token configured (<redacted>)"
    }
}

public struct HermesDeviceDiagnostics: Equatable, Sendable {
    public let baseURL: URL
    public let hasBearerToken: Bool
    public let lastCapabilityCheckAt: Double?
    public let isWirelessHandoff: Bool

    public init(baseURL: URL, hasBearerToken: Bool, lastCapabilityCheckAt: Double?, isWirelessHandoff: Bool) {
        self.baseURL = baseURL
        self.hasBearerToken = hasBearerToken
        self.lastCapabilityCheckAt = lastCapabilityCheckAt
        self.isWirelessHandoff = isWirelessHandoff
    }

    public var apiURLLabel: String {
        "Current API URL: \(baseURL.absoluteString)"
    }

    public var tokenStateLabel: String {
        hasBearerToken ? "Token: configured (<redacted>)" : "Token: missing"
    }

    public var capabilityCheckLabel: String {
        guard let lastCapabilityCheckAt else {
            return "Last capability check: not yet"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return "Last capability check: \(formatter.string(from: Date(timeIntervalSince1970: lastCapabilityCheckAt)))"
    }

    public var handoffStateLabel: String {
        isWirelessHandoff ? "Wi‑Fi/CoreDevice: wireless handoff ready" : "Wi‑Fi/CoreDevice: pair/trust iPhone before wireless handoff"
    }
}

public enum HermesDeviceBootstrapLink: Sendable {
    public static let scheme = "hermes-agent-ios"
    public static let host = "hermes-api"

    public static func url(baseURL: URL, bearerToken: String, gatewayRemoteBaseURL: URL? = nil, gatewayWebSocketToken: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items = [
            URLQueryItem(name: "base_url", value: baseURL.absoluteString),
            URLQueryItem(name: "token", value: bearerToken)
        ]
        if let gatewayRemoteBaseURL {
            items.append(URLQueryItem(name: "gateway_base_url", value: gatewayRemoteBaseURL.absoluteString))
        }
        if let gatewayWebSocketToken = gatewayWebSocketToken?.trimmingCharacters(in: .whitespacesAndNewlines), !gatewayWebSocketToken.isEmpty {
            items.append(URLQueryItem(name: "gateway_ws_token", value: gatewayWebSocketToken))
        }
        components.queryItems = items
        return components.url
    }

    public static func parse(_ url: URL) -> HermesDeviceBootstrapSettings? {
        guard url.scheme == scheme, url.host == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        guard
            let baseURLString = items.first(where: { $0.name == "base_url" })?.value,
            let baseURL = URL(string: baseURLString),
            let token = items.first(where: { $0.name == "token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            return nil
        }
        guard baseURL.scheme == "http" || baseURL.scheme == "https" else { return nil }
        let gatewayBaseURL = items.first(where: { $0.name == "gateway_base_url" })?.value.flatMap(URL.init(string:))
        let gatewayToken = items.first(where: { $0.name == "gateway_ws_token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let gatewayBaseURL, !(gatewayBaseURL.scheme == "http" || gatewayBaseURL.scheme == "https") { return nil }
        return HermesDeviceBootstrapSettings(baseURL: baseURL, bearerToken: token, gatewayRemoteBaseURL: gatewayBaseURL, gatewayWebSocketToken: gatewayToken)
    }
}

public struct HermesAgentSharePayload: Codable, Equatable, Sendable {
    public static let scheme = HermesDeviceBootstrapLink.scheme
    public static let host = "share"

    public let text: String?
    public let url: URL?
    public let title: String?

    public init(text: String? = nil, url: URL? = nil, title: String? = nil) {
        self.text = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.url = url
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var isEmpty: Bool {
        text == nil && url == nil && title == nil
    }

    public var handoffURL: URL? {
        guard !isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items: [URLQueryItem] = []
        if let title { items.append(URLQueryItem(name: "title", value: title)) }
        if let text { items.append(URLQueryItem(name: "text", value: text)) }
        if let url { items.append(URLQueryItem(name: "url", value: url.absoluteString)) }
        components.queryItems = items
        return components.url
    }

    public static func parse(_ url: URL) -> HermesAgentSharePayload? {
        guard url.scheme == scheme, url.host == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ ["text", "url", "title"].contains($0.name) }) else { return nil }
        let text = items.first(where: { $0.name == "text" })?.value
        let title = items.first(where: { $0.name == "title" })?.value
        let urlValue = items.first(where: { $0.name == "url" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedURL = urlValue.flatMap(URL.init(string:))
        if let parsedURL {
            guard parsedURL.scheme == "http" || parsedURL.scheme == "https" else { return nil }
        }
        let payload = HermesAgentSharePayload(text: text, url: parsedURL, title: title)
        return payload.isEmpty ? nil : payload
    }

    public var operatorLabel: String {
        if let title {
            return "Shared: \(title)"
        }
        if let url {
            return "Shared URL: \(url.host ?? url.absoluteString)"
        }
        return "Shared text"
    }

    public var commandPrompt: String {
        var lines = ["Review this shared item and suggest the next useful action."]
        if let title { lines.append("Title: \(title)") }
        if let url { lines.append("URL: \(url.absoluteString)") }
        if let text { lines.append("Text: \(text)") }
        return lines.joined(separator: "\n")
    }

    public var isSecretSafeForChrome: Bool {
        guard let value = handoffURL?.absoluteString.lowercased() else { return true }
        return !value.contains("bearer") && !value.contains("authorization") && !value.contains("base_url=") && !value.contains("token=")
    }
}

private struct HermesRunPayload: Encodable, Equatable, Sendable {
    let input: String
    let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case input
        case sessionId = "session_id"
    }
}

private struct HermesApprovalPayload: Encodable, Equatable, Sendable {
    let choice: HermesApprovalChoice
}

public enum HermesAPIEndpoint: Sendable {
    case capabilities
    case submitRun(input: String, sessionId: String?)
    case runStatus(runId: String)
    case runEvents(runId: String)
    case resolveApproval(runId: String, choice: HermesApprovalChoice)

    public func urlRequest(baseURL: URL, bearerToken: String? = nil) throws -> URLRequest {
        let path: String
        let method: String
        let body: Data?
        let acceptHeader: String

        switch self {
        case .capabilities:
            path = "/v1/capabilities"
            method = "GET"
            body = nil
            acceptHeader = "application/json"
        case .submitRun(let input, let sessionId):
            path = "/v1/runs"
            method = "POST"
            body = try JSONEncoder.hermesAgentGateway.encode(HermesRunPayload(input: input, sessionId: sessionId))
            acceptHeader = "application/json"
        case .runStatus(let runId):
            path = "/v1/runs/\(runId)"
            method = "GET"
            body = nil
            acceptHeader = "application/json"
        case .runEvents(let runId):
            path = "/v1/runs/\(runId)/events"
            method = "GET"
            body = nil
            acceptHeader = "text/event-stream"
        case .resolveApproval(let runId, let choice):
            path = "/v1/runs/\(runId)/approval"
            method = "POST"
            body = try JSONEncoder.hermesAgentGateway.encode(HermesApprovalPayload(choice: choice))
            acceptHeader = "application/json"
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

public struct GatewayClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func createCommand(text: String) async throws -> CommandRunResponse {
        let request = try GatewayEndpoint.createMessage(CommandMessagePayload(text: text)).urlRequest(baseURL: baseURL)
        return try await perform(request, as: CommandRunResponse.self, acceptableStatusCodes: 200..<300)
    }

    public func decideApproval(id: String, decision: ApprovalDecision) async throws -> ApprovalDecisionResponse {
        let request = try GatewayEndpoint.approvalDecision(id: id, decision: decision).urlRequest(baseURL: baseURL)
        return try await perform(request, as: ApprovalDecisionResponse.self, acceptableStatusCodes: 200..<300)
    }

    public func fetchPendingApprovals() async throws -> PendingApprovalsResponse {
        let request = try GatewayEndpoint.pendingApprovals.urlRequest(baseURL: baseURL)
        return try await perform(request, as: PendingApprovalsResponse.self, acceptableStatusCodes: 200..<300)
    }

    public func fetchThreadMessages(threadId: String) async throws -> ThreadMessagesResponse {
        let request = try GatewayEndpoint.threadMessages(threadId: threadId).urlRequest(baseURL: baseURL)
        return try await perform(request, as: ThreadMessagesResponse.self, acceptableStatusCodes: 200..<300)
    }

    private func perform<Response: Decodable>(_ request: URLRequest, as responseType: Response.Type, acceptableStatusCodes: Range<Int>) async throws -> Response {
        try await performGatewayRequest(request, as: responseType, acceptableStatusCodes: acceptableStatusCodes, session: session)
    }
}

public enum HermesAgentAppIntentKind: String, Codable, CaseIterable, Sendable {
    case askHermesAgent
    case runLiveSmoke
    case openNeedsAttention
    case checkHermesCapability

    public var title: String {
        switch self {
        case .askHermesAgent: "Ask Hermes Agent"
        case .runLiveSmoke: "Run Live Smoke"
        case .openNeedsAttention: "Open Needs Attention"
        case .checkHermesCapability: "Check Hermes Capability"
        }
    }

    public var operatorLabel: String {
        switch self {
        case .askHermesAgent: "Open command composer"
        case .runLiveSmoke: "Open live Hermes smoke action"
        case .openNeedsAttention: "Open run cards needing attention"
        case .checkHermesCapability: "Open Hermes capability check"
        }
    }

    public var systemImageName: String {
        switch self {
        case .askHermesAgent: "sparkles"
        case .runLiveSmoke: "bolt.horizontal.circle"
        case .openNeedsAttention: "exclamationmark.triangle"
        case .checkHermesCapability: "server.rack"
        }
    }
}

public struct HermesAgentAppIntentRoute: Codable, Equatable, Sendable {
    public let kind: HermesAgentAppIntentKind
    public let prompt: String?

    public init(kind: HermesAgentAppIntentKind, prompt: String? = nil) {
        self.kind = kind
        self.prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func askHermesAgent(prompt: String) -> HermesAgentAppIntentRoute {
        HermesAgentAppIntentRoute(kind: .askHermesAgent, prompt: prompt)
    }

    public static let runLiveSmoke = HermesAgentAppIntentRoute(kind: .runLiveSmoke)
    public static let openNeedsAttention = HermesAgentAppIntentRoute(kind: .openNeedsAttention)
    public static let checkHermesCapability = HermesAgentAppIntentRoute(kind: .checkHermesCapability)

    public var storageValue: String {
        var components = URLComponents()
        components.scheme = "hermes-agent-intent"
        components.host = kind.rawValue
        if let prompt {
            components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
        }
        return components.url?.absoluteString ?? "hermes-agent-intent://\(kind.rawValue)"
    }

    public static func parse(_ storageValue: String) -> HermesAgentAppIntentRoute? {
        guard let url = URL(string: storageValue), url.scheme == "hermes-agent-intent" else { return nil }
        guard let host = url.host, let kind = HermesAgentAppIntentKind(rawValue: host) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        guard queryItems.allSatisfy({ $0.name == "prompt" }) else { return nil }
        let prompt = queryItems.first(where: { $0.name == "prompt" })?.value
        return HermesAgentAppIntentRoute(kind: kind, prompt: prompt)
    }

    public var operatorLabel: String {
        if kind == .askHermesAgent, let prompt {
            return "Ask Hermes Agent: \(prompt)"
        }
        return kind.operatorLabel
    }

    public var confirmationDialog: String {
        switch kind {
        case .askHermesAgent:
            return prompt.map { "Opening Hermes Agent with: \($0)" } ?? "Opening Hermes Agent command composer"
        case .runLiveSmoke:
            return "Opening Hermes Agent live smoke action"
        case .openNeedsAttention:
            return "Opening Hermes Agent runs that need attention"
        case .checkHermesCapability:
            return "Opening Hermes capability check"
        }
    }

    public var isSecretSafeForDisplay: Bool {
        let lower = storageValue.lowercased()
        return !lower.contains("bearer") && !lower.contains("token=") && !lower.contains("authorization")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public struct HermesAPIClient: Sendable {
    public let baseURL: URL
    public let bearerToken: String?
    private let session: URLSession

    public init(baseURL: URL, bearerToken: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
    }

    public func fetchCapabilities() async throws -> HermesAPICapabilities {
        let request = try HermesAPIEndpoint.capabilities.urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        return try await perform(request, as: HermesAPICapabilities.self, acceptableStatusCodes: 200..<300)
    }

    public func submitRun(input: String, sessionId: String? = nil) async throws -> HermesRunSubmission {
        let request = try HermesAPIEndpoint.submitRun(input: input, sessionId: sessionId).urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        return try await perform(request, as: HermesRunSubmission.self, acceptableStatusCodes: 202..<203)
    }

    public func fetchRunStatus(runId: String) async throws -> HermesRunStatus {
        let request = try HermesAPIEndpoint.runStatus(runId: runId).urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        return try await perform(request, as: HermesRunStatus.self, acceptableStatusCodes: 200..<300)
    }

    public func streamRunEvents(runId: String) async throws -> [HermesRunEvent] {
        let request = try HermesAPIEndpoint.runEvents(runId: runId).urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayClientError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayClientError.unacceptableStatus(http.statusCode)
        }
        return try HermesRunEvent.parseSSEEvents(from: data)
    }

    public func streamRunEvents(runId: String, onEvent: @escaping @MainActor (HermesRunEvent) async -> Void) async throws {
        let request = try HermesAPIEndpoint.runEvents(runId: runId).urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayClientError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayClientError.unacceptableStatus(http.statusCode)
        }

        var buffer = HermesSSEEventBuffer()
        for try await line in bytes.lines {
            if let event = try buffer.appendLine(line) {
                await onEvent(event)
            }
        }
        if let event = try buffer.finish() {
            await onEvent(event)
        }
    }

    public func resolveApproval(runId: String, choice: HermesApprovalChoice) async throws -> HermesApprovalResolution {
        let request = try HermesAPIEndpoint.resolveApproval(runId: runId, choice: choice).urlRequest(baseURL: baseURL, bearerToken: bearerToken)
        return try await perform(request, as: HermesApprovalResolution.self, acceptableStatusCodes: 200..<300)
    }

    private func perform<Response: Decodable>(_ request: URLRequest, as responseType: Response.Type, acceptableStatusCodes: Range<Int>) async throws -> Response {
        try await performGatewayRequest(request, as: responseType, acceptableStatusCodes: acceptableStatusCodes, session: session)
    }
}

private func performGatewayRequest<Response: Decodable>(_ request: URLRequest, as responseType: Response.Type, acceptableStatusCodes: Range<Int>, session: URLSession) async throws -> Response {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw GatewayClientError.nonHTTPResponse
    }
    guard acceptableStatusCodes.contains(http.statusCode) else {
        throw GatewayClientError.unacceptableStatus(http.statusCode)
    }
    return try JSONDecoder.hermesAgentGateway.decode(responseType, from: data)
}

public extension JSONDecoder {
    static var hermesAgentGateway: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension JSONEncoder {
    static var hermesAgentGateway: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
