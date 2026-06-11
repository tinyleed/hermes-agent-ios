import SwiftUI
import UIKit
import UserNotifications

final class HermesAgentAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct HermesAgentIOSApp: App {
    @UIApplicationDelegateAdaptor(HermesAgentAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(settings: .mockGateway)
        }
    }
}
