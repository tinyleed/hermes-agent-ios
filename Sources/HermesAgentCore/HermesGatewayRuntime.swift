import Foundation

public enum HermesGatewayConnectionState: String, Sendable, Equatable {
    case idle
    case connecting
    case open
    case closed
    case error
}

public struct HermesGatewayEvent: Equatable, Sendable {
    public let type: String
    public let sessionId: String?
    public let payload: [String: String]

    public init(type: String, sessionId: String? = nil, payload: [String: String] = [:]) {
        self.type = type
        self.sessionId = sessionId
        self.payload = payload
    }

    public var text: String {
        payload["text"] ?? payload["rendered"] ?? payload["message"] ?? ""
    }

    public var toolId: String {
        payload["tool_id"] ?? payload["id"] ?? payload["name"] ?? "tool"
    }

    public var toolName: String {
        payload["name"] ?? payload["tool_name"] ?? payload["tool"] ?? toolId
    }
}

public struct HermesGatewaySessionCreateResponse: Equatable, Sendable {
    public let sessionId: String
    public let storedSessionId: String?

    public init(sessionId: String, storedSessionId: String?) {
        self.sessionId = sessionId
        self.storedSessionId = storedSessionId
    }
}

public struct HermesChatToolAction: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable {
        case running
        case complete
    }

    public let id: String
    public let name: String
    public let status: Status
    public let startedAt: Date
    public let completedAt: Date?

    public init(id: String, name: String, status: Status, startedAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var durationMilliseconds: Int? {
        guard let completedAt else { return nil }
        return max(0, Int((completedAt.timeIntervalSince1970 - startedAt.timeIntervalSince1970) * 1000))
    }

    public var durationLabel: String {
        durationMilliseconds.map { "\($0)ms" } ?? "running"
    }
}

public struct HermesChatToolGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let actions: [HermesChatToolAction]
    public let startedAt: Date
    public let completedAt: Date?

    public init(id: String = "tool-actions", actions: [HermesChatToolAction], startedAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.actions = actions
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var completedSteps: Int {
        actions.filter { $0.status == .complete }.count
    }

    public var stepCount: Int {
        actions.count
    }

    public var durationMilliseconds: Int? {
        guard let completedAt else { return nil }
        return max(0, Int((completedAt.timeIntervalSince1970 - startedAt.timeIntervalSince1970) * 1000))
    }

    public var summaryLabel: String {
        let duration = durationMilliseconds.map { "\($0)ms" } ?? "running"
        return "Tool actions — \(stepCount) steps — \(duration)"
    }
}

public enum HermesChatBlockingRequestKind: String, Sendable, Equatable, Codable {
    case approval
    case clarify
    case sudo
    case secret

    public var title: String {
        switch self {
        case .approval: return "Approval required"
        case .clarify: return "Clarification needed"
        case .sudo: return "Sudo password required"
        case .secret: return "Secret required"
        }
    }

    public var systemImage: String {
        switch self {
        case .approval: return "checkmark.shield"
        case .clarify: return "questionmark.bubble"
        case .sudo: return "lock.shield"
        case .secret: return "key.fill"
        }
    }

    public var notificationTitle: String {
        switch self {
        case .approval: return "Hermes approval needed"
        case .clarify: return "Hermes clarification needed"
        case .sudo: return "Hermes sudo input needed"
        case .secret: return "Hermes secret input needed"
        }
    }

    public var notificationCategoryIdentifier: String {
        switch self {
        case .approval: return "HERMES_AGENT_APPROVAL"
        case .clarify: return "HERMES_AGENT_CLARIFY"
        case .sudo: return "HERMES_AGENT_SUDO"
        case .secret: return "HERMES_AGENT_SECRET"
        }
    }
}

public struct HermesChatBlockingRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: HermesChatBlockingRequestKind
    public let sessionId: String?
    public let prompt: String
    public let choices: [String]
    public let detailRows: [String]

    public init(id: String, kind: HermesChatBlockingRequestKind, sessionId: String? = nil, prompt: String, choices: [String] = [], detailRows: [String] = []) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
        self.prompt = prompt
        self.choices = choices
        self.detailRows = detailRows
    }

    public var primaryActionLabel: String {
        switch kind {
        case .approval: return "Approve"
        case .clarify: return "Send Answer"
        case .sudo: return "Submit Password"
        case .secret: return "Submit Secret"
        }
    }

    public var destructiveActionLabel: String? {
        kind == .approval ? "Deny" : nil
    }
}

