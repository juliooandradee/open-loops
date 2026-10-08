import AppKit
import SwiftUI

// MARK: - Theme (MED Magno: deep green, gold, nude)

enum Theme {
    static let background = Color(hex: 0x172E27)
    static let border = Color(hex: 0xD2BC86, opacity: 0.22)
    static let gold = Color(hex: 0xD2BC86)
    static let primaryText = Color(hex: 0xF4F2F0, opacity: 0.96)
    static let secondaryText = Color(hex: 0xF4F2F0, opacity: 0.62)
    static let tertiaryText = Color(hex: 0xF4F2F0, opacity: 0.34)
    static let hoverFill = Color.white.opacity(0.06)
    static let morph = Animation.spring(response: 0.3, dampingFraction: 0.86)

    static func leftRounded(_ radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
    }

    static var divider: some View { Rectangle().fill(border).frame(height: 1) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension TaskStatus {
    var color: Color {
        switch self {
        case .needsYou: return Color(hex: 0xE8913A)
        case .readyToReview: return Color(hex: 0x8ED3A0)
        case .working: return Color(hex: 0xE2C779)
        case .openTab: return Color(hex: 0xB9C6BF)
        }
    }

    var label: String {
        switch self {
        case .needsYou: return "Precisa de você"
        case .readyToReview: return "Pronta pra revisar"
        case .working: return "IA trabalhando"
        case .openTab: return "Aba aberta"
        }
    }
}

// MARK: - Root: one shape that morphs between the tab and the panel

struct RootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: PanelState
    let actions: PanelActions

    private var shapeSize: CGSize {
        state.isExpanded ? CGSize(width: PanelLayout.panelWidth, height: state.panelHeight) : PanelLayout.tabSize
    }

    var body: some View {
        let shape = Theme.leftRounded(state.isExpanded ? 16 : 10)
        ZStack(alignment: .topTrailing) {
            if state.isExpanded {
                ExpandedPanelView(store: store, settings: settings, state: state, actions: actions)
                    .transition(.opacity.animation(.easeOut(duration: 0.14).delay(0.05)))
            } else {
                CollapsedTabView(tasks: store.tasks, isAlerting: store.hasUnseenFinish)
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
            }
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .topTrailing)
        .background(shape.fill(Theme.background))
        .clipShape(shape)
        .overlay(shape.stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(state.isExpanded ? 0.4 : 0.22), radius: state.isExpanded ? 18 : 5, x: -3, y: 4)
        .offset(y: state.isExpanded ? state.panelTop : state.tabTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(Theme.morph, value: state.isExpanded)
        .animation(Theme.morph, value: state.panelHeight)
        .animation(Theme.morph, value: state.panelTop)
        .animation(Theme.morph, value: state.tabTop)
        .environment(\.colorScheme, .dark)
    }
}

struct CollapsedTabView: View {
    let tasks: [AITask]
    let isAlerting: Bool

    var body: some View {
        let accent = tasks.map(\.status).min()?.color ?? Theme.tertiaryText
        ZStack {
            if isAlerting { PulsingGlow(color: accent) }
            VStack(spacing: 5) {
                if tasks.isEmpty {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
                } else {
                    Text("\(tasks.count)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(accent)
                    Circle().fill(accent).frame(width: 5, height: 5)
                }
            }
        }
        .frame(width: PanelLayout.tabSize.width, height: PanelLayout.tabSize.height)
    }
}

/// Only exists while an AI has finished unseen, so the repeating animation stops once the panel is opened.
struct PulsingGlow: View {
    let color: Color
    @State private var isBright = false

    var body: some View {
        Rectangle()
            .fill(color.opacity(isBright ? 0.32 : 0.06))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isBright = true }
            }
    }
}

// MARK: - Expanded panel

struct ExpandedPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: PanelState
    let actions: PanelActions
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(tasks: store.tasks, showsSettings: $state.showsSettings)
            Theme.divider
            taskList
            if state.showsSettings { SettingsSection(settings: settings, actions: actions) }
            PanelFooter(store: store)
        }
        .frame(width: PanelLayout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: actions.contentHeightChanged)
        .animation(.easeOut(duration: 0.2), value: store.tasks)
    }

    @ViewBuilder private var taskList: some View {
        if store.tasks.isEmpty {
            EmptyStateView()
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.tasks) { task in
                        TaskRow(
                            task: task,
                            showsSnooze: settings.showsSnoozeButton,
                            onOpen: { actions.open(task) },
                            onDone: { store.markDone(task) },
                            onSnooze: { store.snooze(task) }
                        )
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .padding(6)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { listHeight = $0 })
            }
            .frame(height: min(listHeight, PanelLayout.maxListHeight))
        }
    }
}

