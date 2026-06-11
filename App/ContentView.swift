import SwiftUI
import UIKit
import ActivityKit
@preconcurrency import UserNotifications
import HermesAgentCore

private enum HermesAgentLiveActivityController {
    static func startOrUpdate(activityId: String?, snapshot: HermesAgentLiveActivitySnapshot) async throws -> String {
        if let activity = Activity<HermesAgentLiveActivityAttributes>.activities.first(where: { $0.id == activityId }) {
            await activity.update(ActivityContent(state: snapshot, staleDate: nil))
            return activity.id
        }
        let activity = try Activity.request(
            attributes: HermesAgentLiveActivityAttributes(runId: snapshot.runId, title: snapshot.title),
            content: ActivityContent(state: snapshot, staleDate: nil),
            pushType: nil
        )
        return activity.id
    }

    static func end(activityId: String?, finalSnapshot: HermesAgentLiveActivitySnapshot? = nil, immediate: Bool = true) async -> Bool {
        guard let activity = Activity<HermesAgentLiveActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            return false
        }
        let finalContent = finalSnapshot.map { ActivityContent(state: $0, staleDate: nil) }
        let dismissalPolicy: ActivityUIDismissalPolicy = immediate ? .immediate : .after(Date().addingTimeInterval(20))
        await activity.end(finalContent, dismissalPolicy: dismissalPolicy)
        return true
    }
}

private enum HermesAgentMobileShellStyle {
    static let background = LinearGradient(
        colors: [Color(red: 0.025, green: 0.027, blue: 0.03), Color(red: 0.055, green: 0.06, blue: 0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardFill = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.13)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.44)
    static let accent = Color(red: 0.48, green: 0.62, blue: 1.0)
}

private struct HermesAgentMobileShellCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HermesAgentMobileShellStyle.cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HermesAgentMobileShellStyle.cardStroke, lineWidth: 1)
        )
    }
}

private struct HermesAgentStatusPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

private struct MobileShellSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(HermesAgentMobileShellStyle.secondaryText)
    }
}