public struct HermesChatRuntimeState: Equatable, Sendable {
    public var sessionId: String?
    public var storedSessionId: String?
    public var assistantText: String
    public var toolGroup: HermesChatToolGroup?
    public var blockingRequests: [HermesChatBlockingRequest]
    public var isStreaming: Bool

    public init(sessionId: String? = nil, storedSessionId: String? = nil, assistantText: String = "", toolGroup: HermesChatToolGroup? = nil, blockingRequests: [HermesChatBlockingRequest] = [], isStreaming: Bool = false) {
        self.sessionId = sessionId
        self.storedSessionId = storedSessionId
        self.assistantText = assistantText
        self.toolGroup = toolGroup
        self.blockingRequests = blockingRequests
        self.isStreaming = isStreaming
    }
}

public enum HermesChatRuntimeReducer {
    public static func reduce(_ state: HermesChatRuntimeState, event: HermesGatewayEvent, now: Date = Date()) -> HermesChatRuntimeState {
        var next = state
        switch event.type {
        case "message.start":
            next.assistantText = ""
            next.isStreaming = true
        case "message.delta":
            next.assistantText += event.text
            next.isStreaming = true
        case "reasoning.delta", "thinking.delta", "reasoning.available":
            next.isStreaming = true
        case "message.complete", "response.complete":
            if !event.text.isEmpty {
                next.assistantText = event.text
            }
            next.isStreaming = false
            if let group = next.toolGroup, group.completedAt == nil {
                next.toolGroup = HermesChatToolGroup(actions: group.actions, startedAt: group.startedAt, completedAt: now)
            }
        case "tool.start", "tool.progress", "tool.generating":
            next.toolGroup = upsertToolAction(in: next.toolGroup, event: event, status: .running, now: now)
        case "tool.complete":
            next.toolGroup = upsertToolAction(in: next.toolGroup, event: event, status: .complete, now: now)
        case "approval.request", "clarify.request", "sudo.request", "secret.request":
            if let request = blockingRequest(from: event) {
                if let index = next.blockingRequests.firstIndex(where: { $0.id == request.id }) {
                    next.blockingRequests[index] = request
                } else {
                    next.blockingRequests.append(request)
                }
            }
            next.isStreaming = false
        default:
            break
        }
        return next
    }

    private static func blockingRequest(from event: HermesGatewayEvent) -> HermesChatBlockingRequest? {
        let kind: HermesChatBlockingRequestKind
        switch event.type {
        case "approval.request": kind = .approval
        case "clarify.request": kind = .clarify
        case "sudo.request": kind = .sudo
        case "secret.request": kind = .secret
        default: return nil
        }
        let requestId = event.payload["request_id"] ?? event.payload["id"] ?? "\(event.type)-\(event.sessionId ?? "session")"
        let prompt = event.payload["question"]
            ?? event.payload["prompt"]
            ?? event.payload["description"]
            ?? event.payload["command"]
            ?? kind.title
        let choices = splitList(event.payload["choices"] ?? event.payload["actions"] ?? "")
        var detailRows: [String] = []
        if let command = event.payload["command"], !command.isEmpty { detailRows.append("Command: \(command)") }
        if let risk = event.payload["risk_tier"] ?? event.payload["risk"], !risk.isEmpty { detailRows.append("Risk: \(risk)") }
        if let scope = event.payload["scope"], !scope.isEmpty { detailRows.append("Scope: \(scope)") }
        if let reason = event.payload["reason"], !reason.isEmpty { detailRows.append("Reason: \(reason)") }
        if let rollback = event.payload["rollback"], !rollback.isEmpty { detailRows.append("Rollback: \(rollback)") }
        if let envVar = event.payload["env_var"], !envVar.isEmpty { detailRows.append("Variable: \(envVar)") }
        return HermesChatBlockingRequest(id: requestId, kind: kind, sessionId: event.sessionId, prompt: prompt, choices: choices, detailRows: detailRows)
    }

