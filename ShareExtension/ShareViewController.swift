import HermesAgentCore
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let pasteboardMarker = "HERMES_AGENT_SHARE_V1\n"

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let previewLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var capturedPayload: HermesAgentSharePayload?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureView()
        Task { await loadPreview() }
    }

    private func configureView() {
        titleLabel.text = "Send to HermesAgent"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        statusLabel.text = "Capturing shared item…"
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        previewLabel.text = "No shared item captured yet"
        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.textAlignment = .left
        previewLabel.numberOfLines = 8
        previewLabel.backgroundColor = .secondarySystemBackground
        previewLabel.layer.cornerRadius = 12
        previewLabel.layer.masksToBounds = true

        openButton.setTitle("Open Hermes Agent with Shared Item", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.isEnabled = false
        openButton.addTarget(self, action: #selector(openHermesAgentTapped), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, previewLabel, openButton, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previewLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
    }

    @MainActor
    private func loadPreview() async {
        let payload = await collectSharePayload()
        capturedPayload = payload
        guard !payload.isEmpty else {
            statusLabel.text = "No supported text, URL, or image metadata found."
            previewLabel.text = "No shared item captured"
            openButton.isEnabled = false
            return
        }
        statusLabel.text = "Shared item captured. Tap the button below to open Hermes Agent."
        previewLabel.text = payload.previewText
        openButton.isEnabled = payload.handoffURL != nil && payload.isSecretSafeForChrome
    }

    @objc private func openHermesAgentTapped() {
        Task { await openHermesAgentWithSharedContent() }
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @MainActor
    private func openHermesAgentWithSharedContent() async {
        guard let payload = capturedPayload,
              let handoffURL = payload.handoffURL,
              payload.isSecretSafeForChrome else {
            statusLabel.text = "Unable to open Hermes Agent: unsupported or unsafe shared item."
            return
        }

        UIPasteboard.general.string = Self.pasteboardMarker + payload.commandPrompt
        statusLabel.text = "Opening HermesAgent… If iOS returns here, open Hermes Agent manually; the item is staged."

        var opened = openContainingAppViaResponderChain(handoffURL)
        if !opened {
            opened = await extensionContext?.open(handoffURL) ?? false
        }
        if opened {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            statusLabel.text = "Shared item staged. Open Hermes Agent manually to continue."
            openButton.setTitle("Open Hermes Agent Manually After Closing", for: .normal)
        }
    }

    @MainActor
    private func openContainingAppViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func collectSharePayload() async -> HermesAgentSharePayload {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            return HermesAgentSharePayload(text: "Shared item from iOS share sheet")
        }

        let title = item.attributedTitle?.string ?? item.attributedContentText?.string
        let providers = item.attachments ?? []
        var capturedURL: URL?
        var capturedText: String?

        for provider in providers {
            if capturedURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                capturedURL = await loadURL(from: provider)
            }
            if capturedText == nil, provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                capturedText = await loadText(from: provider)
            }
            if capturedURL != nil && capturedText != nil { break }
        }

        if capturedText == nil, providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            capturedText = "Shared image attachment from iOS share sheet. Ask Hermes Agent to inspect or triage it after opening the app."
        }

        return HermesAgentSharePayload(text: capturedText, url: capturedURL, title: title)
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else if let attributed = item as? NSAttributedString {
                    continuation.resume(returning: attributed.string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension HermesAgentSharePayload {
    var previewText: String {
        var lines: [String] = []
        if let title { lines.append("Title: \(title)") }
        if let url { lines.append("URL: \(url.absoluteString)") }
        if let text { lines.append("Text: \(text)") }
        return lines.isEmpty ? "No shared item captured" : lines.joined(separator: "\n")
    }
}