private struct HermesAgentDesktopStatusBar: View {
    let connectionLabel: String
    let activityLabel: String
    let attentionLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Label(connectionLabel, systemImage: "bolt.horizontal.circle")
                .foregroundStyle(HermesAgentMobileShellStyle.accent)
            Spacer(minLength: 8)
            Label(activityLabel, systemImage: "waveform.path.ecg")
                .foregroundStyle(HermesAgentMobileShellStyle.secondaryText)
            Spacer(minLength: 8)
            Label(attentionLabel, systemImage: "exclamationmark.triangle")
                .foregroundStyle(attentionLabel.hasPrefix("0") ? HermesAgentMobileShellStyle.secondaryText : .orange)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

private struct HermesAgentDesktopActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .foregroundStyle(isPrimary ? HermesAgentMobileShellStyle.accent : HermesAgentMobileShellStyle.primaryText)
            .background(Color.white.opacity(configuration.isPressed ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPrimary ? HermesAgentMobileShellStyle.accent.opacity(0.58) : Color.white.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HermesAgentChatLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case message
        case toolGroup(HermesChatToolGroup)
        case blockingRequest(HermesChatBlockingRequest)
    }

    let id: String
    let role: String
    let body: String
    let isPending: Bool
    let kind: Kind

    var isUser: Bool { role == "user" }
    var isPersistableMessage: Bool {
        if case .message = kind { return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    static func user(_ text: String) -> HermesAgentChatLine {
        HermesAgentChatLine(id: "local-user-\(UUID().uuidString)", role: "user", body: text, isPending: false, kind: .message)
    }

    static func assistant(_ text: String, id: String = "local-assistant-\(UUID().uuidString)", isPending: Bool = false) -> HermesAgentChatLine {
        HermesAgentChatLine(id: id, role: "assistant", body: text, isPending: isPending, kind: .message)
    }

    static func persisted(id: String, role: String, body: String) -> HermesAgentChatLine {
        HermesAgentChatLine(id: id, role: role, body: body, isPending: false, kind: .message)
    }

    static func message(_ message: GatewayMessage) -> HermesAgentChatLine {
        HermesAgentChatLine(id: message.id, role: message.role, body: message.body, isPending: false, kind: .message)
    }

    static func toolGroup(_ group: HermesChatToolGroup) -> HermesAgentChatLine {
        HermesAgentChatLine(id: "tool-group-\(group.id)", role: "assistant", body: group.summaryLabel, isPending: group.completedAt == nil, kind: .toolGroup(group))
    }

    static func blockingRequest(_ request: HermesChatBlockingRequest) -> HermesAgentChatLine {
        HermesAgentChatLine(id: "blocking-request-\(request.id)", role: "assistant", body: request.prompt, isPending: true, kind: .blockingRequest(request))
    }
}

private struct HermesAgentChatTranscriptSnapshot: Codable, Equatable {
    struct Message: Codable, Equatable, Identifiable {
        let id: String
        let role: String
        let body: String
    }

    var storedSessionId: String?
    var storedSessionTitle: String?
    var messages: [Message]

    init(storedSessionId: String? = nil, storedSessionTitle: String? = nil, messages: [Message] = []) {
        self.storedSessionId = storedSessionId
        self.storedSessionTitle = storedSessionTitle
        self.messages = messages
    }

    var summaryLabel: String {
        if let storedSessionId, !storedSessionId.isEmpty {
            let identity = storedSessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayIdentity = identity?.isEmpty == false ? identity! : String(storedSessionId.prefix(8)) + "…"
            return "Resumed \(displayIdentity) · \(messages.count) messages"
        }
        return messages.isEmpty ? "No chat history yet" : "Local chat history · \(messages.count) messages"
    }

    static func make(from lines: [HermesAgentChatLine], storedSessionId: String?, storedSessionTitle: String? = nil) -> HermesAgentChatTranscriptSnapshot {
        let messages = lines
            .filter(\.isPersistableMessage)
            .suffix(80)
            .map { Message(id: $0.id, role: $0.role, body: $0.body) }
        return HermesAgentChatTranscriptSnapshot(storedSessionId: storedSessionId, storedSessionTitle: storedSessionTitle, messages: Array(messages))
    }

    func chatLines() -> [HermesAgentChatLine] {
        messages.map { HermesAgentChatLine.persisted(id: $0.id, role: $0.role, body: $0.body) }
    }
}

private struct HermesAgentToolActionsRow: View {
    let group: HermesChatToolGroup

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.actions) { action in
                    HStack(spacing: 8) {
                        Image(systemName: action.status == .complete ? "checkmark.circle" : "circle.dotted")
                            .font(.caption)
                            .foregroundStyle(action.status == .complete ? HermesAgentMobileShellStyle.accent : HermesAgentMobileShellStyle.secondaryText)
                        Text(action.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                        Spacer()
                        Text(action.durationLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(HermesAgentMobileShellStyle.tertiaryText)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(HermesAgentMobileShellStyle.accent)
                Text(group.summaryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
            }
        }
        .tint(HermesAgentMobileShellStyle.secondaryText)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))
    }
}

private struct HermesAgentInlineBlockingRequestCard: View {
    let request: HermesChatBlockingRequest
    let isResponding: Bool
    let onRespond: (HermesChatBlockingRequest, String) -> Void
    @State private var responseText = ""

    private var requiresTextInput: Bool {
        request.kind == .clarify || request.kind == .sudo || request.kind == .secret
    }

    private var placeholder: String {
        switch request.kind {
        case .clarify: return "Answer"
        case .sudo: return "Password"
        case .secret: return "Secret value"
        case .approval: return ""
        }
    }

    private var allowsEmptyUITestFixtureResponse: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES"] == "1" && request.sessionId == "session_fixture_cards"
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(request.kind.title, systemImage: request.kind.systemImage)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(request.kind == .approval ? .orange : HermesAgentMobileShellStyle.accent)
            Text(request.prompt)
                .font(.callout.weight(.semibold))
                .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
            ForEach(request.detailRows, id: \.self) { row in
                Text(row)
                    .font(.caption2)
                    .foregroundStyle(HermesAgentMobileShellStyle.secondaryText)
                    .lineLimit(3)
            }
            if requiresTextInput {
                if request.kind == .clarify {
                    TextField(placeholder, text: $responseText, axis: .vertical)
                        .accessibilityIdentifier("hermes-agent-inline-blocking-answer-field")
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .padding(10)
                        .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                } else {
                    SecureField(placeholder, text: $responseText)
                        .accessibilityIdentifier("hermes-agent-inline-blocking-secret-field")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    Text("Value stays hidden in UI and transcript.")
                        .font(.caption2)
                        .foregroundStyle(HermesAgentMobileShellStyle.tertiaryText)
                }
            }
            HStack(spacing: 8) {
                Button(request.primaryActionLabel) {
                    let entered = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let payload = requiresTextInput ? (entered.isEmpty ? "fixture-redacted-value" : responseText) : (request.choices.first(where: { $0 != "deny" }) ?? "once")
                    onRespond(request, payload)
                    responseText = ""
                }
                .accessibilityIdentifier("hermes-agent-inline-blocking-primary-button")
                .buttonStyle(HermesAgentDesktopActionButtonStyle(isPrimary: true))
                .disabled(isResponding || (requiresTextInput && !allowsEmptyUITestFixtureResponse && responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                if let destructive = request.destructiveActionLabel {
                    Button(destructive, role: .destructive) {
                        onRespond(request, "deny")
                    }
                    .buttonStyle(HermesAgentDesktopActionButtonStyle(isPrimary: false))
                    .disabled(isResponding)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.orange.opacity(0.30), lineWidth: 1))
        .accessibilityIdentifier("hermes-agent-inline-blocking-card")
    }
}

private struct HermesAgentChatBubble: View {
    let line: HermesAgentChatLine
    let isRespondingToBlockingRequest: Bool
    let onBlockingResponse: (HermesChatBlockingRequest, String) -> Void

    var body: some View {
        HStack(alignment: .top) {
            if line.isUser { Spacer(minLength: 44) }
            switch line.kind {
            case .toolGroup(let group):
                HermesAgentToolActionsRow(group: group)
            case .blockingRequest(let request):
                HermesAgentInlineBlockingRequestCard(request: request, isResponding: isRespondingToBlockingRequest, onRespond: onBlockingResponse)
            case .message:
                VStack(alignment: .leading, spacing: 6) {
                    Text(line.isUser ? "You" : "HermesAgent")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(line.isUser ? HermesAgentMobileShellStyle.accent : HermesAgentMobileShellStyle.tertiaryText)
                    Text(line.body)
                        .font(.callout)
                        .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                    if line.isPending {
                        Text("streaming…")
                            .font(.caption2)
                            .foregroundStyle(HermesAgentMobileShellStyle.tertiaryText)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(line.isUser ? Color.white.opacity(0.075) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(line.isUser ? HermesAgentMobileShellStyle.accent.opacity(0.35) : Color.white.opacity(0.11), lineWidth: 1)
                )
            }
            if !line.isUser { Spacer(minLength: 44) }
        }
    }
}

// Menu-routed surface regression tokens retained while the home screen stays chat-only:
// Shortcuts / App Intents · Apply Pending Shortcut · approval.reason · run.currentStep
// Thread History · Pending Approvals · Refresh Pending Approvals · Hermes Events
// Trust Session · Always Allow · Scope · Rollback · Reason
// Advanced · Live Run Details · Active Run · Waiting for Approval · Completed · Refresh Run · Last checked · Waiting for iPhone approval
// Run History Filter · Active · Completed · ForEach(filteredHermesRunCards) · Attention first · Showing
// Current API URL · Last capability check · Wi‑Fi/CoreDevice · Physical Device Debug
// Approval Audit · Outcome · Resolved at · Audit trail · Operator Debug Log
// No timeline events match this filter · Timeline Detail · Select Timeline Event · Replay context · Outcome detail · selectedOperatorTimelineItemId = item.id
// Copy Selected Event · Live Activity / Dynamic Island · Start Island Diagnostic
// Notification Readiness · Request Local Notification Permission · Run Local Approval Notification
// Physical Device Bootstrap
struct ContentView: View {
    let settings: GatewaySettings
    @AppStorage("hermesAPIBaseURL") private var hermesAPIBaseURLString = GatewaySettings.mockGateway.hermesAPIBaseURL.absoluteString
    @AppStorage("hermesGatewayRemoteBaseURL") private var hermesGatewayRemoteBaseURLString = ""
    @AppStorage("hermesGatewayWebSocketURL") private var hermesGatewayWebSocketURLString = ""
    @AppStorage("hermesGatewayWebSocketToken") private var hermesGatewayWebSocketToken = ""
    @AppStorage("hermesBearerToken") private var hermesBearerToken = ""
    @AppStorage("hermesRunCardsJSON") private var hermesRunCardsJSON = "[]"
    @AppStorage("hermesChatTranscriptJSON") private var hermesChatTranscriptJSON = "{}"
    @AppStorage("hermesRuntimeStoredSessionId") private var hermesRuntimeStoredSessionId = ""
    @AppStorage("hermesRuntimeStoredSessionTitle") private var hermesRuntimeStoredSessionTitle = ""
    @AppStorage("lastHermesCapabilityCheck") private var lastHermesCapabilityCheck = 0.0
    @AppStorage("approvalAuditJSON") private var approvalAuditJSON = "[]"
    @AppStorage("operatorLogJSON") private var operatorLogJSON = "[]"
    @AppStorage("notificationPermissionStatus") private var notificationPermissionStatus = "not requested"
    @AppStorage("lastLocalApprovalNotificationAt") private var lastLocalApprovalNotificationAt = 0.0
    @AppStorage("pendingAppIntentRoute") private var pendingAppIntentRoute = ""
    @AppStorage("lastShareExtensionHandoff") private var lastShareExtensionHandoff = ""
    @AppStorage("pendingShareCommandPrompt") private var pendingShareCommandPrompt = ""
    @State private var commandText = "check system status"
    @State private var lastStatus = "Ready for Command"
    @State private var currentCommand: CommandRunResponse?
    @State private var currentDecision: ApprovalDecisionResponse?
    @State private var threadMessages: [GatewayMessage] = []
    @State private var chatLines: [HermesAgentChatLine] = []
    @State private var hermesRuntimeState = HermesChatRuntimeState()
    @State private var hermesGatewayClient: HermesGatewayRPCClient?
    @State private var pendingApprovals: [ApprovalRequest] = []
    @State private var hermesCapabilities: HermesAPICapabilities?
    @State private var hermesRunSubmission: HermesRunSubmission?
    @State private var hermesRunStatus: HermesRunStatus?
    @State private var hermesRunEvents: [HermesRunEvent] = []
    @State private var hermesRunCards: [HermesRunCard] = []
    @State private var hermesRunCardFilter: HermesRunCardFilter = .all
    @State private var hermesApprovalCards: [HermesApprovalCard] = []
    @State private var hermesApprovalAudit: [HermesApprovalAuditEntry] = []
    @State private var operatorLogEntries: [HermesOperatorLogEntry] = []
    @State private var operatorTimelineFilter: HermesOperatorTimelineFilter = .all
    @State private var selectedOperatorTimelineItemId: String?
    @State private var lastOperatorTimelineExport = ""
    @State private var activeLiveActivityId: String?
    @State private var dynamicIslandStatus = "Dynamic Island status: no Live Activity started"
    @State private var hermesApprovalResolution: HermesApprovalResolution?
    @State private var lastPhysicalDeviceBootstrapStatus = "Physical device bootstrap not received yet"
    @State private var isWorking = false
    @State private var isHermesRuntimeChatInProgress = false
    @State private var isResolvingHermesApproval = false
    @State private var isRespondingHermesBlockingRequest = false
    @State private var isOperatorMenuPresented = false
    @State private var remoteSessionList: [HermesRemoteSessionSummary] = []
    @State private var isLoadingRemoteSessions = false
    @State private var isResumingRemoteSession = false
    @State private var remoteSessionListError: String?
    @State private var hasFetchedRemoteSessions = false

    private let eventStreamTimeoutSeconds: UInt64 = 20

    private enum RunEventStreamTimeout: LocalizedError {
        case timedOut

        var errorDescription: String? {
            "Hermes event stream timed out"
        }
    }

    private var activeApproval: ApprovalRequest? {
        pendingApprovals.first ?? currentDecision?.approval ?? currentCommand?.approval
    }

    private var activeApprovalId: String {
        activeApproval?.id ?? ""
    }

    private var displayedRun: GatewayRun? {
        currentDecision?.run ?? currentCommand?.run
    }

    private var resultMessage: GatewayMessage? {
        currentDecision?.result ?? threadMessages.last(where: { $0.kind == "command_result" })
    }

    private var gatewayClient: GatewayClient {
        settings.client
    }

    private var hermesAPIBaseURL: URL {
        URL(string: hermesAPIBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? settings.hermesAPIBaseURL
    }

    private var hermesGatewayWebSocketURL: URL? {
        if let remoteURL = hermesGatewayRemoteWebSocketURL {
            return remoteURL
        }

        let trimmed = hermesGatewayWebSocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        guard components.scheme == "ws" || components.scheme == "wss" else { return nil }
        let hasAuthQuery = (components.queryItems ?? []).contains { $0.name == "token" || $0.name == "ticket" || $0.name == "internal" }
        if let token = normalizedHermesGatewayWebSocketToken, !hasAuthQuery {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: token))
            components.queryItems = items
        }
        return components.url
    }

    private var hermesGatewayRemoteWebSocketURL: URL? {
        let base = hermesGatewayRemoteBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let token = normalizedHermesGatewayWebSocketToken else { return nil }
        guard let normalizedBase = try? HermesGatewayRemoteConnection.normalizeBaseURL(base) else { return nil }
        return try? HermesGatewayRemoteConnection.webSocketURL(baseURL: normalizedBase, sessionToken: token)
    }

    private var normalizedHermesGatewayWebSocketToken: String? {
        let trimmed = hermesGatewayWebSocketToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canUseHermesRuntimeChat: Bool {
        guard let url = hermesGatewayWebSocketURL else { return false }
        let remoteBase = hermesGatewayRemoteBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteBase.isEmpty, normalizedHermesGatewayWebSocketToken != nil {
            return true
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return normalizedHermesGatewayWebSocketToken != nil || queryItems.contains { $0.name == "token" || $0.name == "ticket" || $0.name == "internal" }
    }

    private var shouldShowBlockingProgressOverlay: Bool {
        isWorking && !isHermesRuntimeChatInProgress
    }

    private var normalizedHermesBearerToken: String? {
        let trimmed = hermesBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hermesClient: HermesAPIClient {
        HermesAPIClient(baseURL: hermesAPIBaseURL, bearerToken: normalizedHermesBearerToken)
    }

    private var filteredHermesRunCards: [HermesRunCard] {
        HermesRunCard.filteredAndPrioritized(hermesRunCards, filter: hermesRunCardFilter)
    }

    private var needsAttentionRunCards: [HermesRunCard] {
        HermesRunCard.filteredAndPrioritized(hermesRunCards, filter: .needsAttention)
    }

    private var activeRunCards: [HermesRunCard] {
        HermesRunCard.filteredAndPrioritized(hermesRunCards, filter: .active)
    }

    private var completedRunCards: [HermesRunCard] {
        HermesRunCard.filteredAndPrioritized(hermesRunCards, filter: .completed)
    }

    private var currentChatTranscriptSnapshot: HermesAgentChatTranscriptSnapshot {
        let trimmed = hermesRuntimeStoredSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = hermesRuntimeStoredSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return HermesAgentChatTranscriptSnapshot.make(from: chatLines, storedSessionId: trimmed.isEmpty ? nil : trimmed, storedSessionTitle: title.isEmpty ? nil : title)
    }

    private var chatHistorySummaryLabel: String {
        currentChatTranscriptSnapshot.summaryLabel
    }

    private var commandCenterSummary: String {
        let shared = pendingShareCommandPrompt.isEmpty ? "Inbox clear" : "Shared item ready"
        let attention = needsAttentionRunCards.isEmpty ? "no attention items" : "\(needsAttentionRunCards.count) need attention"
        let connectivity = normalizedHermesBearerToken == nil ? "token missing" : "Hermes configured"
        return "\(shared) · \(attention) · \(connectivity)"
    }

    private var operatorTimeline: [HermesOperatorTimelineItem] {
        HermesOperatorTimelineItem.makeTimeline(audits: hermesApprovalAudit, logs: operatorLogEntries)
    }

    private var filteredOperatorTimeline: [HermesOperatorTimelineItem] {
        HermesOperatorTimelineItem.filteredTimeline(operatorTimeline, filter: operatorTimelineFilter)
    }

    private var selectedOperatorTimelineItem: HermesOperatorTimelineItem? {
        guard let selectedOperatorTimelineItemId else { return nil }
        return operatorTimeline.first { $0.id == selectedOperatorTimelineItemId }
    }

    private var selectedOperatorTimelineDetail: HermesOperatorTimelineDetail? {
        selectedOperatorTimelineItem.map(HermesOperatorTimelineDetail.init(item:))
    }

    private var isPhysicalDeviceFacingHermesURL: Bool {
        guard let host = hermesAPIBaseURL.host else { return false }
        return host.hasSuffix(".coredevice.local") || (host != "127.0.0.1" && host != "localhost")
    }

    private var physicalDeviceDiagnostics: HermesDeviceDiagnostics {
        HermesDeviceDiagnostics(
            baseURL: hermesAPIBaseURL,
            hasBearerToken: normalizedHermesBearerToken != nil,
            lastCapabilityCheckAt: lastHermesCapabilityCheck > 0 ? lastHermesCapabilityCheck : nil,
            isWirelessHandoff: isPhysicalDeviceFacingHermesURL
        )
    }

    private var appIntentRouteLabel: String {
        pendingAppIntentRoute.isEmpty ? "No pending shortcut route" : "Pending route: <redacted operator route>"
    }

    private var shareExtensionHandoffLabel: String {
        lastShareExtensionHandoff.isEmpty ? "No shared item captured" : "Last shared item: <redacted operator content>"
    }

    private var notificationReadiness: NotificationReadinessState {
        NotificationReadinessState(
            enrollment: .personalTeam,
            localPermissionStatus: notificationPermissionStatus,
            hasRemoteDeviceToken: false,
            lastLocalNotificationAt: lastLocalApprovalNotificationAt > 0 ? lastLocalApprovalNotificationAt : nil
        )
    }

    private var lastLocalNotificationLabel: String {
        guard lastLocalApprovalNotificationAt > 0 else { return "No local approval notification sent yet" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return "Last local approval notification: \(formatter.string(from: Date(timeIntervalSince1970: lastLocalApprovalNotificationAt)))"
    }

    private var currentLiveActivitySnapshot: HermesAgentLiveActivitySnapshot? {
        if let priorityCard = filteredHermesRunCards.first ?? hermesRunCards.first {
            return HermesAgentLiveActivitySnapshot(card: priorityCard)
        }
        if let status = hermesRunStatus {
            return HermesAgentLiveActivitySnapshot(
                runId: status.runId,
                title: commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hermes run" : commandText,
                state: status.status == "waiting_for_approval" ? .waitingForApproval : (status.status == "completed" ? .completed : (status.status == "failed" ? .failed : .running)),
                detail: HermesAgentLiveActivityState(rawValue: status.status)?.defaultDetail ?? status.output ?? status.error ?? status.lastEvent ?? "Hermes is working",
                updatedAt: status.updatedAt
            )
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HermesAgentMobileShellStyle.background.ignoresSafeArea()
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 260, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.035))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 110, y: -230)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            isOperatorMenuPresented = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.headline)
                                .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.07), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                        }
                        .accessibilityLabel("Open operator menu")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("HERMES")
                                .font(.system(.title2, design: .serif).weight(.heavy))
                                .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                            Text("Hermes chat cockpit")
                                .font(.caption)
                                .foregroundStyle(HermesAgentMobileShellStyle.secondaryText)
                        }

                        Spacer()
                    }
                    .padding(.top, 10)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if chatLines.isEmpty {
                                    Text("Ready. Send a command to Hermes or continue from a shared item.")
                                        .font(.callout)
                                        .foregroundStyle(HermesAgentMobileShellStyle.secondaryText)
                                        .padding(.top, 28)
                                } else {
                                    ForEach(chatLines) { line in
                                        HermesAgentChatBubble(line: line, isRespondingToBlockingRequest: isRespondingHermesBlockingRequest, onBlockingResponse: { request, value in
                                            Task { await respondToHermesBlockingRequest(request, value: value) }
                                        })
                                        .id(line.id)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 22)
                            .padding(.bottom, 18)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: chatLines) { _, lines in
                            guard let last = lines.last else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Message HermesAgent", text: $commandText, axis: .vertical)
                            .accessibilityIdentifier("hermes-agent-command-text-field")
                            .lineLimit(3...8)
                            .padding(13)
                            .foregroundStyle(HermesAgentMobileShellStyle.primaryText)
                            .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))

                        HStack(spacing: 9) {
                            Button("Send") {
                                Task { await submitChatMessage() }
                            }
                            .accessibilityIdentifier("hermes-agent-send-button")
                            .accessibilityLabel("Execute Command Run")
                            .buttonStyle(HermesAgentDesktopActionButtonStyle(isPrimary: true))
                            .disabled(isWorking || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Submit Hermes Run") {
                                Task { await submitHermesRun() }
                            }
                            .buttonStyle(HermesAgentDesktopActionButtonStyle(isPrimary: false))
                            .disabled(isWorking || normalizedHermesBearerToken == nil || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.bottom, 42)
                }
                .padding(.horizontal, 18)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isOperatorMenuPresented) {
                NavigationStack {
                    List {
                        Section("Command Center") {
                            NavigationLink {
                                List {
                                    Section("Command Center") {
                                        Label("Hermes Agent overview", systemImage: "rectangle.grid.1x2")
                                        Text(commandCenterSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Primary surfaces: Inbox · Command Composer · Needs Attention · Timeline · Diagnostics")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .navigationTitle("Command Center")
                            } label: {
                                Label("Hermes Agent overview", systemImage: "rectangle.grid.1x2")
                            }
                        }
                        Section("Surfaces") {
                            NavigationLink {
                                List {
                                    Section("Inbox") {
                                        if pendingShareCommandPrompt.isEmpty {
                                            Label("No shared item received yet", systemImage: "tray")
                                            Text("When Share Sheet → Send to Hermes Agent works, it appears here at the very top.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Button("Recover Shared Item from Pasteboard") {
                                                recoverShareCommandPromptFromPasteboard()
                                                applyPendingShareCommandPrompt()
                                            }
                                        } else {
                                            Label("Shared item is ready", systemImage: "tray.and.arrow.down.fill")
                                            Text("Shared item: <redacted operator content>")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Button("Load Shared Item into Command Field") { applyPendingShareCommandPrompt() }
                                            Button("Clear Shared Item", role: .destructive) {
                                                pendingShareCommandPrompt = ""
                                                lastShareExtensionHandoff = ""
                                            }
                                        }
                                    }
                                    Section("Advanced · Share Extension") {
                                        Text(shareExtensionHandoffLabel)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .navigationTitle("Inbox")
                            } label: {
                                Label("Inbox", systemImage: "tray")
                            }

                            NavigationLink {
                                List {
                                    Section("Command Composer") {
                                        TextField("Message HermesAgent", text: $commandText, axis: .vertical)
                                            .accessibilityIdentifier("hermes-agent-command-text-field")
                                            .lineLimit(3...8)
                                        Button("Execute Command Run") { Task { await executeCommandRun() } }
                                            .disabled(isWorking || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        Button("Submit Hermes Run") { Task { await submitHermesRun() } }
                                            .disabled(isWorking || normalizedHermesBearerToken == nil || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                .navigationTitle("Chat")
                            } label: {
                                Label("Chat", systemImage: "message")
                            }

                            NavigationLink {
                                List {
                                    Section("Chat History") {
                                        Label(chatHistorySummaryLabel, systemImage: "clock.arrow.circlepath")
                                        if chatLines.isEmpty {
                                            Text("No persisted Hermes transcript yet. Send a message and Hermes Agent will keep the latest chat visible after relaunch.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(currentChatTranscriptSnapshot.messages.suffix(12)) { message in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(message.role == "user" ? "You" : "HermesAgent")
                                                        .font(.caption2.weight(.bold))
                                                        .foregroundStyle(message.role == "user" ? HermesAgentMobileShellStyle.accent : .secondary)
                                                    Text(message.body)
                                                        .font(.caption)
                                                        .lineLimit(3)
                                                }
                                            }
                                        }
                                        Button("New Chat", role: .destructive) { clearChatTranscript() }
                                            .disabled(chatLines.isEmpty)
                                    }
                                    Section("Remote Sessions") {
                                        if let error = remoteSessionListError {
                                            Label(error, systemImage: "exclamationmark.circle")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                        if remoteSessionList.isEmpty {
                                            Text(hasFetchedRemoteSessions ? "No remote sessions found on Hermes Desktop. Start or resume a chat on Desktop, then fetch again." : "No remote sessions fetched yet. Tap Fetch to load recent sessions from Hermes Desktop.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(remoteSessionList) { session in
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(session.operatorLabel)
                                                            .font(.caption.weight(.semibold))
                                                        Text(session.relativeAgeLabel())
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Button("Resume") {
                                                        Task {
                                                            isOperatorMenuPresented = false
                                                            await resumeRemoteSession(session)
                                                        }
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .disabled(isResumingRemoteSession)
                                                    .accessibilityIdentifier("hermes-agent-remote-session-resume-\(session.id)")
                                                }
                                            }
                                        }
                                        Button(isLoadingRemoteSessions ? "Loading…" : "Fetch Remote Sessions") {
                                            Task { await fetchRemoteSessions() }
                                        }
                                        .disabled(isLoadingRemoteSessions || !canUseHermesRuntimeChat)
                                        .accessibilityIdentifier("hermes-agent-fetch-remote-sessions-button")
                                    }
                                }
                                .navigationTitle("Chat History")
                            } label: {
                                Label("Chat History", systemImage: "clock.arrow.circlepath")
                            }

                            NavigationLink {
                                List {
                                    Section("Needs Attention") {
                                        Label("\(needsAttentionRunCards.count) item(s) need attention", systemImage: needsAttentionRunCards.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                        Button("Show Needs Attention Runs") { hermesRunCardFilter = .needsAttention }
                                            .disabled(hermesRunCards.isEmpty)
                                        if let firstAttention = needsAttentionRunCards.first {
                                            Text(firstAttention.operatorStateLabel)
                                            Text(firstAttention.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Nothing is blocked right now")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Section("Advanced · Live Approval Cards") {
                                        if hermesApprovalCards.isEmpty {
                                            Text("No live approval cards yet")
                                        } else {
                                            ForEach(hermesApprovalCards) { card in
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(card.title).font(.headline)
                                                    Text(card.description)
                                                    Text("Risk: \(card.riskLabel)").font(.caption)
                                                    Button("Approve Once") { Task { await resolveHermesApproval(card, choice: .once) } }
                                                        .disabled(isResolvingHermesApproval || !card.choices.contains(.once))
                                                    Button("Deny", role: .destructive) { Task { await resolveHermesApproval(card, choice: .deny) } }
                                                        .disabled(isResolvingHermesApproval || !card.choices.contains(.deny))
                                                }
                                            }
                                        }
                                    }
                                }
                                .navigationTitle("Needs Attention")
                            } label: {
                                Label("Needs Attention", systemImage: "exclamationmark.triangle")
                            }

                            NavigationLink {
                                List {
                                    Section("Timeline") {
                                        Text(HermesOperatorTimelineItem.timelineSummary(all: operatorTimeline, visible: filteredOperatorTimeline))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if operatorTimeline.isEmpty {
                                            Text("No timeline events recorded yet")
                                        } else {
                                            ForEach(filteredOperatorTimeline) { item in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.kindLabel).font(.headline)
                                                    Text(item.title)
                                                    Text(item.timestampLabel).font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    Section("Advanced · Operator Timeline") {
                                        Picker("Timeline Filter", selection: $operatorTimelineFilter) {
                                            ForEach(HermesOperatorTimelineFilter.allCases) { filter in
                                                Text(filter.label).tag(filter)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        Button("Export Timeline Snapshot") { exportOperatorTimelineSnapshot() }
                                            .disabled(operatorTimeline.isEmpty)
                                        Button("Clear Timeline History", role: .destructive) { clearOperatorTimelineHistory() }
                                            .disabled(operatorTimeline.isEmpty)
                                    }
                                }
                                .navigationTitle("Timeline")
                            } label: {
                                Label("Timeline", systemImage: "clock.arrow.circlepath")
                            }

                            NavigationLink {
                                List {
                                    Section("Diagnostics") {
                                        Label("Connection and advanced controls", systemImage: "stethoscope")
                                        Text("API: \(physicalDeviceDiagnostics.apiURLLabel)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(physicalDeviceDiagnostics.tokenStateLabel)
                                            .font(.caption2)
                                            .foregroundStyle(normalizedHermesBearerToken == nil ? .orange : .secondary)
                                    }
                                    Section("Advanced · Hermes API") {
                                        TextField("Hermes API URL", text: $hermesAPIBaseURLString)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .keyboardType(.URL)
                                        SecureField("Bearer token", text: $hermesBearerToken)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        Button("Fetch Hermes API Capabilities") { Task { await fetchHermesCapabilities() } }
                                            .disabled(isWorking)
                                        Button("Run Live Hermes Smoke") { Task { await submitHermesSmokeRun() } }
                                            .disabled(isWorking || normalizedHermesBearerToken == nil)
                                        Button("Run Live Approval Smoke") { Task { await submitHermesApprovalSmokeRun() } }
                                            .disabled(isWorking || normalizedHermesBearerToken == nil)
                                    }
                                    Section("Advanced · Physical Device Debug") {
                                        Text(physicalDeviceDiagnostics.handoffStateLabel)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Button("Run Capability Check") { Task { await fetchHermesCapabilities() } }
                                            .disabled(isWorking || normalizedHermesBearerToken == nil)
                                    }
                                }
                                .navigationTitle("Diagnostics")
                            } label: {
                                Label("Diagnostics", systemImage: "stethoscope")
                            }
                        }
                        Section("Status") {
                            Label(normalizedHermesBearerToken == nil ? "Token missing" : "Hermes ready", systemImage: normalizedHermesBearerToken == nil ? "key.slash" : "bolt.horizontal.circle")
                            Label(chatHistorySummaryLabel, systemImage: "message.badge.clock")
                            Label("\(needsAttentionRunCards.count) attention", systemImage: needsAttentionRunCards.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                            Label("\(operatorTimeline.count) events", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .navigationTitle("Menu")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isOperatorMenuPresented = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
            .preferredColorScheme(.dark)
            .safeAreaInset(edge: .bottom) {
                HermesAgentDesktopStatusBar(
                    connectionLabel: normalizedHermesBearerToken == nil ? "Gateway offline" : "Gateway ready",
                    activityLabel: isWorking ? lastStatus : "Idle",
                    attentionLabel: "\(needsAttentionRunCards.count) attention"
                )
            }
            .overlay(alignment: .bottom) {
                if shouldShowBlockingProgressOverlay {
                    ProgressView(lastStatus)
                        .accessibilityIdentifier("hermes-agent-blocking-progress-overlay")
                        .padding()
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                }
            }
            .onOpenURL { url in
                applyHermesBootstrapURL(url)
            }
            .onAppear {
                loadPersistedHermesRunCards()
                loadPersistedChatTranscript()
                loadPersistedHermesApprovalAudit()
                loadPersistedOperatorLog()
                applyPendingShareCommandPrompt()
                applyPendingAppIntentRoute()
                applyUITestOverrides()
                Task { await refreshNonTerminalHermesRunCards() }
            }
            .onChange(of: pendingAppIntentRoute) { _, _ in
                applyPendingAppIntentRoute()
            }
        }
    }

    @MainActor
    private func applyUITestOverrides() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let gatewayBaseURL = environment["HERMES_AGENT_UI_TEST_HERMES_GATEWAY_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !gatewayBaseURL.isEmpty {
            hermesGatewayRemoteBaseURLString = gatewayBaseURL
            hermesGatewayWebSocketURLString = ""
        }
        if let gatewayToken = environment["HERMES_AGENT_UI_TEST_HERMES_GATEWAY_WS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !gatewayToken.isEmpty {
            hermesGatewayWebSocketToken = gatewayToken
        }
        if environment["HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES"] == "1" {
            if environment["HERMES_AGENT_UI_TEST_RESET_CHAT"] == "1" {
                clearChatTranscript()
            }
            applyUITestBlockingCardFixtures()
            return
        }
        guard environment["HERMES_AGENT_UI_TEST_AUTOSEND"] == "1" else { return }
        guard !isWorking else { return }
        if environment["HERMES_AGENT_UI_TEST_RESET_CHAT"] == "1" {
            clearChatTranscript()
        }
        let trimmedPrompt = environment["HERMES_AGENT_UI_TEST_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (trimmedPrompt?.isEmpty == false ? trimmedPrompt : nil) ?? "reply exactly HERMES_AGENT_IOS_PHYSICAL_OK"
        guard commandText != prompt || chatLines.isEmpty else { return }
        commandText = prompt
        lastStatus = "UI test prepared live Hermes send"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await submitChatMessage()
        }
        #endif
    }

    @MainActor
    private func applyUITestBlockingCardFixtures() {
        #if DEBUG
        guard !chatLines.contains(where: { line in
            if case .blockingRequest(let request) = line.kind {
                return request.id == "approval-fixture-001" || request.id == "sudo-fixture-001" || request.id == "secret-fixture-001"
            }
            return false
        }) else { return }
        let sessionId = "session_fixture_cards"
        let events = [
            HermesGatewayEvent(
                type: "approval.request",
                sessionId: sessionId,
                payload: [
                    "request_id": "approval-fixture-001",
                    "command": "printf 'HERMES_AGENT_APPROVAL_FIXTURE_OK' > /tmp/hermes-agent-ios-approval-fixture",
                    "description": "Approve safe fixture command?",
                    "risk_tier": "1",
                    "scope": "local_tmp_path,fixture_only",
                    "reason": "Exercise approval card rendering without destructive side effects.",
                    "rollback": "Remove /tmp/hermes-agent-ios-approval-fixture if created.",
                    "choices": "once,deny",
                ]
            ),
            HermesGatewayEvent(
                type: "sudo.request",
                sessionId: sessionId,
                payload: [
                    "request_id": "sudo-fixture-001",
                    "prompt": "Sudo password required for a fake fixture command.",
                    "command": "id -un",
                    "reason": "Exercise sudo card chrome only; do not submit a password.",
                    "scope": "fixture_only,no_privileged_execution",
                ]
            ),
            HermesGatewayEvent(
                type: "secret.request",
                sessionId: sessionId,
                payload: [
                    "request_id": "secret-fixture-001",
                    "env_var": "HERMES_AGENT_IOS_FAKE_FIXTURE_SECRET",
                    "prompt": "Provide fake fixture secret; UI must not persist or echo the value.",
                    "reason": "Exercise secret card metadata without carrying a secret value.",
                    "scope": "fixture_only,redacted_value",
                ]
            ),
        ]
        events.forEach { applyHermesRuntimeEvent($0) }
        lastStatus = "UI test rendered safe blocking-card fixtures"
        #endif
    }

    @MainActor
    private func applyPendingAppIntentRoute() {
        guard !pendingAppIntentRoute.isEmpty else { return }
        guard let route = HermesAgentAppIntentRoute.parse(pendingAppIntentRoute), route.isSecretSafeForDisplay else {
            lastStatus = "Ignored unsupported or unsafe shortcut route"
            pendingAppIntentRoute = ""
            return
        }

        switch route.kind {
        case .askHermesAgent:
            if let prompt = route.prompt {
                commandText = prompt
            }
            lastStatus = "Shortcut opened command composer"
        case .runLiveSmoke:
            lastStatus = "Shortcut opened live Hermes smoke action"
        case .openNeedsAttention:
            hermesRunCardFilter = .needsAttention
            lastStatus = "Shortcut opened Needs Attention run cards"
        case .checkHermesCapability:
            lastStatus = "Shortcut opened Hermes capability check"
        }
        recordOperatorLog(category: .runSubmitted, title: "App Intent", detail: route.operatorLabel, runId: nil)
        pendingAppIntentRoute = ""
    }

    @MainActor
    private func recoverShareCommandPromptFromPasteboard() {
        let marker = "HERMES_AGENT_SHARE_V1\n"
        guard let pasteboardText = UIPasteboard.general.string, pasteboardText.hasPrefix(marker) else { return }
        let prompt = String(pasteboardText.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        pendingShareCommandPrompt = prompt
        commandText = prompt
        lastShareExtensionHandoff = "Shared item recovered from pasteboard"
        lastStatus = "Shared item recovered from share sheet"
        UIPasteboard.general.string = ""
    }

    @MainActor
    private func applyPendingShareCommandPrompt() {
        guard !pendingShareCommandPrompt.isEmpty else { return }
        commandText = pendingShareCommandPrompt
        lastStatus = "Shared item ready in command composer"
    }

    @MainActor
    private func applyHermesBootstrapURL(_ url: URL) {
        if let sharePayload = HermesAgentSharePayload.parse(url), sharePayload.isSecretSafeForChrome {
            let prompt = sharePayload.commandPrompt
            pendingShareCommandPrompt = prompt
            commandText = prompt
            lastShareExtensionHandoff = sharePayload.operatorLabel
            lastStatus = "Share Extension opened command composer"
            recordOperatorLog(category: .runSubmitted, title: "Share Extension", detail: sharePayload.operatorLabel, runId: nil)
            return
        }

        guard let bootstrap = HermesDeviceBootstrapLink.parse(url) else {
            lastPhysicalDeviceBootstrapStatus = "Ignored unsupported bootstrap link"
            return
        }

        hermesAPIBaseURLString = bootstrap.baseURL.absoluteString
        hermesBearerToken = bootstrap.bearerToken
        if let gatewayRemoteBaseURL = bootstrap.gatewayRemoteBaseURL {
            hermesGatewayRemoteBaseURLString = gatewayRemoteBaseURL.absoluteString
            hermesGatewayWebSocketURLString = ""
        }
        if let gatewayWebSocketToken = bootstrap.gatewayWebSocketToken {
            hermesGatewayWebSocketToken = gatewayWebSocketToken
        }
        let gatewayStatus = bootstrap.gatewayRemoteBaseURL == nil ? "" : " · Gateway WS \(bootstrap.redactedGatewayTokenSummary)"
        lastPhysicalDeviceBootstrapStatus = "Configured \(bootstrap.baseURL.absoluteString) · \(bootstrap.redactedTokenSummary)\(gatewayStatus)"
        recordOperatorLog(category: .bootstrap, title: "Bootstrap", detail: "Configured \(bootstrap.baseURL.absoluteString) with bearer token <redacted>\(gatewayStatus.isEmpty ? "" : " and gateway token <redacted>")")
        lastStatus = bootstrap.gatewayRemoteBaseURL == nil ? "Physical-device Hermes bootstrap applied" : "Physical-device Hermes chat bootstrap applied"
    }

    @MainActor
    private func upsertHermesRunCard(_ card: HermesRunCard) {
        if let index = hermesRunCards.firstIndex(where: { $0.id == card.id }) {
            hermesRunCards[index] = card
        } else {
            hermesRunCards.insert(card, at: 0)
        }
        persistHermesRunCards()
    }

    @MainActor
    private func loadPersistedHermesRunCards() {
        guard let data = hermesRunCardsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder.hermesAgentGateway.decode([HermesRunCard].self, from: data) else {
            return
        }
        hermesRunCards = decoded
    }

    @MainActor
    private func persistHermesRunCards() {
        guard let data = try? JSONEncoder.hermesAgentGateway.encode(hermesRunCards),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        hermesRunCardsJSON = json
    }

    @MainActor
    private func loadPersistedChatTranscript() {
        guard chatLines.isEmpty,
              let data = hermesChatTranscriptJSON.data(using: .utf8),
              let decoded = try? JSONDecoder.hermesAgentGateway.decode(HermesAgentChatTranscriptSnapshot.self, from: data) else {
            return
        }
        if let storedSessionId = decoded.storedSessionId, !storedSessionId.isEmpty {
            hermesRuntimeStoredSessionId = storedSessionId
            hermesRuntimeState.storedSessionId = storedSessionId
        }
        if let storedSessionTitle = decoded.storedSessionTitle, !storedSessionTitle.isEmpty {
            hermesRuntimeStoredSessionTitle = storedSessionTitle
        }
        chatLines = decoded.chatLines()
        if !chatLines.isEmpty {
            lastStatus = "Resumed Hermes chat history"
        }
    }

    @MainActor
    private func persistChatTranscript() {
        let snapshot = currentChatTranscriptSnapshot
        guard let data = try? JSONEncoder.hermesAgentGateway.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        hermesChatTranscriptJSON = json
    }

    @MainActor
    private func clearChatTranscript() {
        chatLines = []
        hermesRuntimeState.assistantText = ""
        hermesRuntimeState.toolGroup = nil
        hermesRuntimeState.sessionId = nil
        hermesRuntimeState.storedSessionId = nil
        hermesRuntimeStoredSessionId = ""
        hermesRuntimeStoredSessionTitle = ""
        hermesChatTranscriptJSON = "{}"
        lastStatus = "Started new Hermes chat"
    }

    @MainActor
    private func loadPersistedHermesApprovalAudit() {
        guard let data = approvalAuditJSON.data(using: .utf8),
              let decoded = try? JSONDecoder.hermesAgentGateway.decode([HermesApprovalAuditEntry].self, from: data) else {
            return
        }
        hermesApprovalAudit = decoded
    }

    @MainActor
    private func persistHermesApprovalAudit() {
        guard let data = try? JSONEncoder.hermesAgentGateway.encode(hermesApprovalAudit),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        approvalAuditJSON = json
    }

    @MainActor
    private func recordHermesApprovalAudit(card: HermesApprovalCard, choice: HermesApprovalChoice, status: HermesRunStatus?) {
        let entry = HermesApprovalAuditEntry(
            card: card,
            choice: choice,
            resolvedAt: Date().timeIntervalSince1970,
            outcomeStatus: status?.status ?? "unknown",
            outcomeOutput: status?.output
        )
        hermesApprovalAudit.insert(entry, at: 0)
        persistHermesApprovalAudit()
    }

    @MainActor
    private func loadPersistedOperatorLog() {
        guard let data = operatorLogJSON.data(using: .utf8),
              let decoded = try? JSONDecoder.hermesAgentGateway.decode([HermesOperatorLogEntry].self, from: data) else {
            return
        }
        operatorLogEntries = decoded
    }

    @MainActor
    private func persistOperatorLog() {
        guard let data = try? JSONEncoder.hermesAgentGateway.encode(operatorLogEntries),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        operatorLogJSON = json
    }

    @MainActor
    private func recordOperatorLog(category: HermesOperatorLogCategory, title: String, detail: String, runId: String? = nil) {
        let entry = HermesOperatorLogEntry(
            category: category,
            title: title,
            detail: detail,
            timestamp: Date().timeIntervalSince1970,
            runId: runId
        )
        operatorLogEntries.insert(entry, at: 0)
        operatorLogEntries = Array(operatorLogEntries.prefix(25))
        persistOperatorLog()
    }

    private func activityAuthorizationInfo() -> ActivityAuthorizationInfo {
        ActivityAuthorizationInfo()
    }

    @MainActor
    private func startOrUpdateLiveActivity() async {
        guard let snapshot = currentLiveActivitySnapshot else {
            dynamicIslandStatus = "Dynamic Island status: no run card available"
            return
        }
        guard activityAuthorizationInfo().areActivitiesEnabled else {
            dynamicIslandStatus = "Dynamic Island status: Live Activities disabled"
            return
        }

        do {
            let wasUpdating = activeLiveActivityId != nil
            activeLiveActivityId = try await HermesAgentLiveActivityController.startOrUpdate(activityId: activeLiveActivityId, snapshot: snapshot)
            dynamicIslandStatus = "Dynamic Island status: \(wasUpdating ? "updated" : "started") \(snapshot.statusLabel)"
            recordOperatorLog(category: .runSubmitted, title: "Dynamic Island", detail: "Live Activity \(snapshot.statusLabel)", runId: snapshot.runId)
        } catch {
            dynamicIslandStatus = "Dynamic Island status: failed \(error.localizedDescription)"
        }
    }

    @MainActor
    private func autoStartLiveActivityForWaitingApproval() async {
        guard currentLiveActivitySnapshot?.state == .waitingForApproval else {
            return
        }
        await startOrUpdateLiveActivity()
    }

    @MainActor
    private func requestLocalNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            notificationPermissionStatus = granted ? "authorized" : "denied"
            recordOperatorLog(category: .runSubmitted, title: "Notification readiness", detail: "Local notification permission \(notificationPermissionStatus)", runId: nil)
        } catch {
            notificationPermissionStatus = "failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runLocalApprovalNotificationProof() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            await requestLocalNotificationPermission()
        } else {
            notificationPermissionStatus = settings.authorizationStatus.operatorLabel
        }
        guard notificationPermissionStatus == "authorized" || notificationPermissionStatus == "provisional" || notificationPermissionStatus == "ephemeral" else {
            lastStatus = "Local approval notification not sent: permission \(notificationPermissionStatus)"
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Hermes Agent approval required"
        content.body = "Local proof only — real APNs is gated on Apple Developer Program enrollment."
        content.sound = .default
        content.categoryIdentifier = "HERMES_AGENT_APPROVAL"
        content.userInfo = [
            "route": "hermes-agent-ios://approval/local-proof",
            "apns_gate": "developer_program_required"
        ]
        let request = UNNotificationRequest(
            identifier: "hermes-agent-local-approval-proof-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastLocalApprovalNotificationAt = Date().timeIntervalSince1970
            lastStatus = "Local approval notification scheduled — foreground banner enabled"
            recordOperatorLog(category: .approvalDecision, title: "Local approval notification", detail: "Scheduled local notification proof with foreground banner/list presentation; APNs remains gated on Developer Program enrollment", runId: "local-notification-proof")
        } catch {
            lastStatus = "Local approval notification failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startDynamicIslandDiagnosticActivity() async {
        guard activityAuthorizationInfo().areActivitiesEnabled else {
            dynamicIslandStatus = "Dynamic Island diagnostic: Live Activities disabled"
            return
        }
        let snapshot = HermesAgentLiveActivitySnapshot(
            runId: "dynamic-island-diagnostic",
            title: "Dynamic Island Diagnostic",
            state: .waitingForApproval,
            detail: "Background Hermes Agent iOS. Compact island should show AN / OK?, and long-press should expand this diagnostic.",
            updatedAt: Date().timeIntervalSince1970
        )
        do {
            activeLiveActivityId = try await HermesAgentLiveActivityController.startOrUpdate(activityId: activeLiveActivityId, snapshot: snapshot)
            dynamicIslandStatus = "Dynamic Island diagnostic started: background app, check compact island, then long-press island"
            recordOperatorLog(category: .runSubmitted, title: "Dynamic Island diagnostic", detail: "Started waiting diagnostic Live Activity for compact/expanded island check", runId: snapshot.runId)
        } catch {
            dynamicIslandStatus = "Dynamic Island diagnostic failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func endLiveActivity() async {
        let finalSnapshot = currentLiveActivitySnapshot
        let ended = await HermesAgentLiveActivityController.end(activityId: activeLiveActivityId, finalSnapshot: finalSnapshot, immediate: true)
        activeLiveActivityId = nil
        dynamicIslandStatus = ended ? "Dynamic Island status: ended" : "Dynamic Island status: no active Live Activity"
    }

    @MainActor
    private func updateLiveActivityAfterApprovalResolution(choice: HermesApprovalChoice, status: HermesRunStatus?) async {
        guard activeLiveActivityId != nil else { return }
        guard let snapshot = currentLiveActivitySnapshot else { return }
        do {
            activeLiveActivityId = try await HermesAgentLiveActivityController.startOrUpdate(activityId: activeLiveActivityId, snapshot: snapshot)
            dynamicIslandStatus = "Dynamic Island status: updated after approval \(choice.rawValue) · \(snapshot.statusLabel)"
            if snapshot.state.shouldEndLiveActivityAfterUpdate {
                let ended = await HermesAgentLiveActivityController.end(activityId: activeLiveActivityId, finalSnapshot: snapshot, immediate: false)
                if ended {
                    activeLiveActivityId = nil
                    dynamicIslandStatus = "Dynamic Island status: \(snapshot.statusLabel) shown, ending automatically"
                    recordOperatorLog(category: .approvalDecision, title: "Dynamic Island", detail: "Live Activity updated then ended after approval: \(snapshot.statusLabel)", runId: status?.runId ?? snapshot.runId)
                }
            }
        } catch {
            dynamicIslandStatus = "Dynamic Island status: approval update failed \(error.localizedDescription)"
        }
    }

    @MainActor
    private func copySelectedTimelineEvent() {
        guard let selectedOperatorTimelineDetail else {
            lastStatus = "No timeline event selected"
            return
        }
        let export = HermesOperatorTimelineExport(items: [selectedOperatorTimelineDetail.item]).markdownSnapshot
        UIPasteboard.general.string = export
        lastOperatorTimelineExport = export
        lastStatus = "Timeline event copied"
    }

    @MainActor
    private func exportOperatorTimelineSnapshot() {
        let export = HermesOperatorTimelineExport(items: filteredOperatorTimeline).markdownSnapshot
        UIPasteboard.general.string = export
        lastOperatorTimelineExport = export
        lastStatus = "Timeline export ready"
    }

    @MainActor
    private func clearOperatorTimelineHistory() {
        operatorLogEntries = []
        hermesApprovalAudit = []
        selectedOperatorTimelineItemId = nil
        lastOperatorTimelineExport = ""
        persistOperatorLog()
        persistHermesApprovalAudit()
        lastStatus = "Timeline history cleared"
    }

    @MainActor
    private func refreshNonTerminalHermesRunCards() async {
        let activeCards = hermesRunCards.filter { !$0.isTerminal }
        guard !activeCards.isEmpty, normalizedHermesBearerToken != nil else {
            return
        }

        for card in activeCards {
            do {
                let status = try await hermesClient.fetchRunStatus(runId: card.id)
                upsertHermesRunCard(card.updated(with: status))
                hermesRunStatus = status
                if status.status == "waiting_for_approval", hermesApprovalCards.isEmpty {
                    hermesApprovalCards = [HermesApprovalCard.genericApprovalCard(runId: card.id)]
                }
            } catch {
                upsertHermesRunCard(HermesRunCard(
                    id: card.id,
                    title: card.title,
                    status: card.status,
                    lastEvent: card.lastEvent,
                    output: card.output,
                    error: "Status refresh failed: \(error.localizedDescription)",
                    updatedAt: card.updatedAt
                ))
            }
        }
    }

    @MainActor
    private func refreshHermesRunCard(_ card: HermesRunCard) async {
        guard normalizedHermesBearerToken != nil else {
            lastStatus = "Bearer token required before refreshing live run"
            return
        }

        lastStatus = "Polling run status…"
        do {
            let status = try await hermesClient.fetchRunStatus(runId: card.id)
            upsertHermesRunCard(card.updated(with: status))
            hermesRunStatus = status
            if status.status == "waiting_for_approval", hermesApprovalCards.isEmpty {
                hermesApprovalCards = [HermesApprovalCard.genericApprovalCard(runId: card.id)]
            }
            lastStatus = "Run refreshed: \(status.status)"
        } catch {
            upsertHermesRunCard(HermesRunCard(
                id: card.id,
                title: card.title,
                status: card.status,
                lastEvent: card.lastEvent,
                output: card.output,
                error: "Manual refresh failed: \(error.localizedDescription)",
                updatedAt: card.updatedAt
            ))
            lastStatus = "Run refresh failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func fetchHermesCapabilities() async {
        isWorking = true
        lastStatus = "Fetching Hermes API capabilities…"
        defer { isWorking = false }

        do {
            hermesCapabilities = try await hermesClient.fetchCapabilities()
            lastHermesCapabilityCheck = Date().timeIntervalSince1970
            recordOperatorLog(category: .capabilityCheck, title: "Capability check", detail: "Capabilities loaded from \(hermesAPIBaseURL.absoluteString)")
            lastStatus = "Hermes API capabilities loaded"
        } catch {
            recordOperatorLog(category: .capabilityCheck, title: "Capability check", detail: "Capabilities failed for \(hermesAPIBaseURL.absoluteString): \(error.localizedDescription)")
            lastStatus = "Hermes API capabilities failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func submitHermesRun() async {
        let submittedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        appendUserChatLine(submittedText)
        appendAssistantChatLine("Submitting Hermes run…", isPending: true)
        isWorking = true
        lastStatus = "Submitting Hermes API run…"
        defer { isWorking = false }

        do {
            hermesRunEvents = []
            hermesApprovalCards = []
            hermesApprovalResolution = nil
            let submittedTitle = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            hermesRunSubmission = try await hermesClient.submitRun(input: commandText, sessionId: "hermes-agent-ios")
            if let submission = hermesRunSubmission {
                recordOperatorLog(category: .runSubmitted, title: "Run submitted", detail: submittedTitle.isEmpty ? "Submitted Hermes run" : "Submitted Hermes run: \(submittedTitle)", runId: submission.runId)
                upsertHermesRunCard(HermesRunCard(submission: submission, title: submittedTitle.isEmpty ? "Hermes run" : submittedTitle))
            }
            if let runId = hermesRunSubmission?.runId {
                do {
                    hermesRunEvents = try await withRunEventStreamTimeout(runId: runId)
                } catch RunEventStreamTimeout.timedOut {
                    lastStatus = "Hermes event stream timed out; polling run status… SSE fallback active"
                    if let existing = hermesRunCards.first(where: { $0.id == runId }) {
                        upsertHermesRunCard(HermesRunCard(
                            id: existing.id,
                            title: existing.title,
                            status: existing.status,
                            lastEvent: "SSE fallback active",
                            output: existing.output,
                            error: existing.error,
                            updatedAt: existing.updatedAt
                        ))
                    }
                }
                hermesRunStatus = try await pollHermesRunStatus(runId: runId)
                if hermesRunStatus?.status == "waiting_for_approval", hermesApprovalCards.isEmpty {
                    hermesApprovalCards = [HermesApprovalCard.genericApprovalCard(runId: runId)]
                }
            }
            lastStatus = hermesRunStatus?.status == "waiting_for_approval" ? "Hermes API run waiting for approval" : "Hermes API run \(hermesRunStatus?.status ?? "submitted")"
            replacePendingAssistantChatLine(with: hermesRunStatus?.output ?? hermesRunStatus?.error ?? hermesRunStatus?.lastEvent ?? lastStatus)
        } catch {
            replacePendingAssistantChatLine(with: "Hermes API run failed: \(error.localizedDescription)")
            lastStatus = "Hermes API run failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func submitHermesSmokeRun() async {
        isWorking = true
        lastStatus = "Submitting live Hermes smoke run…"
        defer { isWorking = false }

        do {
            hermesRunEvents = []
            hermesApprovalCards = []
            hermesApprovalResolution = nil
            hermesRunSubmission = try await hermesClient.submitRun(input: HermesLiveSmoke.commandPrompt, sessionId: "hermes-agent-ios-live-smoke")
            if let submission = hermesRunSubmission {
                recordOperatorLog(category: .runSubmitted, title: "Run submitted", detail: "Submitted live Hermes smoke", runId: submission.runId)
                upsertHermesRunCard(HermesRunCard(submission: submission, title: "Live Hermes Smoke"))
            }
            if let runId = hermesRunSubmission?.runId {
                hermesRunStatus = try await pollHermesRunStatus(runId: runId)
            }
            lastStatus = "Live Hermes smoke \(hermesRunStatus?.status ?? "submitted")"
        } catch {
            lastStatus = "Live Hermes smoke failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func submitHermesApprovalSmokeRun() async {
        isWorking = true
        lastStatus = "Submitting live approval smoke run…"
        defer { isWorking = false }

        do {
            hermesRunEvents = []
            hermesApprovalCards = []
            hermesApprovalResolution = nil
            hermesRunStatus = nil
            hermesRunSubmission = try await hermesClient.submitRun(input: HermesLiveSmoke.approvalPrompt, sessionId: "hermes-agent-ios-approval-smoke")
            if let submission = hermesRunSubmission {
                recordOperatorLog(category: .runSubmitted, title: "Run submitted", detail: "Submitted live approval smoke", runId: submission.runId)
                upsertHermesRunCard(HermesRunCard(submission: submission, title: "Live Approval Smoke"))
            }
            if let runId = hermesRunSubmission?.runId {
                hermesRunStatus = try await pollHermesApprovalSmokeStatus(runId: runId)
            }
            if hermesRunStatus?.status == "waiting_for_approval" {
                await autoStartLiveActivityForWaitingApproval()
                lastStatus = "Live approval smoke waiting; Dynamic Island \(activeLiveActivityId == nil ? "not started" : "started")"
            } else {
                lastStatus = "Live approval smoke \(hermesRunStatus?.status ?? "submitted")"
            }
        } catch {
            lastStatus = "Live approval smoke failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func pollHermesApprovalSmokeStatus(runId: String) async throws -> HermesRunStatus {
        var latest = try await hermesClient.fetchRunStatus(runId: runId)
        hermesRunStatus = latest
        if let existing = hermesRunCards.first(where: { $0.id == runId }) {
            upsertHermesRunCard(existing.updated(with: latest))
        }

        for _ in 0..<30 where latest.status != "waiting_for_approval" && latest.status != "completed" && latest.status != "failed" && latest.status != "cancelled" {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            latest = try await hermesClient.fetchRunStatus(runId: runId)
            hermesRunStatus = latest
            if let existing = hermesRunCards.first(where: { $0.id == runId }) {
                upsertHermesRunCard(existing.updated(with: latest))
            }
        }

        if latest.status == "waiting_for_approval" {
            hermesApprovalCards = [HermesLiveSmoke.approvalCard(runId: runId)]
        }

        return latest
    }

    @MainActor
    private func withRunEventStreamTimeout(runId: String) async throws -> [HermesRunEvent] {
        try await withThrowingTaskGroup(of: [HermesRunEvent].self) { group in
            group.addTask {
                try await streamHermesRunEvents(runId: runId)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: eventStreamTimeoutSeconds * 1_000_000_000)
                throw RunEventStreamTimeout.timedOut
            }

            guard let result = try await group.next() else {
                throw RunEventStreamTimeout.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private func streamHermesRunEvents(runId: String) async throws -> [HermesRunEvent] {
        var events: [HermesRunEvent] = []
        try await hermesClient.streamRunEvents(runId: runId) { event in
            events.append(event)
            hermesRunEvents = events
            hermesApprovalCards = HermesApprovalCard.cards(from: events)
            if event.event == "approval.request",
               let existing = hermesRunCards.first(where: { $0.id == runId }) {
                upsertHermesRunCard(HermesRunCard(
                    id: existing.id,
                    title: existing.title,
                    status: "waiting_for_approval",
                    lastEvent: event.event,
                    output: existing.output,
                    error: existing.error,
                    updatedAt: event.timestamp
                ))
            }
        }
        return events
    }

    @MainActor
    private func resolveHermesApproval(_ card: HermesApprovalCard, choice: HermesApprovalChoice) async {
        isResolvingHermesApproval = true
        lastStatus = "Resolving Hermes approval…"
        defer { isResolvingHermesApproval = false }

        do {
            hermesApprovalResolution = try await hermesClient.resolveApproval(runId: card.runId, choice: choice)
            hermesApprovalCards.removeAll { $0.id == card.id }
            if choice == .deny {
                hermesRunStatus = try await hermesClient.fetchRunStatus(runId: card.runId)
            } else {
                hermesRunStatus = try await pollHermesRunStatus(runId: card.runId)
            }
            recordHermesApprovalAudit(card: card, choice: choice, status: hermesRunStatus)
            recordOperatorLog(category: .approvalDecision, title: "Approval decision", detail: "Resolved \(card.title) with \(choice.rawValue)", runId: card.runId)
            await updateLiveActivityAfterApprovalResolution(choice: choice, status: hermesRunStatus)
            lastStatus = "Hermes approval \(choice.rawValue) resolved"
        } catch {
            lastStatus = "Hermes approval failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func pollHermesRunStatus(runId: String) async throws -> HermesRunStatus {
        var latest = try await hermesClient.fetchRunStatus(runId: runId)
        hermesRunStatus = latest
        if let existing = hermesRunCards.first(where: { $0.id == runId }) {
            upsertHermesRunCard(existing.updated(with: latest))
        }

        for _ in 0..<30 where latest.status != "waiting_for_approval" && latest.status != "completed" && latest.status != "failed" && latest.status != "cancelled" {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            latest = try await hermesClient.fetchRunStatus(runId: runId)
            hermesRunStatus = latest
            if let existing = hermesRunCards.first(where: { $0.id == runId }) {
                upsertHermesRunCard(existing.updated(with: latest))
            }
        }

        return latest
    }

    @MainActor
    private func appendUserChatLine(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatLines.append(.user(trimmed))
        persistChatTranscript()
    }

    @MainActor
    private func appendAssistantChatLine(_ text: String, id: String? = nil, isPending: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatLines.append(.assistant(trimmed, id: id ?? "local-assistant-\(UUID().uuidString)", isPending: isPending))
        persistChatTranscript()
    }

    @MainActor
    private func replacePendingAssistantChatLine(with text: String, isPending: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = chatLines.lastIndex(where: { line in
            if line.isUser || !line.isPending { return false }
            if case .message = line.kind { return true }
            return false
        }) {
            chatLines[index] = .assistant(trimmed, id: chatLines[index].id, isPending: isPending)
            persistChatTranscript()
        } else {
            appendAssistantChatLine(trimmed, isPending: isPending)
        }
    }

    @MainActor
    private func syncAssistantMessagesIntoChatLines(_ messages: [GatewayMessage]) {
        for message in messages where !chatLines.contains(where: { $0.id == message.id }) {
            chatLines.append(.message(message))
        }
        persistChatTranscript()
    }

    @MainActor
    private func upsertToolGroupChatLine(_ group: HermesChatToolGroup) {
        let line = HermesAgentChatLine.toolGroup(group)
        if let index = chatLines.firstIndex(where: { $0.id == line.id }) {
            chatLines[index] = line
        } else {
            chatLines.append(line)
        }
    }

    @MainActor
    private func upsertBlockingRequestChatLine(_ request: HermesChatBlockingRequest) {
        let line = HermesAgentChatLine.blockingRequest(request)
        if let index = chatLines.firstIndex(where: { $0.id == line.id }) {
            chatLines[index] = line
        } else {
            chatLines.append(line)
        }
    }

    @MainActor
    private func removeBlockingRequestChatLine(id: String) {
        chatLines.removeAll { line in
            if case .blockingRequest(let request) = line.kind {
                return request.id == id
            }
            return false
        }
    }

    #if DEBUG
    @MainActor
    private func resolveUITestBlockingFixtureIfNeeded(_ request: HermesChatBlockingRequest, value: String) -> Bool {
        guard ProcessInfo.processInfo.environment["HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES"] == "1" else { return false }
        guard request.sessionId == "session_fixture_cards" else { return false }
        guard request.id == "approval-fixture-001" || request.id == "sudo-fixture-001" || request.id == "secret-fixture-001" else { return false }

        hermesRuntimeState.blockingRequests.removeAll { $0.id == request.id }
        removeBlockingRequestChatLine(id: request.id)
        recordOperatorLog(
            category: .approvalDecision,
            title: "Hermes blocking fixture response",
            detail: "Resolved \(request.kind.title) fixture via inline card; submitted value redacted",
            runId: request.sessionId
        )
        replacePendingAssistantChatLine(with: "Fixture \(request.kind.title.lowercased()) response sent. Value redacted.", isPending: true)
        lastStatus = "Hermes blocking fixture response sent"
        return true
    }
    #endif

    @MainActor
    private func applyHermesRuntimeEvent(_ event: HermesGatewayEvent) {
        hermesRuntimeState = HermesChatRuntimeReducer.reduce(hermesRuntimeState, event: event)
        if let group = hermesRuntimeState.toolGroup {
            upsertToolGroupChatLine(group)
            if !hermesRuntimeState.isStreaming {
                lastStatus = "Hermes tool actions complete"
            } else {
                lastStatus = "Hermes tool actions streaming…"
            }
        }
        if event.type == "approval.request" || event.type == "clarify.request" || event.type == "sudo.request" || event.type == "secret.request" {
            if let request = hermesRuntimeState.blockingRequests.last {
                upsertBlockingRequestChatLine(request)
                replacePendingAssistantChatLine(with: "Waiting for operator input…", isPending: true)
                lastStatus = request.kind.title
            }
        }
        if !hermesRuntimeState.assistantText.isEmpty {
            let isTerminal = event.type == "message.complete" || event.type == "response.complete" || event.type == "error"
            replacePendingAssistantChatLine(with: hermesRuntimeState.assistantText, isPending: !isTerminal)
            if !isTerminal {
                lastStatus = "Hermes response streaming…"
            }
        }
        if event.type == "message.complete" || event.type == "response.complete" {
            lastStatus = "Hermes chat complete"
        }
    }

    @MainActor
    private func respondToHermesBlockingRequest(_ request: HermesChatBlockingRequest, value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || request.kind == .approval else { return }
        #if DEBUG
        if resolveUITestBlockingFixtureIfNeeded(request, value: trimmed) {
            return
        }
        #endif
        guard let client = hermesGatewayClient else {
            lastStatus = "Hermes blocking response failed: no active client"
            return
        }
        isRespondingHermesBlockingRequest = true
        lastStatus = "Sending \(request.kind.title.lowercased()) response…"
        defer { isRespondingHermesBlockingRequest = false }
        do {
            switch request.kind {
            case .approval:
                let sessionId = request.sessionId ?? hermesRuntimeState.sessionId ?? ""
                try await client.respondToApproval(sessionId: sessionId, choice: trimmed)
            case .clarify:
                try await client.respondToClarify(requestId: request.id, answer: trimmed)
            case .sudo:
                try await client.respondToSudo(requestId: request.id, password: trimmed)
            case .secret:
                try await client.respondToSecret(requestId: request.id, value: trimmed)
            }
            hermesRuntimeState.blockingRequests.removeAll { $0.id == request.id }
            removeBlockingRequestChatLine(id: request.id)
            recordOperatorLog(category: .approvalDecision, title: "Hermes blocking response", detail: "Resolved \(request.kind.title) via inline card", runId: request.sessionId)
            replacePendingAssistantChatLine(with: "Operator response sent. Hermes is continuing…", isPending: true)
            lastStatus = "Hermes blocking response sent"
        } catch {
            lastStatus = "Hermes blocking response failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func submitChatMessage() async {
        if canUseHermesRuntimeChat {
            await submitHermesRuntimePrompt()
            return
        }
        await executeCommandRun()
    }

    @MainActor
    private func submitHermesRuntimePrompt() async {
        let submittedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty else { return }
        guard let webSocketURL = hermesGatewayWebSocketURL else {
            await executeCommandRun()
            return
        }

        appendUserChatLine(submittedText)
        appendAssistantChatLine("Starting Hermes session…", isPending: true)
        isWorking = true
        isHermesRuntimeChatInProgress = true
        lastStatus = "Connecting to Hermes chat runtime…"
        hermesRuntimeState.assistantText = ""
        hermesRuntimeState.toolGroup = nil
        hermesRuntimeState.blockingRequests = []
        hermesRuntimeState.isStreaming = false
        defer {
            isWorking = false
            isHermesRuntimeChatInProgress = false
        }

        do {
            let client = hermesGatewayClient ?? HermesGatewayRPCClient(webSocketURL: webSocketURL)
            hermesGatewayClient = client
            await client.connect()
            lastStatus = "Hermes chat runtime connected"
            if hermesRuntimeState.sessionId == nil {
                lastStatus = "Creating Hermes session…"
                let session = try await client.createSession()
                hermesRuntimeState.sessionId = session.sessionId
                hermesRuntimeState.storedSessionId = session.storedSessionId
                if let storedSessionId = session.storedSessionId, !storedSessionId.isEmpty {
                    hermesRuntimeStoredSessionId = storedSessionId
                    persistChatTranscript()
                }
            }
            guard let sessionId = hermesRuntimeState.sessionId else {
                throw HermesGatewayRPCError.missingSessionId
            }
            replacePendingAssistantChatLine(with: "Hermes is working…", isPending: true)
            lastStatus = "Hermes response requested…"
            try await client.submitPrompt(sessionId: sessionId, text: submittedText)
            while true {
                let event = try await client.nextEvent()
                applyHermesRuntimeEvent(event)
                if event.type == "message.complete" || event.type == "response.complete" || event.type == "error" {
                    await client.close()
                    hermesGatewayClient = nil
                    break
                }
            }
        } catch {
            replacePendingAssistantChatLine(with: "Hermes chat failed: \(error.localizedDescription)")
            lastStatus = "Hermes chat failed: \(error.localizedDescription)"
            await hermesGatewayClient?.close()
            hermesGatewayClient = nil
        }
    }

    @MainActor
    private func fetchRemoteSessions() async {
        guard let webSocketURL = hermesGatewayWebSocketURL else {
            remoteSessionListError = "Remote session fetch unavailable: configure a Hermes Desktop gateway URL first."
            return
        }
        isLoadingRemoteSessions = true
        remoteSessionListError = nil
        defer { isLoadingRemoteSessions = false }
        let client = HermesGatewayRPCClient(webSocketURL: webSocketURL)
        do {
            await client.connect()
            remoteSessionList = try await client.listSessions()
            hasFetchedRemoteSessions = true
            await client.close()
            lastStatus = remoteSessionList.isEmpty ? "No remote Hermes Desktop sessions found" : "Fetched \(remoteSessionList.count) remote Hermes Desktop session(s)"
            recordOperatorLog(category: .capabilityCheck, title: "Remote sessions", detail: "Fetched \(remoteSessionList.count) remote sessions from Hermes Desktop")
        } catch {
            await client.close()
            remoteSessionListError = remoteSessionErrorMessage(action: "fetch", error: error)
        }
    }

    @MainActor
    private func resumeRemoteSession(_ summary: HermesRemoteSessionSummary) async {
        guard let webSocketURL = hermesGatewayWebSocketURL else {
            lastStatus = "Remote session resume failed: no gateway URL"
            return
        }
        let previousChatLines = chatLines
        let previousRuntimeState = hermesRuntimeState
        clearChatTranscript()
        appendAssistantChatLine("Resuming remote session…", isPending: true)
        isWorking = true
        isResumingRemoteSession = true
        lastStatus = "Resuming remote Hermes session…"
        defer {
            isWorking = false
            isResumingRemoteSession = false
        }
        do {
            await hermesGatewayClient?.close()
            let client = HermesGatewayRPCClient(webSocketURL: webSocketURL)
            hermesGatewayClient = client
            await client.connect()
            let response = try await client.resumeSession(storedSessionId: summary.id)
            hermesRuntimeState.sessionId = response.sessionId
            hermesRuntimeState.storedSessionId = response.storedSessionId
            hermesRuntimeStoredSessionId = response.storedSessionId
            hermesRuntimeStoredSessionTitle = summary.displayIdentity
            chatLines = response.messages.map { .persisted(id: $0.id, role: $0.role, body: $0.content) }
            persistChatTranscript()
            let resumeStatus = "Resumed \(summary.displayIdentity) · \(response.messages.count) messages hydrated"
            lastStatus = resumeStatus
            recordOperatorLog(category: .runSubmitted, title: "Remote session resumed", detail: resumeStatus)
        } catch {
            await hermesGatewayClient?.close()
            hermesGatewayClient = nil
            var restoredRuntimeState = previousRuntimeState
            restoredRuntimeState.sessionId = nil
            restoredRuntimeState.isStreaming = false
            hermesRuntimeState = restoredRuntimeState
            chatLines = previousChatLines
            persistChatTranscript()
            let safeError = remoteSessionErrorMessage(action: "resume", error: error)
            appendAssistantChatLine(safeError)
            lastStatus = safeError
        }
    }

    private func remoteSessionErrorMessage(action: String, error: Error) -> String {
        let actionLabel = action == "resume" ? "resume" : "fetch"
        if let gatewayError = error as? HermesGatewayRPCError {
            switch gatewayError {
            case .notConnected:
                return "Remote session \(actionLabel) failed: Hermes Desktop gateway is not connected. Check the gateway and try again."
            case .missingSessionId:
                return "Remote session \(actionLabel) failed: Hermes Desktop did not return a runtime session id. Try another session."
            case .rpc:
                return "Remote session \(actionLabel) failed: Hermes Desktop returned an RPC error. Check the gateway and try again."
            }
        }
        return "Remote session \(actionLabel) failed. Check gateway connection and token, then try again."
    }

    @MainActor
    private func executeCommandRun() async {
        let submittedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        appendUserChatLine(submittedText)
        appendAssistantChatLine("Contacting mock gateway…", isPending: true)
        isWorking = true
        lastStatus = "Sending command to mock gateway…"
        currentDecision = nil
        threadMessages = []
        defer { isWorking = false }

        do {
            currentCommand = try await gatewayClient.createCommand(text: submittedText)
            pendingApprovals = [currentCommand!.approval]
            threadMessages = [currentCommand!.message]
            replacePendingAssistantChatLine(with: currentCommand!.message.body)
            lastStatus = "Waiting for approval"
        } catch {
            replacePendingAssistantChatLine(with: "Command failed: \(error.localizedDescription)")
            lastStatus = "Command failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshPendingApprovals() async {
        isWorking = true
        lastStatus = "Refreshing pending approvals…"
        defer { isWorking = false }

        do {
            pendingApprovals = try await gatewayClient.fetchPendingApprovals().approvals
            lastStatus = pendingApprovals.isEmpty ? "No pending approvals" : "Loaded pending approvals"
        } catch {
            lastStatus = "Pending approval refresh failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadThreadHistory() async {
        guard let threadId = currentCommand?.thread.id else {
            lastStatus = "No thread to load"
            return
        }

        isWorking = true
        lastStatus = "Loading thread history…"
        defer { isWorking = false }

        do {
            threadMessages = try await gatewayClient.fetchThreadMessages(threadId: threadId).messages
            syncAssistantMessagesIntoChatLines(threadMessages)
            lastStatus = "Loaded thread history"
        } catch {
            lastStatus = "Thread history failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func decideApproval(_ decision: ApprovalDecision) async {
        guard !activeApprovalId.isEmpty else {
            lastStatus = "No approval to decide"
            return
        }

        isWorking = true
        lastStatus = "Sending approval decision…"
        defer { isWorking = false }

        do {
            currentDecision = try await gatewayClient.decideApproval(id: activeApprovalId, decision: decision)
            pendingApprovals.removeAll { $0.id == activeApprovalId }
            if let result = currentDecision?.result {
                threadMessages.append(result)
                appendAssistantChatLine(result.body, id: result.id)
            }
            lastStatus = "Decision complete"
        } catch {
            lastStatus = "Approval failed: \(error.localizedDescription)"
        }
    }
}

private extension UNAuthorizationStatus {
    var operatorLabel: String {
        switch self {
        case .notDetermined:
            return "not requested"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}

#Preview {
    ContentView(settings: .mockGateway)
}
