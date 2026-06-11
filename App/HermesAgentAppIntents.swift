import AppIntents
import Foundation
import HermesAgentCore

private enum HermesAgentIntentStore {
    static let pendingRouteKey = "pendingAppIntentRoute"

    static func save(_ route: HermesAgentAppIntentRoute) {
        UserDefaults.standard.set(route.storageValue, forKey: pendingRouteKey)
    }
}

struct AskHermesAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Hermes Agent"
    static let description = IntentDescription("Open Hermes Agent iOS with a prompt ready in the command composer.")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt", default: "brief me")
    var prompt: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let route = HermesAgentAppIntentRoute.askHermesAgent(prompt: prompt)
        HermesAgentIntentStore.save(route)
        return .result(dialog: IntentDialog(stringLiteral: route.confirmationDialog))
    }
}

struct RunLiveSmokeIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Live Smoke"
    static let description = IntentDescription("Open Hermes Agent iOS at the live Hermes smoke action.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let route = HermesAgentAppIntentRoute.runLiveSmoke
        HermesAgentIntentStore.save(route)
        return .result(dialog: IntentDialog(stringLiteral: route.confirmationDialog))
    }
}

struct OpenNeedsAttentionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Needs Attention"
    static let description = IntentDescription("Open Hermes Agent iOS filtered to run cards that need operator attention.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let route = HermesAgentAppIntentRoute.openNeedsAttention
        HermesAgentIntentStore.save(route)
        return .result(dialog: IntentDialog(stringLiteral: route.confirmationDialog))
    }
}

struct CheckHermesCapabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Hermes Capability"
    static let description = IntentDescription("Open Hermes Agent iOS at the Hermes capability check.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let route = HermesAgentAppIntentRoute.checkHermesCapability
        HermesAgentIntentStore.save(route)
        return .result(dialog: IntentDialog(stringLiteral: route.confirmationDialog))
    }
}

struct HermesAgentShortcutsProvider: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskHermesAgentIntent(),
            phrases: ["Ask \(.applicationName)", "Tell \(.applicationName)"],
            shortTitle: "Ask Hermes Agent",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: RunLiveSmokeIntent(),
            phrases: ["Run live smoke in \(.applicationName)"],
            shortTitle: "Live Smoke",
            systemImageName: "bolt.horizontal.circle"
        )
        AppShortcut(
            intent: OpenNeedsAttentionIntent(),
            phrases: ["Open needs attention in \(.applicationName)"],
            shortTitle: "Needs Attention",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: CheckHermesCapabilityIntent(),
            phrases: ["Check Hermes in \(.applicationName)"],
            shortTitle: "Check Hermes",
            systemImageName: "server.rack"
        )
    }
}
