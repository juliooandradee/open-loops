import Foundation

/// Conversations the user checked off or snoozed, persisted in Application Support.
final class HiddenTaskStore {
    private struct Entry: Codable {
        let activityMarker: String
        let doneAt: Date
        /// nil = done for good; a date = snoozed until then.
        let hiddenUntil: Date?
    }

    private let retention: TimeInterval = 30 * 86_400
    private let fileURL: URL
    private var entries: [String: Entry] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("OpenLoops", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("hidden-tasks.json")
        load()
    }

    /// Hidden only while the conversation has no new activity; anything new brings it back.
    func isHidden(_ task: AITask, now: Date = Date()) -> Bool {
        guard let entry = entries[task.id], entry.activityMarker == task.activityMarker else { return false }
        guard let until = entry.hiddenUntil else { return true }
        return now < until
    }

    func hide(_ task: AITask, until: Date? = nil) {
        entries[task.id] = Entry(activityMarker: task.activityMarker, doneAt: Date(), hiddenUntil: until)
        save()
    }

    func unhide(_ task: AITask) {
        entries.removeValue(forKey: task.id)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        let oldest = Date().addingTimeInterval(-retention)
        entries = decoded.filter { $0.value.doneAt >= oldest }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
