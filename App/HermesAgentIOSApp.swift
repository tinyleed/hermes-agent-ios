import SwiftUI
import UIKit
import UserNotifications
import HermesAgentCore

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String else { return }
        UserDefaults.standard.set(route, forKey: "pendingAppIntentRoute")
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let defaults = UserDefaults.standard
        defaults.set(APNsDeviceTokenRegistrationStatus.captured.rawValue, forKey: "apnsRegistrationStatus")
        defaults.set(deviceToken.count, forKey: "apnsDeviceTokenByteCount")
        defaults.set(Date().timeIntervalSince1970, forKey: "apnsRegistrationUpdatedAt")
        defaults.set("", forKey: "apnsRegistrationFailureRedacted")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let failed = APNsDeviceTokenState.failed(reason: error.localizedDescription, at: Date().timeIntervalSince1970)
        let defaults = UserDefaults.standard
        defaults.set(APNsDeviceTokenRegistrationStatus.failed.rawValue, forKey: "apnsRegistrationStatus")
        defaults.set(0, forKey: "apnsDeviceTokenByteCount")
        defaults.set(failed.lastUpdatedAt ?? Date().timeIntervalSince1970, forKey: "apnsRegistrationUpdatedAt")
        defaults.set(failed.failureReasonRedacted ?? "<redacted>", forKey: "apnsRegistrationFailureRedacted")
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
