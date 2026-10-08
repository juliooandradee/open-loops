import AppKit
import SwiftUI

/// Geometry published to SwiftUI. Offsets are measured from the top of the window strip.
final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var showsSettings = false
    @Published var tabTop: CGFloat = 0
    @Published var panelTop: CGFloat = 0
    @Published var panelHeight: CGFloat = 320
}

struct PanelActions {
    let open: (AITask) -> Void
    let moveTab: (_ upward: Bool) -> Void
    let contentHeightChanged: (CGFloat) -> Void
    let quit: () -> Void
}

enum PanelLayout {
    static let tabSize = CGSize(width: 26, height: 58)
    static let panelWidth: CGFloat = 352
    static let maxListHeight: CGFloat = 480
    /// Room on the left of the panel for its shadow.
    static let shadowMargin: CGFloat = 30
    static let edgeInset: CGFloat = 8
}

/// Never activates the app (the user stays in their app), but can take clicks right away.
private final class SidePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// A non-key window spends the first click on becoming key, and views inside the list's scroll view don't accept
    /// "first mouse" — so a row needed two clicks. Becoming key before dispatching lets that same click reach the row.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A transparent strip glued to the right edge of the main screen. The tab lives in it and morphs into the panel
/// on hover, then retracts into the tab again — the same feel as Codenotch.
final class SidePanelController {
    private static let offsetKey = "tabVerticalOffset"
    /// Codenotch's tab sits at the vertical middle of the edge; ours rests just above it.
    private static let defaultOffset: CGFloat = 84
    private static let offsetStep: CGFloat = 40
    private static let expandDelay: TimeInterval = 0.06
    private static let collapseDelay: TimeInterval = 0.16
    private static let pinnedTimeout: TimeInterval = 12
    private static let raisedLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    let state = PanelState()
    private let store: TaskStore
    private let panel: SidePanel
    private var verticalOffset: CGFloat
    private var contentHeight: CGFloat = 320
    private var mouseMonitors: [Any] = []
    private var exitPollTimer: Timer?
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    /// Opened from a notification: stays open until the mouse has visited it (or a timeout).
    private var isPinned = false

