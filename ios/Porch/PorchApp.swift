import UIKit
import PorchCore

@main
final class PorchApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SystemIncomingCalls.shared.start()
        FamilyMessageAlerts.shared.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FamilyMessageAlerts.shared.received(deviceToken: deviceToken)
    }
    // Without notifications, messages still show when Porch is opened.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Porch", sessionRole: session.role)
        configuration.delegateClass = PorchScene.self
        return configuration
    }
}

/// A touch or a key press anywhere in Porch means someone is at the iPad (see `BedsideAttendance`).
final class PorchWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches || event.type == .presses { AttendanceTracker.shared.noticed() }
        super.sendEvent(event)
    }
}

final class PorchScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        #if DEBUG
        PorchDevice.installPreviewFixture()
        #endif
        let window = PorchWindow(windowScene: scene)
        window.rootViewController = PorchContainerViewController()
        window.makeKeyAndVisible()
        self.window = window
        Cell2JackKeypad.shared.root = window.rootViewController
        Cell2JackKeypad.shared.windowScene = scene
        if let url = options.urlContexts.first?.url ?? options.userActivities.lazy.compactMap(Self.webLink).first {
            (window.rootViewController as? PorchContainerViewController)?.openInvitation(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if let url = contexts.first?.url { (window?.rootViewController as? PorchContainerViewController)?.openInvitation(url) }
    }

    /// An invitation link from helloporch.store, tapped in Messages or scanned with the camera (see `PorchWebLinks`).
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = Self.webLink(userActivity) { (window?.rootViewController as? PorchContainerViewController)?.openInvitation(url) }
    }
    private static func webLink(_ activity: NSUserActivity) -> URL? {
        activity.activityType == NSUserActivityTypeBrowsingWeb ? activity.webpageURL : nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? PorchContainerViewController)?.resume()
        UIApplication.shared.isIdleTimerDisabled = PorchDevice.experience == .bedside
        SystemIncomingCalls.shared.resumeCamera()
        Cell2JackKeypad.shared.activate()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SystemIncomingCalls.shared.enterBackground()
        RemoteCaregiverSession.shared.end()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Cell2JackKeypad.shared.pause()
        (window?.rootViewController as? PorchContainerViewController)?.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
