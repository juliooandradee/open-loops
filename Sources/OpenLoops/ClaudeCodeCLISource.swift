import Foundation

/// Claude Code sessions started outside the desktop app: in a terminal (`claude`) or an editor extension. Read-only.
final class ClaudeCodeCLISource {
    private struct SessionInfo {
        var title: String?
        var entrypoint: String?
        var cwd: String?
        var firstPrompt: String?
    }

    private struct Place {
        let label: String
        let appCandidates: [String]
    }

    private static let terminalApps = [
        "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "com.apple.Terminal",
    ]
    private static let editorApps = [
        "com.google.antigravity", "com.google.antigravity-ide", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    ]

    private let fileManager = FileManager.default
    private let stalledAfter: TimeInterval = 15 * 60
    /// The beginning of a transcript never changes, so it is read once per file; the end only when the file changes.
    private var headCache: [URL: SessionInfo] = [:]
    private var tailCache: [URL: (modified: Date, info: SessionInfo, turn: TurnState)] = [:]

    func scan(since cutoff: Date, excluding desktopIds: Set<String>) -> [AITask] {
        recentTranscripts(since: cutoff)
            .filter { !desktopIds.contains($0.url.deletingPathExtension().lastPathComponent) }
            .compactMap { makeTask(transcript: $0.url, modified: $0.modified) }
    }

    private func recentTranscripts(since cutoff: Date) -> [(url: URL, modified: Date)] {
        let root = ClaudeTranscript.projectsRoot
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.flatMap { folder -> [(url: URL, modified: Date)] in
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { file in
                guard file.pathExtension == "jsonl", let modified = LogFile.modificationDate(of: file),
                      modified >= cutoff else { return nil }
                return (file, modified)
            }
        }
    }

    private func makeTask(transcript: URL, modified: Date) -> AITask? {
        let (recent, turn) = tailInfo(of: transcript, modified: modified)
        let head = headInfo(of: transcript)
        guard let place = Self.place(for: recent.entrypoint ?? head.entrypoint) else { return nil }
        let assessment = StatusAssessment.from(turn, lastActivity: modified, stalledAfter: stalledAfter)
        let folder = (recent.cwd ?? head.cwd).map { URL(fileURLWithPath: $0).lastPathComponent }
        return AITask(
            id: "claude-code:\(transcript.deletingPathExtension().lastPathComponent)",
            provider: .claude,
            channel: .codeTool(label: place.label, appCandidates: place.appCandidates),
            title: recent.title ?? head.title ?? head.firstPrompt ?? folder ?? "Sessão do Claude Code",
            detail: assessment.detail,
            status: assessment.status,
            lastActivity: modified,
            activityMarker: String(Int(modified.timeIntervalSince1970)),
            openURL: nil
        )
    }

    private func tailInfo(of transcript: URL, modified: Date) -> (SessionInfo, TurnState) {
        if let cached = tailCache[transcript], cached.modified == modified { return (cached.info, cached.turn) }
        let lines = LogFile.lastLines(of: transcript)
        let info = Self.info(from: lines)
        let turn = ClaudeTranscript.turnState(in: lines)
        tailCache[transcript] = (modified, info, turn)
        return (info, turn)
    }

    private func headInfo(of transcript: URL) -> SessionInfo {
        if let cached = headCache[transcript] { return cached }
        let info = Self.info(from: LogFile.firstLines(of: transcript))
        headCache[transcript] = info
        return info
    }

    /// Pulls the latest title (`/rename` or the auto title), where it runs, and the first prompt as a fallback title.
    private static func info(from lines: [String]) -> SessionInfo {
        var info = SessionInfo()
        for line in lines {
            guard line.contains("-title\"") || line.contains("\"entrypoint\""), let entry = JSONLine.object(line) else {
                continue
            }
            let title = (entry["customTitle"] as? String) ?? (entry["aiTitle"] as? String)
            info.title = TextTools.nonEmpty(title) ?? info.title
            info.entrypoint = (entry["entrypoint"] as? String) ?? info.entrypoint
            info.cwd = (entry["cwd"] as? String) ?? info.cwd
            if info.firstPrompt == nil { info.firstPrompt = firstPrompt(in: entry) }
        }
        return info
    }

    private static func firstPrompt(in entry: [String: Any]) -> String? {
        guard entry["type"] as? String == "user", entry["isMeta"] as? Bool != true,
              let message = entry["message"] as? [String: Any],
              let text = TextTools.nonEmpty(ClaudeTranscript.text(of: message)), !text.hasPrefix("<") else { return nil }
        return TextTools.firstLine(of: text, limit: 70)
    }

    /// Automations (`sdk-*`) and desktop-app runs are not conversations to come back to.
    private static func place(for entrypoint: String?) -> Place? {
        let value = entrypoint ?? "cli"
        if value.hasPrefix("sdk") || value.contains("desktop") { return nil }
        let isEditor = ["vscode", "cursor", "jetbrains", "windsurf"].contains { value.contains($0) }
        return isEditor
            ? Place(label: "Editor", appCandidates: editorApps)
            : Place(label: "Terminal", appCandidates: terminalApps)
    }
}
