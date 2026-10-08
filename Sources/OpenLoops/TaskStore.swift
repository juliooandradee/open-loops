import AppKit
import Combine

/// Polls every source in the background and publishes the conversations still waiting on the user.
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AITask] = []
    @Published private(set) var lastHiddenTask: AITask?
    @Published private(set) var chromePermissionDenied = false
    /// An AI finished since the panel was last opened (the tab pulses).
    @Published private(set) var hasUnseenFinish = false

    let settings: AppSettings
    private static let refreshInterval: TimeInterval = 5
    private static let lastSummaryKey = "lastMorningSummaryAt"

    private let notifier: Notifier
    private let claudeSource = ClaudeSource()
    private let cliSource = ClaudeCodeCLISource()
    private let codexSource = CodexSource()
    private let chromeSource = ChromeSource()
    private let hiddenStore = HiddenTaskStore()
    private let scanQueue = DispatchQueue(label: "open-loops.scan", qos: .utility)
    /// Chrome gets its own queue: AppleScript can hang (e.g. while macOS asks for permission) and must not hold up the rest.
    private let chromeQueue = DispatchQueue(label: "open-loops.chrome", qos: .utility)
    private var timer: Timer?
    private var settingsSubscription: AnyCancellable?
    private var isScanningApps = false
    private var isScanningChrome = false
    private var tickCount = 0
    private var appTasks: [AITask] = []
    private var tabTasks: [AITask] = []
    private var previousStatuses: [String: TaskStatus]?

    init(settings: AppSettings, notifier: Notifier) {
        self.settings = settings
        self.notifier = notifier
        if UserDefaults.standard.object(forKey: Self.lastSummaryKey) == nil {
            markMorningSummarySent()
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        settingsSubscription = settings.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAppSources() }
    }

    func refresh() {
        refreshAppSources()
        if tickCount % 2 == 0 { refreshChromeTabs() }
        tickCount += 1
    }

    func task(withId id: String) -> AITask? {
        (appTasks + tabTasks).first { $0.id == id }
    }

    func markDone(_ task: AITask) { hide(task, until: nil) }

    func snooze(_ task: AITask) { hide(task, until: settings.nextMorning()) }

    func undoLastHide() {
        guard let task = lastHiddenTask else { return }
        hiddenStore.unhide(task)
        lastHiddenTask = nil
        publishVisibleTasks()
    }

    func forgetLastHide() {
        if lastHiddenTask != nil { lastHiddenTask = nil }
    }

    func acknowledgeFinishes() {
        if hasUnseenFinish { hasUnseenFinish = false }
    }

    func open(_ task: AITask) {
        switch task.channel {
        case .desktopApp:
            guard let url = task.openURL else { return }
            NSWorkspace.shared.open(url)
        case .chromeTab(let windowId, let tabId):
            chromeQueue.async { [chromeSource] in chromeSource.focus(windowId: windowId, tabId: tabId) }
        case .codeTool(_, let appCandidates):
            AppLauncher.activateFirstAvailable(appCandidates)
        }
    }

    // MARK: - Scanning

    private func refreshAppSources() {
        guard !isScanningApps else { return }
        isScanningApps = true
        let cutoff = Date().addingTimeInterval(-Double(settings.lookbackDays) * 86_400)
        let includesCLI = settings.includesClaudeCodeCLI
        scanQueue.async { [weak self] in
            guard let self else { return }
            let results = self.scanApps(since: cutoff, includesCLI: includesCLI)
            DispatchQueue.main.async { self.receiveAppTasks(results) }
        }
    }

    /// Runs on `scanQueue`. The desktop scan goes first: it tells the CLI source which transcripts to skip.
    private func scanApps(since cutoff: Date, includesCLI: Bool) -> [AITask] {
        let desktop = claudeSource.scan(since: cutoff)
        let terminal = includesCLI ? cliSource.scan(since: cutoff, excluding: claudeSource.desktopTranscriptIds) : []
        return desktop + terminal + codexSource.scan(since: cutoff)
    }

    private func refreshChromeTabs() {
        guard !isScanningChrome else { return }
        isScanningChrome = true
        chromeQueue.async { [weak self] in
            guard let self else { return }
            let tabs = self.chromeSource.scan()
            let denied = self.chromeSource.permissionDenied
            DispatchQueue.main.async {
                self.isScanningChrome = false
                self.tabTasks = tabs
                if self.chromePermissionDenied != denied { self.chromePermissionDenied = denied }
                self.publishVisibleTasks()
            }
        }
    }

    private func receiveAppTasks(_ results: [AITask]) {
        isScanningApps = false
        detectFinishes(in: results)
        appTasks = results
        publishVisibleTasks()
        sendMorningSummaryIfDue()
    }

    private func publishVisibleTasks() {
        let visible = (appTasks + tabTasks)
            .filter { !hiddenStore.isHidden($0) }
            .sorted { lhs, rhs in
                lhs.status != rhs.status ? lhs.status < rhs.status : lhs.lastActivity > rhs.lastActivity
            }
        if visible != tasks { tasks = visible }
    }

    private func hide(_ task: AITask, until: Date?) {
        hiddenStore.hide(task, until: until)
        lastHiddenTask = task
        publishVisibleTasks()
    }

    // MARK: - Notifications

    /// A conversation that was "working" on the previous scan and now waits on the user has just finished.
    private func detectFinishes(in results: [AITask]) {
        defer {
            previousStatuses = Dictionary(results.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        }
        guard let previous = previousStatuses, settings.notifyWhenDone else { return }
        let finished = results.filter { task in
            previous[task.id] == .working && task.status.isWaitingOnUser && !hiddenStore.isHidden(task)
        }
        guard !finished.isEmpty else { return }
        hasUnseenFinish = true
        finished.forEach(notifier.notifyFinished)
    }

    /// Once a day, the first scan after the chosen hour (also right after the Mac wakes up).
    private func sendMorningSummaryIfDue(now: Date = Date()) {
        guard settings.morningSummary else { return }
        let calendar = Calendar.current
        let lastSent = UserDefaults.standard.object(forKey: Self.lastSummaryKey) as? Date
        let alreadySentToday = lastSent.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        guard calendar.component(.hour, from: now) >= settings.morningHour, !alreadySentToday else { return }
        markMorningSummarySent()
        let pending = tasks.filter { $0.status != .working }
        if !pending.isEmpty { notifier.notifyMorningSummary(pending) }
    }

    private func markMorningSummarySent() {
        UserDefaults.standard.set(Date(), forKey: Self.lastSummaryKey)
    }
}

enum AppLauncher {
    /// Brings the first running app of the list forward, or opens the first one installed.
    static func activateFirstAvailable(_ bundleIdentifiers: [String]) {
        for identifier in bundleIdentifiers {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
                running.activate(options: [])
                return
            }
        }
        let workspace = NSWorkspace.shared
        guard let installed = bundleIdentifiers.lazy.compactMap(workspace.urlForApplication(withBundleIdentifier:)).first
        else { return }
        workspace.openApplication(at: installed, configuration: NSWorkspace.OpenConfiguration())
    }
}
