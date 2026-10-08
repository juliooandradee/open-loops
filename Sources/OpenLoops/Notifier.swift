import Foundation
import UserNotifications

/// macOS notifications: "the AI finished" and the morning summary. Clicking one opens the conversation or the panel.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpenTask: ((String) -> Void)?
    var onOpenPanel: (() -> Void)?

    private static let taskIdKey = "taskId"
    private var didAskPermission = false

    /// UNUserNotificationCenter only exists for a real app bundle (not for `swift run`).
    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func notifyFinished(_ task: AITask) {
        let place = task.channel.placeLabel.map { " · \($0)" } ?? ""
        post(
            identifier: "finished-\(task.id)",
            title: "\(task.status.label) — \(task.provider.displayName)\(place)",
            body: [task.title, task.detail].compactMap { $0 }.joined(separator: "\n"),
            userInfo: [Self.taskIdKey: task.id]
        )
    }

    func notifyMorningSummary(_ tasks: [AITask]) {
        let count = tasks.count
        post(
            identifier: "morning-summary",
            title: "Bom dia! \(count) \(count == 1 ? "conversa em aberto" : "conversas em aberto")",
            body: TaskSummary.describe(tasks),
            userInfo: [:]
        )
    }

    private func post(identifier: String, title: String, body: String, userInfo: [String: String]) {
        guard let center else { return }
        requestPermissionOnce()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func requestPermissionOnce() {
        guard !didAskPermission else { return }
        didAskPermission = true
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskId = response.notification.request.content.userInfo[Self.taskIdKey] as? String
        DispatchQueue.main.async { [weak self] in
            if let taskId { self?.onOpenTask?(taskId) } else { self?.onOpenPanel?() }
        }
        completionHandler()
    }
}