struct PanelHeader: View {
    let tasks: [AITask]
    @Binding var showsSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandEmblem().frame(width: 20, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Open Loops").font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.primaryText)
                Text(TaskSummary.describe(tasks))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            IconButton(systemName: showsSettings ? "xmark" : "gearshape", help: "Configurações") {
                showsSettings.toggle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Theme.gold)
            Text("Tudo em dia").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
            Text("Nenhuma conversa de IA esperando você.").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - Rows

struct TaskRow: View {
    let task: AITask
    let showsSnooze: Bool
    let onOpen: () -> Void
    let onDone: () -> Void
    let onSnooze: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderIcon(task: task)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                StatusLine(task: task)
                if let detail = task.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                if showsSnooze { RowActionButton(kind: .snooze, action: onSnooze) }
                RowActionButton(kind: .done, action: onDone)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(isHovered ? Theme.hoverFill : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .help(task.detail ?? task.title)
    }
}

struct StatusLine: View {
    let task: AITask

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: task.status)
            Text(task.status.label).foregroundStyle(task.status.color)
            Text("·").foregroundStyle(Theme.tertiaryText)
            if task.channel.isBrowserTab {
                Text("\(task.provider.displayName) no Chrome").foregroundStyle(Theme.secondaryText)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(RelativeTime.describe(task.lastActivity, now: context.date)).foregroundStyle(Theme.secondaryText)
                }
                if let place = task.channel.placeLabel {
                    Text("· \(place)").foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}

struct StatusDot: View {
    let status: TaskStatus
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 6, height: 6)
            .opacity(isDimmed ? 0.3 : 1)
            .onAppear {
                guard status == .working else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isDimmed = true }
            }
    }
}

struct ProviderIcon: View {
    let task: AITask

    var body: some View {
        let hasOwnApp = task.provider == .claude || task.provider == .chatgpt
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: hasOwnApp ? AppIcons.icon(for: task.provider) : AppIcons.chrome)
                .resizable()
                .frame(width: 26, height: 26)
            badge(hasOwnApp: hasOwnApp).offset(x: 3, y: 3)
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder private func badge(hasOwnApp: Bool) -> some View {
        switch task.channel {
        case .chromeTab where hasOwnApp:
            Image(nsImage: AppIcons.chrome).resizable().frame(width: 12, height: 12)
        case .codeTool:
            Image(systemName: "terminal.fill")
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Color.black.opacity(0.85)))
        default:
            EmptyView()
        }
    }
}

/// The ✓ (done) and 🌙 (snooze until tomorrow) buttons at the end of each row.
struct RowActionButton: View {
    enum Kind {
        case done, snooze

        var symbols: (idle: String, hover: String, active: String) {
            switch self {
            case .done: return ("circle", "checkmark.circle", "checkmark.circle.fill")
            case .snooze: return ("moon.zzz", "moon.zzz.fill", "moon.zzz.fill")
            }
        }

        var tint: Color { self == .done ? TaskStatus.readyToReview.color : Theme.gold }
        var help: String { self == .done ? "Marcar como feito" : "Adiar pra amanhã de manhã" }
    }

    let kind: Kind
    let action: () -> Void
    @State private var isActive = false
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isActive = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action)
        } label: {
            Image(systemName: isActive ? kind.symbols.active : (isHovered ? kind.symbols.hover : kind.symbols.idle))
                .font(.system(size: kind == .done ? 17 : 13))
                .foregroundStyle(isActive || isHovered ? kind.tint : Theme.tertiaryText)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(kind.help)
    }
}

// MARK: - Footer & small controls

struct PanelFooter: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        if store.lastHiddenTask != nil || store.chromePermissionDenied {
            VStack(alignment: .leading, spacing: 6) {
                if let task = store.lastHiddenTask {
                    Button(action: store.undoLastHide) {
                        Label("Desfazer “\(TextTools.truncate(task.title, to: 34))”", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                }
                if store.chromePermissionDenied {
                    Text("Chrome sem permissão: Ajustes do Sistema › Privacidade e Segurança › Automação")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Theme.divider }
        }
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ChipButton: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.background : Theme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Theme.gold : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Images

struct BrandEmblem: View {
    var body: some View {
        if let emblem = BrandImages.emblem {
            Image(nsImage: emblem).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(Theme.gold)
        }
    }
}

enum BrandImages {
    static let emblem = Bundle.main.image(forResource: "emblem")
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static var chrome: NSImage { appIcon(ChromeSource.bundleIdentifier) }

    static func icon(for provider: AIProvider) -> NSImage {
        switch provider {
        case .claude: return appIcon("com.anthropic.claudefordesktop")
        case .chatgpt: return appIcon("com.openai.codex", fallback: "com.openai.chat")
        default: return chrome
        }
    }

    private static func appIcon(_ bundleIdentifier: String, fallback: String? = nil) -> NSImage {
        if let cached = cache[bundleIdentifier] { return cached }
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? fallback.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
        let image = appURL.map { workspace.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            ?? NSImage()
        cache[bundleIdentifier] = image
        return image
    }
}