    private static func splitList(_ raw: String) -> [String] {
        raw
            .split { character in character == "," || character == "|" || character == "\n" || character == "[" || character == "]" || character == "\"" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func upsertToolAction(in group: HermesChatToolGroup?, event: HermesGatewayEvent, status: HermesChatToolAction.Status, now: Date) -> HermesChatToolGroup {
        let current = group ?? HermesChatToolGroup(actions: [], startedAt: now)
        let id = event.toolId
        var actions = current.actions
        if let index = actions.firstIndex(where: { $0.id == id }) {
            let existing = actions[index]
            actions[index] = HermesChatToolAction(
                id: existing.id,
                name: event.toolName,
                status: status,
                startedAt: existing.startedAt,
                completedAt: status == .complete ? now : existing.completedAt
            )
        } else {
            actions.append(HermesChatToolAction(
                id: id,
                name: event.toolName,
                status: status,
                startedAt: now,
                completedAt: status == .complete ? now : nil
            ))
        }
        return HermesChatToolGroup(actions: actions, startedAt: current.startedAt, completedAt: actions.allSatisfy { $0.status == .complete } ? now : nil)
    }
}

public actor HermesGatewayRPCClient {
    private let webSocketURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var nextRequestId = 0
    private var bufferedEvents: [HermesGatewayEvent] = []

    public init(webSocketURL: URL, session: URLSession = .shared) {
        self.webSocketURL = webSocketURL
        self.session = session
    }

    public func connect() async {
        if let currentTask = task {
            switch currentTask.state {
            case .running, .suspended:
                return
            default:
                task = nil
            }
        }
        let nextTask = session.webSocketTask(with: webSocketURL)
        task = nextTask
        nextTask.resume()
    }

    public func close() {
        bufferedEvents.removeAll()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    public func createSession(cols: Int = 96) async throws -> HermesGatewaySessionCreateResponse {
        let result = try await request(method: "session.create", params: ["cols": cols])
        let sessionId = result["session_id"] as? String ?? ""
        let storedSessionId = result["stored_session_id"] as? String
        guard !sessionId.isEmpty else { throw HermesGatewayRPCError.missingSessionId }
        return HermesGatewaySessionCreateResponse(sessionId: sessionId, storedSessionId: storedSessionId)
    }

    public func submitPrompt(sessionId: String, text: String) async throws {
        _ = try await request(method: "prompt.submit", params: ["session_id": sessionId, "text": text])
    }

    public func respondToApproval(sessionId: String, choice: String, resolveAll: Bool = false) async throws {
        try await sendNotification(method: "approval.respond", params: ["session_id": sessionId, "choice": choice, "all": resolveAll])
    }

    public func respondToClarify(requestId: String, answer: String) async throws {
        try await sendNotification(method: "clarify.respond", params: ["request_id": requestId, "answer": answer])
    }

    public func respondToSudo(requestId: String, password: String) async throws {
        try await sendNotification(method: "sudo.respond", params: ["request_id": requestId, "password": password])
    }

    public func respondToSecret(requestId: String, value: String) async throws {
        try await sendNotification(method: "secret.respond", params: ["request_id": requestId, "value": value])
    }

    public func listSessions(limit: Int = 10) async throws -> [HermesRemoteSessionSummary] {
        let result = try await request(method: "session.list", params: ["limit": limit])
        return Self.parseSessionListResult(result)
    }

    public func resumeSession(storedSessionId: String) async throws -> HermesRemoteSessionResumeResponse {
        let result = try await request(method: "session.resume", params: ["session_id": storedSessionId])
        return try Self.parseSessionResumeResult(result, fallbackStoredSessionId: storedSessionId)
    }

    public static func parseSessionListResult(_ result: [String: Any]) -> [HermesRemoteSessionSummary] {
        guard let rawSessions = result["sessions"] as? [[String: Any]] else { return [] }
        return rawSessions.compactMap { raw in
            guard let id = (raw["id"] ?? raw["session_id"] ?? raw["stored_session_id"]) as? String,
                  !id.isEmpty else { return nil }
            let title = raw["title"] as? String ?? ""
            let messageCount = raw["message_count"] as? Int ?? (raw["messages"] as? [[String: Any]])?.count ?? 0
            let updatedAt = raw["updated_at"] as? TimeInterval ?? raw["last_active"] as? TimeInterval ?? raw["started_at"] as? TimeInterval ?? raw["created_at"] as? TimeInterval ?? 0
            return HermesRemoteSessionSummary(id: id, title: title, messageCount: messageCount, updatedAt: updatedAt)
        }
    }

    public static func parseSessionResumeResult(_ result: [String: Any], fallbackStoredSessionId: String) throws -> HermesRemoteSessionResumeResponse {
        let sessionId = result["session_id"] as? String ?? ""
        let resumedStoredId = result["stored_session_id"] as? String ?? result["session_key"] as? String ?? result["resumed"] as? String ?? fallbackStoredSessionId
        guard !sessionId.isEmpty else { throw HermesGatewayRPCError.missingSessionId }
        let rawMessages = result["messages"] as? [[String: Any]] ?? []
        let messages: [HermesRemoteSessionMessage] = rawMessages.enumerated().compactMap { index, raw in
            guard let role = raw["role"] as? String else { return nil }
            let content = Self.displayText(from: raw["content"] ?? raw["body"] ?? raw["text"])
            let id = raw["id"] as? String ?? "\(resumedStoredId)-msg-\(index)"
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return HermesRemoteSessionMessage(id: id, role: role, content: content)
        }
        return HermesRemoteSessionResumeResponse(sessionId: sessionId, storedSessionId: resumedStoredId, messages: messages)
    }

    public func nextEvent() async throws -> HermesGatewayEvent {
        if !bufferedEvents.isEmpty {
            return bufferedEvents.removeFirst()
        }
        guard let task else { throw HermesGatewayRPCError.notConnected }
        while true {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let value): text = value
            case .data(let data): text = String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
            if let event = Self.parseEventFrame(text) {
                return event
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) async throws {
        await connect()
        guard let task else { throw HermesGatewayRPCError.notConnected }
        let frame: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: frame, options: [])
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        await connect()
        guard let task else { throw HermesGatewayRPCError.notConnected }
        nextRequestId += 1
        let id = "ios-\(nextRequestId)"
        let frame: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: frame, options: [])
        try await task.send(.string(String(decoding: data, as: UTF8.self)))

        while true {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let value): text = value
            case .data(let data): text = String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
            guard let object = Self.parseJSONObject(text) else { continue }
            if let event = Self.parseEventFrame(text) {
                bufferedEvents.append(event)
                continue
            }
            if let responseId = object["id"] as? String, responseId == id {
                if let error = object["error"] as? [String: Any] {
                    throw HermesGatewayRPCError.rpc(error["message"] as? String ?? "Hermes RPC failed")
                }
                return object["result"] as? [String: Any] ?? [:]
            }
        }
    }

    public static func parseEventFrame(_ text: String) -> HermesGatewayEvent? {
        guard let object = parseJSONObject(text), object["method"] as? String == "event", let params = object["params"] as? [String: Any] else { return nil }
        guard let type = params["type"] as? String else { return nil }
        let payload = flattenStringPayload(params["payload"] as? [String: Any] ?? [:])
        return HermesGatewayEvent(type: type, sessionId: params["session_id"] as? String, payload: payload)
    }

    private static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func flattenStringPayload(_ payload: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in payload {
            if let string = value as? String {
                result[key] = string
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            }
        }
        return result
    }

    private static func displayText(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let parts as [Any]:
            return parts.map { displayText(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case let object as [String: Any]:
            if let text = object["text"] as? String { return text }
            if let content = object["content"] { return displayText(from: content) }
            if let kind = object["type"] as? String {
                switch kind {
                case "image_url", "input_image", "image": return "[image]"
                case "input_audio", "audio": return "[audio]"
                default: return "[\(kind)]"
                }
            }
            return "[structured content]"
        case .none:
            return ""
        default:
            return String(describing: value ?? "")
        }
    }
}

public struct HermesRemoteSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let messageCount: Int
    public let updatedAt: TimeInterval

    public init(id: String, title: String, messageCount: Int, updatedAt: TimeInterval) {
        self.id = id
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
    }

    public var displayIdentity: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTitle = trimmedTitle.lowercased()
        let titleLooksSecretBearing = lowerTitle.contains("token=") || lowerTitle.contains("bearer") || lowerTitle.contains("authorization") || lowerTitle.contains("/api/ws")
        return trimmedTitle.isEmpty || titleLooksSecretBearing ? String(id.prefix(8)) + "…" : trimmedTitle
    }

    public var operatorLabel: String {
        "\(displayIdentity) · \(messageCount) messages"
    }

    public func relativeAgeLabel(now: Date = Date()) -> String {
        guard updatedAt > 0 else { return "unknown age" }
        let interval = now.timeIntervalSince1970 - updatedAt
        if interval < 3600 { return "\(max(0, Int(interval / 60)))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

public struct HermesRemoteSessionMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let content: String

    public init(id: String, role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

public struct HermesRemoteSessionResumeResponse: Equatable, Sendable {
    public let sessionId: String
    public let storedSessionId: String
    public let messages: [HermesRemoteSessionMessage]

    public init(sessionId: String, storedSessionId: String, messages: [HermesRemoteSessionMessage]) {
        self.sessionId = sessionId
        self.storedSessionId = storedSessionId
        self.messages = messages
    }
}

public enum HermesGatewayRPCError: LocalizedError, Equatable {
    case notConnected
    case missingSessionId
    case rpc(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Hermes gateway is not connected"
        case .missingSessionId: "Hermes gateway did not return a session id"
        case .rpc(let message): message
        }
    }
}
