import Foundation

/// Reads the Claude desktop app's Code sessions (title, activity, end-of-turn summary) straight from disk. Read-only.
final class ClaudeSource {
    private struct SessionRecord: Decodable {
        let sessionId: String
        let cliSessionId: String?
        let title: String?
        let lastActivityAt: Double?
        let isArchived: Bool?
        let lastAssistantUuid: String?
        let postTurnSummary: TurnSummary?
    }

    private struct TurnSummary: Decodable {
        let statusCategory: String?
        let statusDetail: String?
        let needsAction: String?
        let summarizesUuid: String?

        enum CodingKeys: String, CodingKey {
            case statusCategory = "status_category"
            case statusDetail = "status_detail"
            case needsAction = "needs_action"
            case summarizesUuid = "summarizes_uuid"
        }
    }

    private struct CachedRecord {
        let modified: Date
        let record: SessionRecord?
    }

    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let stalledAfter: TimeInterval = 15 * 60
    private var recordCache: [URL: CachedRecord] = [:]
    private var transcriptCache: [String: URL] = [:]
    /// Transcript ids owned by the desktop app (archived ones included), so the CLI source can skip them.
    private(set) var desktopTranscriptIds: Set<String> = []

    private var sessionsRoot: URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    func scan(since cutoff: Date) -> [AITask] {
        let records = sessionFiles().compactMap(loadRecord)
        desktopTranscriptIds = Set(records.compactMap(\.cliSessionId))
        return records
            .filter { $0.isArchived != true }
            .compactMap { makeTask(from: $0, cutoff: cutoff) }
    }

    /// `continue?session=` opens that exact session (`needs-input` only resolves sessions flagged as waiting).
    static func deepLink(sessionId: String) -> URL? {
        var components = URLComponents(string: "claude://code/continue")
        components?.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components?.url
    }

    // MARK: - Session files

    private func sessionFiles() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: sessionsRoot, includingPropertiesForKeys: keys) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("local_")
        }
    }

    private func loadRecord(at url: URL) -> SessionRecord? {
        let modified = LogFile.modificationDate(of: url) ?? .distantPast
        if let cached = recordCache[url], cached.modified == modified { return cached.record }
        let record = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SessionRecord.self, from: $0) }
        recordCache[url] = CachedRecord(modified: modified, record: record)
        return record
    }

    private func makeTask(from record: SessionRecord, cutoff: Date) -> AITask? {
        guard let activityMs = record.lastActivityAt else { return nil }
        let recordedActivity = Date(timeIntervalSince1970: activityMs / 1000)
        guard recordedActivity >= cutoff else { return nil }
        let transcript = record.cliSessionId.flatMap(transcriptURL)
        let turn = transcript.map { ClaudeTranscript.turnState(in: LogFile.lastLines(of: $0)) } ?? .unknown
        let lastActivity = turn.lastActivity(recorded: recordedActivity, log: transcript)
        let assessment = assess(record, turn: turn, lastActivity: lastActivity)
        return AITask(
            id: "claude:\(record.sessionId)",
            provider: .claude,
            channel: .desktopApp,
            title: TextTools.nonEmpty(record.title) ?? "Sessão sem título",
            detail: assessment.detail,
            status: assessment.status,
            lastActivity: lastActivity,
            activityMarker: String(Int(activityMs)),
            openURL: Self.deepLink(sessionId: record.sessionId)
        )
    }

    // MARK: - Status

    private func assess(_ record: SessionRecord, turn: TurnState, lastActivity: Date) -> StatusAssessment {
        switch turn {
        case .finished, .unknown:
            if let summary = summaryAssessment(record) { return summary }
        case .inProgress, .aborted:
            break
        }
        return StatusAssessment.from(turn, lastActivity: lastActivity, stalledAfter: stalledAfter)
    }

    /// Claude writes a short "what's left" summary after each turn; only trust it when it covers the latest reply.
    private func summaryAssessment(_ record: SessionRecord) -> StatusAssessment? {
        guard let summary = record.postTurnSummary,
              summary.summarizesUuid != nil,
              summary.summarizesUuid == record.lastAssistantUuid else { return nil }
        if let action = TextTools.nonEmpty(summary.needsAction) {
            return StatusAssessment(status: .needsYou, detail: TextTools.truncate(action, to: TextTools.detailLimit))
        }
        let detail = TextTools.nonEmpty(summary.statusDetail).map { TextTools.truncate($0, to: TextTools.detailLimit) }
        let status: TaskStatus = summary.statusCategory == "blocked" ? .needsYou : .readyToReview
        return StatusAssessment(status: status, detail: detail)
    }

    private func transcriptURL(for cliSessionId: String) -> URL? {
        if let cached = transcriptCache[cliSessionId] { return cached }
        let root = ClaudeTranscript.projectsRoot
        let projects = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let found = projects
            .map { $0.appendingPathComponent("\(cliSessionId).jsonl") }
            .first { fileManager.fileExists(atPath: $0.path) }
        transcriptCache[cliSessionId] = found
        return found
    }
}
