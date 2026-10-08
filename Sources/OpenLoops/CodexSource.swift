import Foundation
import SQLite3

/// Reads ChatGPT desktop (Codex) threads from its local SQLite state and rollout logs. Read-only.
final class CodexSource {
    private struct ThreadRow {
        let id: String
        let title: String
        let updatedAtMs: Int64
        let rolloutPath: String
    }

    private let fileManager = FileManager.default
    private let codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    private let stalledAfter: TimeInterval = 30 * 60

    private static let threadsQuery = """
        SELECT id, COALESCE(NULLIF(name, ''), title), COALESCE(updated_at_ms, updated_at * 1000), rollout_path
        FROM threads
        WHERE archived = 0
          AND COALESCE(thread_source, 'user') IN ('user', 'voice_chat')
          AND COALESCE(updated_at_ms, updated_at * 1000) >= ?
        ORDER BY 3 DESC
        LIMIT 40
        """

    func scan(since cutoff: Date) -> [AITask] {
        guard let database = latestStateDatabase() else { return [] }
        return fetchThreads(from: database, since: cutoff).map(makeTask)
    }

    static func deepLink(threadId: String) -> URL? {
        URL(string: "codex://threads/\(threadId)")
    }

    // MARK: - Database

    /// The app bumps the schema file name (state_5.sqlite, state_6.sqlite…), so pick the highest version.
    private func latestStateDatabase() -> URL? {
        let files = (try? fileManager.contentsOfDirectory(at: codexHome, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .max { schemaVersion(of: $0) < schemaVersion(of: $1) }
    }

    private func schemaVersion(of url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "state_", with: "")) ?? 0
    }

    private func fetchThreads(from url: URL, since cutoff: Date) -> [ThreadRow] {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(database, 1500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, Self.threadsQuery, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970 * 1000))
        var rows: [ThreadRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(ThreadRow(
                id: Self.text(statement, 0),
                title: Self.text(statement, 1),
                updatedAtMs: sqlite3_column_int64(statement, 2),
                rolloutPath: Self.text(statement, 3)
            ))
        }
        return rows
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    // MARK: - Tasks

    private func makeTask(from row: ThreadRow) -> AITask {
        let recordedActivity = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000)
        let rollout = row.rolloutPath.isEmpty ? nil : URL(fileURLWithPath: row.rolloutPath)
        let turn = rollout.map(turnState) ?? .unknown
        let lastActivity = turn.lastActivity(recorded: recordedActivity, log: rollout)
        let assessment = StatusAssessment.from(turn, lastActivity: lastActivity, stalledAfter: stalledAfter)
        return AITask(
            id: "chatgpt:\(row.id)",
            provider: .chatgpt,
            channel: .desktopApp,
            title: TextTools.nonEmpty(row.title).map { TextTools.firstLine(of: $0) } ?? "Conversa sem título",
            detail: assessment.detail,
            status: assessment.status,
            lastActivity: lastActivity,
            activityMarker: String(row.updatedAtMs),
            openURL: Self.deepLink(threadId: row.id)
        )
    }

    private func turnState(rollout: URL) -> TurnState {
        let lines = LogFile.lastLines(of: rollout)
        for line in lines.reversed() where line.contains("\"task_") || line.contains("\"turn_aborted\"") {
            guard let entry = JSONLine.object(line), entry["type"] as? String == "event_msg",
                  let payload = entry["payload"] as? [String: Any] else { continue }
            switch payload["type"] as? String {
            case "task_complete": return .finished(lastMessage: payload["last_agent_message"] as? String)
            case "turn_aborted": return .aborted
            case "task_started": return .inProgress
            default: continue
            }
        }
        return .unknown
    }
}
