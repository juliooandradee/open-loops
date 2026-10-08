import AppKit

/// Lists AI conversations open as Google Chrome tabs (via AppleScript) and can bring one to the front.
final class ChromeSource {
    private struct ConversationRule {
        let hostSuffix: String
        let pathFragment: String
        let provider: AIProvider
    }

    static let bundleIdentifier = "com.google.Chrome"

    private(set) var permissionDenied = false
    private var firstSeen: [String: Date] = [:]

    private static let rules: [ConversationRule] = [
        ConversationRule(hostSuffix: "chatgpt.com", pathFragment: "/c/", provider: .chatgpt),
        ConversationRule(hostSuffix: "chat.openai.com", pathFragment: "/c/", provider: .chatgpt),
        ConversationRule(hostSuffix: "claude.ai", pathFragment: "/chat/", provider: .claude),
        ConversationRule(hostSuffix: "gemini.google.com", pathFragment: "/app/", provider: .gemini),
        ConversationRule(hostSuffix: "gemini.google.com", pathFragment: "/gem/", provider: .gemini),
        ConversationRule(hostSuffix: "aistudio.google.com", pathFragment: "/prompts/", provider: .gemini),
        ConversationRule(hostSuffix: "notebooklm.google.com", pathFragment: "/notebook/", provider: .gemini),
        ConversationRule(hostSuffix: "perplexity.ai", pathFragment: "/search/", provider: .perplexity),
        ConversationRule(hostSuffix: "grok.com", pathFragment: "/c/", provider: .grok),
        ConversationRule(hostSuffix: "grok.com", pathFragment: "/chat/", provider: .grok),
        ConversationRule(hostSuffix: "chat.deepseek.com", pathFragment: "/chat/", provider: .other),
    ]

    private static let titleDecorations = [
        " - Claude", " | Claude", " - ChatGPT", " | ChatGPT", "ChatGPT - ", " - Gemini", "Gemini - ",
        " - Google AI Studio", " - NotebookLM", " - Perplexity", " | Perplexity", " - Grok", " | Grok", " - DeepSeek",
    ]

    private static let listTabsScript = """
        set separator to character id 9
        set output to ""
        tell application "Google Chrome"
            repeat with chromeWindow in windows
                set windowId to id of chromeWindow
                repeat with chromeTab in tabs of chromeWindow
                    set output to output & windowId & separator & (id of chromeTab) & separator & (URL of chromeTab) & separator & (title of chromeTab) & linefeed
                end repeat
            end repeat
        end tell
        return output
        """

    func scan() -> [AITask] {
        guard Self.isChromeRunning() else { return [] }
        let result = AppleScriptRunner.run(Self.listTabsScript)
        permissionDenied = result.permissionDenied
        guard let output = result.output else { return [] }
        let tasks = output.components(separatedBy: "\n").compactMap(makeTask)
        var seenIds = Set<String>()
        return tasks.filter { seenIds.insert($0.id).inserted }
    }

    func focus(windowId: Int, tabId: Int) {
        let script = """
            tell application "Google Chrome"
                repeat with chromeWindow in windows
                    if id of chromeWindow is \(windowId) then
                        set tabIndex to 0
                        repeat with chromeTab in tabs of chromeWindow
                            set tabIndex to tabIndex + 1
                            if id of chromeTab is \(tabId) then
                                set active tab index of chromeWindow to tabIndex
                                set index of chromeWindow to 1
                                activate
                                return
                            end if
                        end repeat
                    end if
                end repeat
            end tell
            """
        _ = AppleScriptRunner.run(script)
    }

    static func isChromeRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    // MARK: - Parsing

    private func makeTask(fromLine line: String) -> AITask? {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 4, let windowId = Int(fields[0]), let tabId = Int(fields[1]),
              let url = URL(string: fields[2]), let provider = Self.conversationProvider(for: url) else { return nil }
        let rawTitle = fields[3...].joined(separator: " ")
        let id = "tab:\(Self.stableAddress(of: url))"
        let seen = firstSeen[id] ?? Date()
        firstSeen[id] = seen
        return AITask(
            id: id,
            provider: provider,
            channel: .chromeTab(windowId: windowId, tabId: tabId),
            title: Self.cleanTitle(rawTitle, provider: provider),
            detail: nil,
            status: .openTab,
            lastActivity: seen,
            activityMarker: rawTitle,
            openURL: url
        )
    }

    static func conversationProvider(for url: URL) -> AIProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path + "/"
        let rule = rules.first { rule in
            host.hasSuffix(rule.hostSuffix) && path.contains(rule.pathFragment) && !path.hasSuffix(rule.pathFragment)
                && !path.contains("new_chat")
        }
        return rule?.provider
    }

    private static func stableAddress(of url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    private static func cleanTitle(_ raw: String, provider: AIProvider) -> String {
        var title = raw
        for decoration in titleDecorations {
            title = title.replacingOccurrences(of: decoration, with: "")
        }
        title = title.trimmingCharacters(in: .whitespaces)
        let isGeneric = title.isEmpty || title.caseInsensitiveCompare(provider.displayName) == .orderedSame
        return isGeneric ? "Conversa no \(provider.displayName)" : title
    }
}

enum AppleScriptRunner {
    struct Result {
        let output: String?
        let permissionDenied: Bool
    }

    /// Runs through osascript so it never blocks the main thread; gives up after a few seconds.
    static func run(_ script: String, timeout: TimeInterval = 6) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        guard (try? process.run()) != nil else { return Result(output: nil, permissionDenied: false) }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let errorText = String(decoding: errorData, as: UTF8.self)
        let succeeded = process.terminationStatus == 0
        return Result(
            output: succeeded ? String(decoding: outputData, as: UTF8.self) : nil,
            permissionDenied: errorText.contains("-1743")
        )
    }
}
