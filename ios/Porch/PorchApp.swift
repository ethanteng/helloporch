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
        // The phone adapter's hang-up key goes to the visible screen however the
        // responder chain is set up, the way the Cell2Jack driver's hang-up does.
        if let presses = event as? UIPressesEvent, presses.allPresses.contains(where: {
            $0.phase == .began && $0.key.map { Int($0.keyCode.rawValue) } == CallTrigger.receiverHangUpKey
        }) {
            Cell2JackKeypad.shared.receiveAdapterHangUp()
        }
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
        ScreenAwake.update(inFront: true)
        SystemIncomingCalls.shared.resumeCamera()
        Cell2JackKeypad.shared.activate()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SystemIncomingCalls.shared.enterBackground()
        RemoteCaregiverSession.shared.end()
        ScreenAwake.update(inFront: false)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Cell2JackKeypad.shared.pause()
        (window?.rootViewController as? PorchContainerViewController)?.pause()
    }
}

/// Keeps the screen on for the bedside clock, and on any device while a call screen is open, the way FaceTime does.
/// Otherwise a family phone dims and locks mid-call, and leaving the foreground hangs up a call it placed.
/// Voice calls also turn on the proximity sensor, so an iPhone's screen goes dark against an ear instead of
/// taking taps from a cheek. iPads have no sensor.
@MainActor enum ScreenAwake {
    private static let calls = NSHashTable<UIViewController>.weakObjects()
    private static let voiceCalls = NSHashTable<UIViewController>.weakObjects()
    static func callShown(_ screen: UIViewController, voice: Bool) {
        calls.add(screen)
        if voice { voiceCalls.add(screen) } else { voiceCalls.remove(screen) }
        update()
    }
    /// A screen over the call, such as the phone keypad, leaves the call going. Anything else closed it.
    static func callDisappeared(_ screen: UIViewController) {
        guard screen.presentedViewController == nil || screen.isBeingDismissed else { return }
        calls.remove(screen); voiceCalls.remove(screen)
        update()
    }
    /// Only the background gives the screen back to iOS. Covering the proximity sensor can resign active too, and
    /// turning the sensor or the idle timer off then would light the screen against an ear or let the phone lock.
    static func update(inFront: Bool = UIApplication.shared.applicationState != .background) {
        // Welcome isn't the bedside clock, even on an iPad whose mode hasn't been chosen yet.
        let clock = !PorchDevice.needsWelcome && PorchDevice.experience == .bedside
        UIApplication.shared.isIdleTimerDisabled = inFront && (clock || !calls.allObjects.isEmpty)
        UIDevice.current.isProximityMonitoringEnabled = inFront && !voiceCalls.allObjects.isEmpty
    }
}