    init(store: TaskStore) {
        self.store = store
        let savedOffset = UserDefaults.standard.object(forKey: Self.offsetKey) as? Double
        verticalOffset = savedOffset.map { CGFloat($0) } ?? Self.defaultOffset
        panel = Self.makePanel()
        installContent()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.placeWindow() }
    }

    func show() {
        placeWindow()
        panel.orderFrontRegardless()
        startMouseTracking()
    }

    /// Opens the panel without hover (e.g. from the morning notification).
    func presentPinned() {
        isPinned = true
        setExpanded(true)
        schedule(after: Self.pinnedTimeout) { [weak self] in
            guard let self, self.isPinned else { return }
            self.setExpanded(false)
        }
    }

    // MARK: - Setup

    private static func makePanel() -> SidePanel {
        let panel = SidePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private func installContent() {
        let actions = PanelActions(
            open: { [weak self] task in self?.open(task) },
            moveTab: { [weak self] upward in self?.moveTab(upward: upward) },
            contentHeightChanged: { [weak self] height in self?.updateContentHeight(height) },
            quit: { NSApp.terminate(nil) }
        )
        let root = RootView(store: store, settings: store.settings, state: state, actions: actions)
        let hostingView = FirstMouseHostingView(rootView: root)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    // MARK: - Mouse

    /// Collapsed, the window ignores the mouse, so every move reaches the global monitor (no polling needed).
    private func startMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.evaluateMouse()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.evaluateMouse()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func evaluateMouse() {
        if hotZone().contains(NSEvent.mouseLocation) {
            mouseEnteredHotZone()
        } else {
            mouseLeftHotZone()
        }
    }

    private func mouseEnteredHotZone() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        isPinned = false
        guard !state.isExpanded, pendingExpand == nil else { return }
        pendingExpand = schedule(after: Self.expandDelay) { [weak self] in self?.setExpanded(true) }
    }

    private func mouseLeftHotZone() {
        pendingExpand?.cancel()
        pendingExpand = nil
        guard state.isExpanded, !isPinned, pendingCollapse == nil else { return }
        pendingCollapse = schedule(after: Self.collapseDelay) { [weak self] in self?.setExpanded(false) }
    }

    /// While open, the panel itself receives the mouse; a light poll catches the moment it leaves.
    private func setExitPolling(_ enabled: Bool) {
        exitPollTimer?.invalidate()
        exitPollTimer = nil
        guard enabled else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.evaluateMouse() }
        RunLoop.main.add(timer, forMode: .common)
        exitPollTimer = timer
    }

    @discardableResult
    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    // MARK: - Expand / collapse

    private func setExpanded(_ expanded: Bool) {
        pendingExpand = nil
        pendingCollapse = nil
        guard state.isExpanded != expanded else { return }
        if expanded { layoutContent() }
        state.isExpanded = expanded
        panel.ignoresMouseEvents = !expanded
        // Open: above Codenotch (same edge). Closed: back to its level, so Codenotch's own panel can cover our tab.
        panel.level = expanded ? Self.raisedLevel : .statusBar
        setExitPolling(expanded)
        if expanded {
            store.acknowledgeFinishes()
        } else {
            didCollapse()
        }
    }

    private func didCollapse() {
        isPinned = false
        state.showsSettings = false
        store.forgetLastHide()
        // A click made the panel key; hand the keyboard back once the retract animation is over.
        schedule(after: 0.4) { [weak self] in
            guard let self, !self.state.isExpanded, self.panel.isKeyWindow else { return }
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
        }
    }

    private func open(_ task: AITask) {
        store.open(task)
        setExpanded(false)
    }

    private func moveTab(upward: Bool) {
        let limit = (NSScreen.screens.first?.frame.height ?? 900) / 2 - 80
        let moved = verticalOffset + (upward ? Self.offsetStep : -Self.offsetStep)
        verticalOffset = min(max(moved, -limit), limit)
        UserDefaults.standard.set(Double(verticalOffset), forKey: Self.offsetKey)
        layoutContent()
    }

    private func updateContentHeight(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        layoutContent()
    }

    // MARK: - Geometry

    /// The main screen is the one carrying the menu bar (where Codenotch lives).
    private func placeWindow() {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let width = PanelLayout.panelWidth + PanelLayout.shadowMargin
        panel.setFrame(NSRect(x: area.maxX - width, y: area.minY, width: width, height: area.height), display: true)
        layoutContent()
    }

    private func layoutContent() {
        let stripHeight = panel.frame.height
        let tabCenter = panel.frame.maxY - ((NSScreen.screens.first?.frame.midY ?? 0) + verticalOffset)
        let panelHeight = min(contentHeight, stripHeight - 2 * PanelLayout.edgeInset)
        state.tabTop = Self.clamp(tabCenter - PanelLayout.tabSize.height / 2, size: PanelLayout.tabSize.height, in: stripHeight)
        state.panelTop = Self.clamp(tabCenter - panelHeight / 2, size: panelHeight, in: stripHeight)
        state.panelHeight = panelHeight
    }

    private static func clamp(_ top: CGFloat, size: CGFloat, in stripHeight: CGFloat) -> CGFloat {
        min(max(top, PanelLayout.edgeInset), stripHeight - size - PanelLayout.edgeInset)
    }

    /// Screen rect the mouse must be in: the tab when closed, tab + panel when open.
    private func hotZone() -> NSRect {
        let tab = screenRect(top: state.tabTop, size: PanelLayout.tabSize)
        guard state.isExpanded else { return tab.insetBy(dx: -1, dy: -2) }
        let panelSize = CGSize(width: PanelLayout.panelWidth, height: state.panelHeight)
        return tab.union(screenRect(top: state.panelTop, size: panelSize))
    }

    private func screenRect(top: CGFloat, size: CGSize) -> NSRect {
        let frame = panel.frame
        return NSRect(x: frame.maxX - size.width, y: frame.maxY - top - size.height, width: size.width, height: size.height)
    }
}
