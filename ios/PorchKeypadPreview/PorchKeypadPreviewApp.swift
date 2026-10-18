import UIKit

// This target has no FamilyService, CallKit, LiveKit, call controller, URL
// handler, push registration, camera, or microphone implementation linked in.
@main
final class PorchKeypadPreviewApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Porch keypad preview", sessionRole: session.role)
        configuration.delegateClass = PorchKeypadPreviewScene.self
        return configuration
    }
}
final class PorchKeypadPreviewScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = PorchStyle.navigation(KeypadPreviewViewController())
        window.makeKeyAndVisible(); self.window = window
    }
}
