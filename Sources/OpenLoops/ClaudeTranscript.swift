import Foundation

/// Reads Claude Code transcripts (`~/.claude/projects/<folder>/<session>.jsonl`), shared by the desktop app and CLI sources.
enum ClaudeTranscript {
    static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Whether the latest turn is still running, finished (with the final reply) or was interrupted.
    static func turnState(in lines: [String]) -> TurnState {
        for line in lines.reversed() {
            guard let entry = JSONLine.object(line), let type = entry["type"] as? String else { continue }
            if type == "user", entry["isMeta"] as? Bool != true {
                return isInterruption(entry) ? .aborted : .inProgress
            }
            guard type == "assistant", let message = entry["message"] as? [String: Any] else { continue }
            let stopReason = message["stop_reason"] as? String
            let endedTurn = stopReason == "end_turn" || stopReason == "stop_sequence"
            return endedTurn ? .finished(lastMessage: text(of: message)) : .inProgress
        }
        return .unknown
    }

    static func text(of message: [String: Any]) -> String? {
        guard let blocks = message["content"] as? [[String: Any]] else { return message["content"] as? String }
        let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static func isInterruption(_ entry: [String: Any]) -> Bool {
        guard let message = entry["message"] as? [String: Any] else { return false }
        return (text(of: message) ?? "").hasPrefix("[Request interrupted")
    }
}
