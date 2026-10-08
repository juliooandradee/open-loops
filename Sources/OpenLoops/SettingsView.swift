import SwiftUI

/// The ⚙︎ section: every extra can be switched on or off.
struct SettingsSection: View {
    @ObservedObject var settings: AppSettings
    let actions: PanelActions
    @State private var opensAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsToggle(title: "Abrir ao iniciar o Mac", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
            SettingsToggle(title: "Avisar quando a IA terminar", isOn: $settings.notifyWhenDone)
            SettingsToggle(title: "Botão “adiar pra amanhã”", isOn: $settings.showsSnoozeButton)
            SettingsToggle(title: "Resumo da manhã", isOn: $settings.morningSummary)
            if settings.morningSummary {
                ChoiceRow(title: "Horário do resumo", choices: AppSettings.morningHourChoices, selection: $settings.morningHour) {
                    "\($0)h"
                }
            }
            SettingsToggle(title: "Incluir Claude Code (terminal/editor)", isOn: $settings.includesClaudeCodeCLI)
            ChoiceRow(title: "Mostrar últimos", choices: AppSettings.lookbackChoices, selection: $settings.lookbackDays) {
                $0 == 1 ? "1 dia" : "\($0) dias"
            }
            HStack(spacing: 6) {
                Text("Posição da aba")
                Spacer()
                ChipButton(title: "↑ Subir") { actions.moveTab(true) }
                ChipButton(title: "↓ Descer") { actions.moveTab(false) }
            }
            HStack {
                Spacer()
                ChipButton(title: "Sair do Open Loops", action: actions.quit)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.secondaryText)
        .padding(14)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .top) { Theme.divider }
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(GoldSwitchStyle())
        }
    }
}

/// A small switch in the brand gold (drawn in SwiftUI, so it also shows up in rendered previews).
struct GoldSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Theme.gold : Color.white.opacity(0.16))
                .frame(width: 28, height: 16)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

struct ChoiceRow: View {
    let title: String
    let choices: [Int]
    @Binding var selection: Int
    let label: (Int) -> String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            ForEach(choices, id: \.self) { choice in
                ChipButton(title: label(choice), isSelected: selection == choice) { selection = choice }
            }
        }
    }
}
