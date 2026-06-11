import ActivityKit
import WidgetKit
import SwiftUI
import HermesAgentCore

@main
struct HermesAgentLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        HermesAgentLiveActivityWidget()
    }
}

struct HermesAgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HermesAgentLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(context.state.statusLabel, systemImage: context.state.dynamicIslandMinimalSymbolName)
                    Spacer()
                    Text(context.state.dynamicIslandCompactLabel)
                        .font(.caption.weight(.bold))
                }
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(context.state.stalenessLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.86))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.statusLabel, systemImage: context.state.dynamicIslandMinimalSymbolName)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.dynamicIslandCompactLabel)
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: context.state.dynamicIslandMinimalSymbolName)
                        .imageScale(.small)
                    Text(context.state.dynamicIslandCompactLeadingLabel)
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(context.state.state == .waitingForApproval ? .orange : .cyan)
            } compactTrailing: {
                Text(context.state.dynamicIslandCompactTrailingLabel)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(context.state.state == .waitingForApproval ? .orange : .cyan)
            } minimal: {
                Image(systemName: context.state.dynamicIslandMinimalSymbolName)
                    .foregroundStyle(context.state.state == .waitingForApproval ? .orange : .cyan)
            }
            .keylineTint(context.state.state == .waitingForApproval ? .orange : .cyan)
        }
    }
}
