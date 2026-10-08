import Foundation

enum TextTools {
    static let detailLimit = 160

    private static let nonProsePrefixes = ["|", "```", "---", "![", "<", ":"]
    private static let markdownLink = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)

    /// Last line of a message that reads as prose (skips images, code fences, tables, tags), without markdown.
    static func lastMeaningfulLine(of text: String?) -> String? {
        guard let text else { return nil }
        let prose = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty && !nonProsePrefixes.contains { line.hasPrefix($0) } }
            .map { stripMarkdown(replacingLinks(in: $0)) }
            .last { !$0.isEmpty }
        return prose.map { truncate($0, to: detailLimit) }
    }

    /// "[texto](url)" → "texto".
    static func replacingLinks(in line: String) -> String {
        guard let markdownLink else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return markdownLink.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
    }

    static func firstLine(of text: String, limit: Int = 90) -> String {
        let line = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        return truncate(stripMarkdown(line), to: limit)
    }

    static func stripMarkdown(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespaces)
        for marker in ["**", "__", "`"] {
            cleaned = cleaned.replacingOccurrences(of: marker, with: "")
        }
        while let first = cleaned.first, "#>-*•".contains(first) {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum LogFile {
    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Complete lines from the end of a (possibly huge) JSONL file, oldest first.
    static func lastLines(of url: URL, maxBytes: UInt64 = 524_288) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.filter { !$0.isEmpty }
    }

    /// Complete lines from the start of a JSONL file.
    static func firstLines(of url: URL, maxBytes: Int = 262_144) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if data.count == maxBytes, !lines.isEmpty { lines.removeLast() }
        return lines.filter { !$0.isEmpty }
    }
}

enum JSONLine {
    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum RelativeTime {
    static func describe(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "agora" }
        if minutes < 60 { return "há \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "há \(hours) h" }
        let days = hours / 24
        return days == 1 ? "ontem" : "há \(days) dias"
    }
}
