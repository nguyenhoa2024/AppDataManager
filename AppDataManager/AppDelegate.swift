import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions
                     launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? FileManager.default.createDirectory(
            at: PathConfig.backupRoot, withIntermediateDirectories: true)

        let nav = UINavigationController(rootViewController: MainViewController())
        styleNavBar(nav.navigationBar)

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = C.bg
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        return true
    }
}

/// Nav bar toi mau, dung chung cho ca nav chinh lan man hinh cai dat.
func styleNavBar(_ bar: UINavigationBar) {
    bar.barStyle = .black
    bar.tintColor = C.mint
    bar.titleTextAttributes = [.foregroundColor: UIColor.white]

    if #available(iOS 15.0, *) {
        // Tu iOS 15 nav bar trong suot khi khong scroll — phai set ca hai
        // appearance thi mau nen moi giu nguyen.
        let a = UINavigationBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = C.bg
        a.titleTextAttributes = [.foregroundColor: UIColor.white]
        bar.standardAppearance = a
        bar.scrollEdgeAppearance = a
    } else {
        bar.barTintColor = C.bg
        bar.isTranslucent = false
    }
}
