import SwiftUI
import AppKit

/// The menu bar dropdown — the macOS stand-in for the Android app's
/// notification actions and long-press menu.
struct MenuBarView: View {
    @EnvironmentObject private var locale: LocalizationManager
    @EnvironmentObject private var pet: PetController
    @ObservedObject private var tasks = AgentTaskStore.shared

    var body: some View {
        Button(pet.isRunning ? locale[.hideHer] : locale[.showHer]) {
            pet.toggle()
        }

        Button(locale[.nextFace]) {
            pet.cycleExpression()
        }
        .disabled(!pet.isRunning)

        Menu(locale[.skinMenu]) {
            ForEach(PetSkin.skins, id: \.index) { skin in
                Button {
                    pet.selectSkin(skin.index)
                } label: {
                    if pet.skinIndex == skin.index {
                        Label(locale[skin.nameKey], systemImage: "checkmark")
                    } else {
                        Text(locale[skin.nameKey])
                    }
                }
            }
        }

        Button(ChatText.title) { ChatWindowController.shared.open() }
        Button(taskMenuTitle) { AgentTaskWindowController.shared.open() }

        Divider()

        Toggle(ChatText.pick("安静模式", "Quiet mode"), isOn: $pet.quietMode)
            .keyboardShortcut("m", modifiers: [.command, .shift])

        Toggle(locale[.soundTitle], isOn: $pet.soundOn)
        Toggle(locale[.wanderTitle], isOn: $pet.wanderOn)
        Toggle(locale[.randomFaceTitle], isOn: $pet.randomFace)
        Toggle(locale[.launchAtLogin], isOn: launchAtLoginBinding)

        Divider()

        Button {
            SettingsWindowController.shared.open()
        } label: {
            Label(locale[.settings], systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            AboutWindowController.shared.open()
        } label: {
            Label(locale[.about], systemImage: "info.circle")
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label(locale[.quit], systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var taskMenuTitle: String {
        let title = ChatText.pick("派发工作任务…", "Assign a task…")
        if let active = tasks.jobs.first(where: { $0.id == tasks.activeID }) {
            return title + " · " + AgentTaskStore.statusText(active.status)
        }
        return title
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { _ = LoginItem.set(enabled: $0) }
        )
    }
}
