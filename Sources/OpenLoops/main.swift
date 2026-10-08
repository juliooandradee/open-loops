import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore?
    private var panelController: SidePanelController?
    private let notifier = Notifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isAnotherInstanceRunning() else {
            NSApp.terminate(nil)
            return
        }
        let store = TaskStore(settings: AppSettings(), notifier: notifier)
        let controller = SidePanelController(store: store)
        notifier.onOpenTask = { [weak store, weak controller] taskId in
            guard let task = store?.task(withId: taskId) else {
                controller?.presentPinned()
                return
            }
            store?.open(task)
        }
        notifier.onOpenPanel = { [weak controller] in controller?.presentPinned() }
        controller.show()
        store.start()
        LoginItem.enableOnFirstLaunch()
        self.store = store
        panelController = controller
    }

    private static func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count > 1
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
