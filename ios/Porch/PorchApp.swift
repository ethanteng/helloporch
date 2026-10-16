import UIKit

@main
final class PorchApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Porch", sessionRole: session.role)
        configuration.delegateClass = PorchScene.self
        return configuration
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
        let window = UIWindow(windowScene: scene)
        window.rootViewController = PorchContainerViewController()
        window.makeKeyAndVisible()
        self.window = window
        if let url = options.urlContexts.first?.url { (window.rootViewController as? PorchContainerViewController)?.openInvitation(url) }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if let url = contexts.first?.url { (window?.rootViewController as? PorchContainerViewController)?.openInvitation(url) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? PorchContainerViewController)?.resume()
        UIApplication.shared.isIdleTimerDisabled = PorchDevice.experience == .bedside
    }

    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? PorchContainerViewController)?.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
