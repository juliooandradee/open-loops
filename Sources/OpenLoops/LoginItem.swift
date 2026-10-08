import ServiceManagement

/// "Open at login" through the system Login Items list.
enum LoginItem {
    private static let firstLaunchKey = "didEnableLoginItemOnFirstLaunch"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    static func enableOnFirstLaunch() {
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        guard isAppBundle, !UserDefaults.standard.bool(forKey: firstLaunchKey) else { return }
        UserDefaults.standard.set(true, forKey: firstLaunchKey)
        setEnabled(true)
    }
}
