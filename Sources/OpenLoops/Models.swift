import Foundation

enum AIProvider: String {
    case claude, chatgpt, gemini, perplexity, grok, other

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .perplexity: return "Perplexity"
        case .grok: return "Grok"
        case .other: return "IA"
        }
    }
}

enum TaskChannel: Equatable {
    case desktopApp
    case chromeTab(windowId: Int, tabId: Int)
    /// Claude Code running outside the desktop app (a terminal or an editor such as VS Code).
    case codeTool(label: String, appCandidates: [String])

    var isBrowserTab: Bool {
        if case .chromeTab = self { return true }
        return false
    }

    var placeLabel: String? {
        switch self {
        case .desktopApp: return nil
        case .chromeTab: return "Chrome"
        case .codeTool(let label, _): return label
        }
    }
}

enum TaskStatus: Int, Comparable, CaseIterable {
    case needsYou, readyToReview, working, openTab

    static func < (lhs: TaskStatus, rhs: TaskStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The AI is done and the ball is in the user's court.
    var isWaitingOnUser: Bool { self == .needsYou || self == .readyToReview }
}

struct AITask: Identifiable, Equatable {
    let id: String
    let provider: AIProvider
    let channel: TaskChannel
    let title: String
    let detail: String?
    let status: TaskStatus
    let lastActivity: Date
    /// Changes whenever the conversation has new activity; a "done" check only hides the task while it stays the same.
    let activityMarker: String
    let openURL: URL?
}

/// Where a conversation's latest turn stands, read from its transcript.
enum TurnState {
    case inProgress
    case finished(lastMessage: String?)
    case aborted
    case unknown

    /// Session metadata is only written between turns; while a turn runs, its log file's modification date is the heartbeat.
    /// (Finished sessions ignore it: the apps touch those logs without real conversation activity.)
    func lastActivity(recorded: Date, log: URL?) -> Date {
        guard case .inProgress = self, let log, let modified = LogFile.modificationDate(of: log) else { return recorded }
        return max(recorded, modified)
    }
}

struct StatusAssessment {
    let status: TaskStatus
    let detail: String?

    static let aborted = StatusAssessment(status: .needsYou, detail: "Interrompida — dar continuidade")

    /// A turn still running; if nothing moved for too long it most likely stalled or waits for an approval.
    static func inProgress(lastActivity: Date, stalledAfter: TimeInterval) -> StatusAssessment {
        guard Date().timeIntervalSince(lastActivity) > stalledAfter else {
            return StatusAssessment(status: .working, detail: nil)
        }
        return StatusAssessment(status: .needsYou, detail: "Parou no meio — dar continuidade")
    }

    static func from(_ turn: TurnState, lastActivity: Date, stalledAfter: TimeInterval) -> StatusAssessment {
        switch turn {
        case .inProgress: return inProgress(lastActivity: lastActivity, stalledAfter: stalledAfter)
        case .aborted: return aborted
        case .finished(let lastMessage): return fromFinalMessage(lastMessage)
        case .unknown: return StatusAssessment(status: .readyToReview, detail: nil)
        }
    }

    /// Infers whether the AI is waiting on the user from its final message.
    static func fromFinalMessage(_ message: String?) -> StatusAssessment {
        guard let lastParagraph = TextTools.lastMeaningfulLine(of: message) else {
            return StatusAssessment(status: .readyToReview, detail: nil)
        }
        let asksSomething = lastParagraph.contains("?")
        return StatusAssessment(status: asksSomething ? .needsYou : .readyToReview, detail: lastParagraph)
    }
}

enum TaskSummary {
    private static let phrases: [TaskStatus: (singular: String, plural: String)] = [
        .needsYou: ("precisa de você", "precisam de você"),
        .readyToReview: ("pra revisar", "pra revisar"),
        .working: ("trabalhando", "trabalhando"),
        .openTab: ("aba aberta", "abas abertas"),
    ]

    /// "2 precisam de você · 1 pra revisar · 1 trabalhando"
    static func describe(_ tasks: [AITask]) -> String {
        let parts = TaskStatus.allCases.compactMap { status -> String? in
            let count = tasks.filter { $0.status == status }.count
            guard count > 0, let phrase = phrases[status] else { return nil }
            return "\(count) \(count == 1 ? phrase.singular : phrase.plural)"
        }
        return parts.isEmpty ? "Nada pendente" : parts.joined(separator: " · ")
    }
}
