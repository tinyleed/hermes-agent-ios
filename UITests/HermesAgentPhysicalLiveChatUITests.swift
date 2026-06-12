import XCTest

final class HermesAgentPhysicalLiveChatUITests: XCTestCase {
    private func gatewayTokenFromDashboard(baseURL: String) throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/") else {
            throw XCTSkip("Invalid Hermes dashboard URL")
        }
        let html = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"window\.__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges >= 2,
              let tokenRange = Range(match.range(at: 1), in: html) else {
            throw XCTSkip("Hermes dashboard did not expose a session token")
        }
        return String(html[tokenRange])
    }

    private func launchAppWithLiveGateway(_ app: XCUIApplication, autosend: Bool = false, prompt: String? = nil) throws {
        let baseURL = ProcessInfo.processInfo.environment["HERMES_AGENT_UI_TEST_HERMES_GATEWAY_BASE_URL"] ?? "http://127.0.0.1:9119"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_HERMES_GATEWAY_BASE_URL"] = baseURL
        app.launchEnvironment["HERMES_AGENT_UI_TEST_HERMES_GATEWAY_WS_TOKEN"] = try gatewayTokenFromDashboard(baseURL: baseURL)
        if autosend {
            app.launchEnvironment["HERMES_AGENT_UI_TEST_AUTOSEND"] = "1"
        }
        if let prompt {
            app.launchEnvironment["HERMES_AGENT_UI_TEST_PROMPT"] = prompt
        }
    }

    func testPhysicalHermesGatewayAutosendRendersLiveResponse() throws {
        let marker = "HERMES_AGENT_IOS_PHYSICAL_OK_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_AUTOSEND"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_PROMPT"] = "reply exactly \(marker)"
        app.launch()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 120),
            "Expected live Hermes assistant response to render unique physical-device smoke marker: \(marker)"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Gateway ready")).firstMatch.exists ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hermes chat complete")).firstMatch.exists
        )
    }

    func testHermesRuntimeAutosendDoesNotShowBlockingProgressOverlay() throws {
        let marker = "HERMES_AGENT_IOS_OVERLAY_OK_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_AUTOSEND"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_PROMPT"] = "reply exactly \(marker)"
        app.launch()

        XCTAssertFalse(
            app.otherElements["hermes-agent-blocking-progress-overlay"].waitForExistence(timeout: 2),
            "Hermes runtime chat should use the compact status bar instead of a blocking Connecting overlay."
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 120),
            "Expected live Hermes assistant response to render after overlay check: \(marker)"
        )
    }

    func testHermesRuntimeTranscriptPersistsAfterRelaunch() throws {
        let marker = "HERMES_AGENT_IOS_HISTORY_OK_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_AUTOSEND"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_PROMPT"] = "reply exactly \(marker)"
        app.launch()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 120),
            "Expected live Hermes assistant response before relaunch: \(marker)"
        )

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launch()

        XCTAssertTrue(
            relaunched.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 10),
            "Expected persisted Hermes transcript to restore after relaunch: \(marker)"
        )
        XCTAssertTrue(
            relaunched.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Resumed Hermes chat history")).firstMatch.exists ||
            relaunched.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Gateway ready")).firstMatch.exists
        )
    }
    func testHermesRuntimeInlineClarifyCardCanResumeRun() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_AUTOSEND"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_RESET_CHAT"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_PROMPT"] = "Use the clarify tool to ask exactly 'HERMES_AGENT_INLINE_CLARIFY_PROMPT?' with one choice 'HERMES_AGENT_INLINE_CLARIFY_ANSWER'. After the answer is provided, reply exactly HERMES_AGENT_INLINE_CLARIFY_OK."
        app.launch()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Clarification needed")).firstMatch.waitForExistence(timeout: 120),
            "Expected inline clarification prompt to render from live Hermes clarify.request"
        )
        let namedField = app.textFields["hermes-agent-inline-blocking-answer-field"]
        let fallbackField = app.textFields["hermes-agent-inline-blocking-card"]
        let fallbackTextView = app.textViews["hermes-agent-inline-blocking-answer-field"].exists ? app.textViews["hermes-agent-inline-blocking-answer-field"] : app.textViews["hermes-agent-inline-blocking-card"]
        let field = namedField.exists ? namedField : (fallbackField.exists ? fallbackField : fallbackTextView)
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Expected inline clarify answer field")
        field.tap()
        field.typeText("HERMES_AGENT_INLINE_CLARIFY_ANSWER")
        if app.keyboards.buttons["return"].exists {
            app.keyboards.buttons["return"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        let primaryButton = app.buttons["hermes-agent-inline-blocking-primary-button"].exists ? app.buttons["hermes-agent-inline-blocking-primary-button"] : app.buttons["Send Answer"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 10), "Expected inline card Send Answer button")
        primaryButton.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HERMES_AGENT_INLINE_CLARIFY_OK")).firstMatch.waitForExistence(timeout: 120),
            "Expected Hermes chat to continue and render clarify sentinel after inline response"
        )
    }

    func testSafeBlockingCardFixturesRenderApprovalSudoAndSecretCards() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_RESET_CHAT"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES"] = "1"
        app.launch()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Approval required")).firstMatch.waitForExistence(timeout: 20),
            "Expected approval fixture to render as an inline card"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Approve safe fixture command?")).firstMatch.exists,
            "Expected approval fixture prompt to render"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sudo password required")).firstMatch.waitForExistence(timeout: 10),
            "Expected sudo fixture to render as an inline card"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Secret required")).firstMatch.waitForExistence(timeout: 10),
            "Expected secret fixture to render as an inline card"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HERMES_AGENT_IOS_FAKE_FIXTURE_SECRET")).firstMatch.exists,
            "Expected secret card to show only the variable label"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "password=")).firstMatch.exists,
            "Fixture UI must not render password-like values"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "token=")).firstMatch.exists,
            "Fixture UI must not render token-like values"
        )
    }

    func testSafeBlockingCardFixturesCanBeResolvedWithoutSecretRendering() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HERMES_AGENT_UI_TEST_RESET_CHAT"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES"] = "1"
        app.launch()

        let approvalCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Approval required")).firstMatch
        XCTAssertTrue(approvalCard.waitForExistence(timeout: 20), "Expected approval fixture before resolving")
        let approvalButton = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approvalButton.waitForExistence(timeout: 10), "Expected approval fixture action")
        approvalButton.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture approval required response sent. Value redacted.")).firstMatch.waitForExistence(timeout: 10),
            "Expected redacted approval fixture response status"
        )

        let sudoCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sudo password required")).firstMatch
        XCTAssertTrue(sudoCard.waitForExistence(timeout: 10), "Expected sudo fixture before resolving")
        app.swipeUp()
        let sudoButton = app.buttons["Submit Password"].firstMatch
        XCTAssertTrue(sudoButton.waitForExistence(timeout: 10), "Expected sudo fixture action")
        sudoButton.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture sudo password required response sent. Value redacted.")).firstMatch.waitForExistence(timeout: 10),
            "Expected redacted sudo fixture response status"
        )

        let secretCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Secret required")).firstMatch
        XCTAssertTrue(secretCard.waitForExistence(timeout: 10), "Expected secret fixture before resolving")
        let secretButton = app.buttons["Submit Secret"].firstMatch
        XCTAssertTrue(secretButton.waitForExistence(timeout: 10), "Expected secret fixture action")
        secretButton.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture secret required response sent. Value redacted.")).firstMatch.waitForExistence(timeout: 10),
            "Expected redacted secret fixture response status"
        )

        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "fixture-redacted-value")).firstMatch.exists,
            "Synthetic fixture value must not render in transcript/status"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "password=")).firstMatch.exists,
            "Fixture UI must not render password-like values"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "token=")).firstMatch.exists,
            "Fixture UI must not render token-like values"
        )
    }

    func testMockGatewayBackedBlockingCardsResumeToRedactedFinalOutput() throws {
        let app = XCUIApplication()
        try launchAppWithLiveGateway(app, autosend: true, prompt: "exercise safe blocking cards")
        app.launchEnvironment["HERMES_AGENT_UI_TEST_RESET_CHAT"] = "1"
        app.launchEnvironment["HERMES_AGENT_UI_TEST_MOCK_BLOCKING_GATEWAY_ALLOW_EMPTY_RESPONSE"] = "1"
        app.launch()

        let approvalCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Approval required")).firstMatch
        if !approvalCard.waitForExistence(timeout: 30) {
            XCTFail("Expected mock gateway approval.request to render. UI: \(app.debugDescription)")
            return
        }
        let approvalButton = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approvalButton.waitForExistence(timeout: 10), "Expected approval action")
        approvalButton.tap()

        let sudoCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sudo password required")).firstMatch
        XCTAssertTrue(sudoCard.waitForExistence(timeout: 30), "Expected mock gateway sudo.request after approval response")
        app.swipeUp()
        let sudoButton = app.buttons["Submit Password"].firstMatch
        XCTAssertTrue(sudoButton.waitForExistence(timeout: 10), "Expected sudo response action")
        sudoButton.tap()

        let secretCard = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Secret required")).firstMatch
        XCTAssertTrue(secretCard.waitForExistence(timeout: 30), "Expected mock gateway secret.request after sudo response")
        let secretButton = app.buttons["Submit Secret"].firstMatch
        XCTAssertTrue(secretButton.waitForExistence(timeout: 10), "Expected secret response action")
        secretButton.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HERMES_AGENT_MOCK_BLOCKING_GATEWAY_DONE")).firstMatch.waitForExistence(timeout: 30),
            "Expected mock gateway final output after approval/sudo/secret responses"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "mock-sudo-fixture-password")).firstMatch.exists,
            "Submitted sudo value must not render in transcript/status"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "mock-secret-fixture-token")).firstMatch.exists,
            "Submitted secret value must not render in transcript/status"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "password=")).firstMatch.exists,
            "Gateway-backed UI must not render password-like values"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "token=")).firstMatch.exists,
            "Gateway-backed UI must not render token-like values"
        )
    }

    private func enterSecureBlockingValue(_ app: XCUIApplication, value: String) {
        let secureField = app.secureTextFields["hermes-agent-inline-blocking-secret-field"].firstMatch
        let textField = app.textFields["hermes-agent-inline-blocking-secret-field"].firstMatch
        let textView = app.textViews["hermes-agent-inline-blocking-secret-field"].firstMatch
        let field: XCUIElement
        if secureField.waitForExistence(timeout: 5) {
            field = secureField
        } else if textField.waitForExistence(timeout: 5) {
            field = textField
        } else {
            XCTAssertTrue(textView.waitForExistence(timeout: 5), "Expected secure blocking response field")
            field = textView
        }
        field.tap()
        field.typeText(value)
        if app.keyboards.buttons["return"].exists {
            app.keyboards.buttons["return"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    func testRemoteSessionHistoryCanFetchAndResumeFromOperatorMenu() throws {
        let app = XCUIApplication()
        try launchAppWithLiveGateway(app)
        app.launch()

        let menuButton = app.buttons["Open operator menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 20), "Expected operator menu button")
        menuButton.tap()

        let chatHistory = app.buttons["Chat History"]
        XCTAssertTrue(chatHistory.waitForExistence(timeout: 10), "Expected Chat History menu item")
        chatHistory.tap()

        let fetchButton = app.buttons["hermes-agent-fetch-remote-sessions-button"]
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 10), "Expected Fetch Remote Sessions button")
        fetchButton.tap()

        let resumeButton = app.buttons["Resume"].firstMatch
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 30), "Expected at least one remote session Resume button after fetch")
        resumeButton.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HERMES_AGENT_REMOTE_SESSION_UI_SMOKE_OK")).firstMatch.waitForExistence(timeout: 30) ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reply exactly HERMES_AGENT_REMOTE_SESSION_UI_SMOKE_OK")).firstMatch.waitForExistence(timeout: 30) ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Remote session resumed")).firstMatch.waitForExistence(timeout: 30) ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hermes chat complete")).firstMatch.waitForExistence(timeout: 30) ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hermes Agent iOS WS smoke")).firstMatch.waitForExistence(timeout: 30),
            "Expected remote session resume to close the menu and hydrate a visible chat transcript/status"
        )
    }

}
