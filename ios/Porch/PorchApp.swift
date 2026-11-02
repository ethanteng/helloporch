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
        ScreenAwake.update(active: true)
        SystemIncomingCalls.shared.resumeCamera()
        Cell2JackKeypad.shared.activate()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SystemIncomingCalls.shared.enterBackground()
        RemoteCaregiverSession.shared.end()
        // Resigning active is also how the proximity sensor blanks the screen. Only a real
        // background should give the idle timer and the sensor back to iOS.
        ScreenAwake.enteredBackground()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Cell2JackKeypad.shared.pause()
        (window?.rootViewController as? PorchContainerViewController)?.pause()
        ScreenAwake.update(active: false)
    }
}

/// Keeps the screen on for the bedside clock, and on any device while a call screen is open, the way FaceTime does.
/// Otherwise a family phone dims and locks mid-call, and leaving the foreground hangs up a call it placed.
/// Voice calls also turn on the proximity sensor, so an iPhone's screen goes dark against an ear instead of
/// taking taps from a cheek. iPads have no sensor.
@MainActor enum ScreenAwake {
    struct Decision: Equatable {
        var idleTimerDisabled: Bool
        var proximityMonitoring: Bool
    }

    private static let calls = NSHashTable<UIViewController>.weakObjects()
    private static let voiceCalls = NSHashTable<UIViewController>.weakObjects()
    private static var watchingProximity = false

    static func callShown(_ screen: UIViewController, voice: Bool) {
        calls.add(screen)
        if voice { voiceCalls.add(screen) } else { voiceCalls.remove(screen) }
        update()
    }
    /// The call screen itself went away. A sheet on top of it (add a phone, the keypad) makes this
    /// screen disappear on an iPhone too, and that call is still going, so that does not release it.
    static func callEnded(_ screen: UIViewController) {
        guard screen.isBeingDismissed || screen.isMovingFromParent else { return }
        callHidden(screen)
    }
    static func callHidden(_ screen: UIViewController) {
        calls.remove(screen); voiceCalls.remove(screen)
        update()
    }
    /// Home screen or the app switcher. Covering the proximity sensor resigns active without this.
    static func enteredBackground() { update(active: false, background: true) }

    static func update(active: Bool = UIApplication.shared.applicationState == .active,
                       background: Bool = UIApplication.shared.applicationState == .background) {
        // Welcome isn't the bedside clock, even on an iPad whose mode hasn't been chosen yet.
        let clock = !PorchDevice.needsWelcome && PorchDevice.experience == .bedside
        let inCall = !calls.allObjects.isEmpty
        let voice = !voiceCalls.allObjects.isEmpty
        let decision = policy(active: active, background: background, bedsideClock: clock, inCall: inCall, voice: voice,
                              nearEar: UIDevice.current.proximityState)
        UIApplication.shared.isIdleTimerDisabled = decision.idleTimerDisabled
        UIDevice.current.isProximityMonitoringEnabled = decision.proximityMonitoring
        watchProximity(voice && !background)
    }

    /// Covering the sensor resigns active and blacks the screen. That is still this call: turning the
    /// sensor off there lights the screen against an ear, and the idle timer can then lock the phone
    /// and hang up. A real background still sleeps.
    static func policy(active: Bool, background: Bool, bedsideClock: Bool, inCall: Bool, voice: Bool, nearEar: Bool) -> Decision {
        let blankedByEar = inCall && nearEar && !background
        let foreground = (active && !background) || blankedByEar
        return Decision(
            idleTimerDisabled: foreground && (bedsideClock || inCall),
            proximityMonitoring: voice && !background)
    }

    /// `willResignActive` can run before `proximityState` flips. When the sensor then reports near,
    /// put the idle timer back. A "not near" notice is the screen coming on, which also becomes active.
    private static func watchProximity(_ on: Bool) {
        guard on != watchingProximity else { return }
        watchingProximity = on
        if on {
            NotificationCenter.default.addObserver(
                ScreenAwakeProximity.shared, selector: #selector(ScreenAwakeProximity.near),
                name: UIDevice.proximityStateDidChangeNotification, object: nil)
        } else {
            ScreenAwakeProximity.shared.generation += 1
            NotificationCenter.default.removeObserver(ScreenAwakeProximity.shared)
        }
    }
}

/// Posted on the main thread by UIKit. A notice already queued must not turn the sensor back on
/// after the call ends or Porch backgrounds.
private final class ScreenAwakeProximity: NSObject {
    static let shared = ScreenAwakeProximity()
    var generation = 0
    @objc func near() {
        let generation = generation
        guard UIDevice.current.proximityState else { return }
        Task { @MainActor in
            guard generation == ScreenAwakeProximity.shared.generation else { return }
            ScreenAwake.update()
        }
    }
}
