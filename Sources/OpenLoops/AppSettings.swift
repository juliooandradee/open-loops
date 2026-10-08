import Foundation

/// User preferences, each one a switch in the panel's settings. Persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let lookbackChoices = [1, 3, 7]
    static let morningHourChoices = [7, 8, 9]

    @Published var lookbackDays: Int { didSet { persist(lookbackDays, Keys.lookbackDays) } }
    @Published var notifyWhenDone: Bool { didSet { persist(notifyWhenDone, Keys.notifyWhenDone) } }
    @Published var showsSnoozeButton: Bool { didSet { persist(showsSnoozeButton, Keys.showsSnoozeButton) } }
    @Published var morningSummary: Bool { didSet { persist(morningSummary, Keys.morningSummary) } }
    @Published var morningHour: Int { didSet { persist(morningHour, Keys.morningHour) } }
    @Published var includesClaudeCodeCLI: Bool { didSet { persist(includesClaudeCodeCLI, Keys.includesClaudeCodeCLI) } }

    private enum Keys {
        static let lookbackDays = "lookbackDays"
        static let notifyWhenDone = "notifyWhenDone"
        static let showsSnoozeButton = "showsSnoozeButton"
        static let morningSummary = "morningSummary"
        static let morningHour = "morningHour"
        static let includesClaudeCodeCLI = "includesClaudeCodeCLI"
    }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Keys.lookbackDays: 3,
            Keys.notifyWhenDone: true,
            Keys.showsSnoozeButton: true,
            Keys.morningSummary: true,
            Keys.morningHour: 8,
            Keys.includesClaudeCodeCLI: true,
        ])
        lookbackDays = Self.pick(defaults.integer(forKey: Keys.lookbackDays), from: Self.lookbackChoices, fallback: 3)
        notifyWhenDone = defaults.bool(forKey: Keys.notifyWhenDone)
        showsSnoozeButton = defaults.bool(forKey: Keys.showsSnoozeButton)
        morningSummary = defaults.bool(forKey: Keys.morningSummary)
        morningHour = Self.pick(defaults.integer(forKey: Keys.morningHour), from: Self.morningHourChoices, fallback: 8)
        includesClaudeCodeCLI = defaults.bool(forKey: Keys.includesClaudeCodeCLI)
    }

    /// Next morning at the summary hour: later today if it is still before that hour (e.g. 2 a.m.), otherwise tomorrow.
    func nextMorning(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let todayAtHour = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: now) ?? now
        return todayAtHour > now ? todayAtHour : calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? todayAtHour
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private static func pick(_ value: Int, from choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }
}
