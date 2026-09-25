import ApplicationServices
import ServiceManagement
import SwiftUI

enum Settings {
    static func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("一般", symbol: "gearshape", GeneralSettingsView()))
        tabs.addTabViewItem(tab("操作", symbol: "list.bullet", ActionsSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func tab<Content: View>(_ label: String, symbol: String, _ view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()
    @State private var message: String?

    var body: some View {
        Form {
            Toggle("ログイン時に起動", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            LabeledContent("アクセシビリティ") {
                HStack {
                    Text(trusted ? "許可済み" : "未許可")
                        .foregroundStyle(trusted ? Color.secondary : Color.red)
                    Button("システム設定を開く") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "ログイン項目を変更できません: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct ActionsSettingsView: View {
    @State private var ids = Actions.ordered(Actions.all, by: Actions.savedOrder).map(\.id)
    @State private var hidden = Actions.hiddenIDs

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Toggle(isOn: shown(id)) {
                            Label(action(id).title, systemImage: action(id).symbol)
                        }
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                }
                .onMove { source, destination in
                    ids.move(fromOffsets: source, toOffset: destination)
                    Actions.savedOrder = ids
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Text("ドラッグで並べ替え、チェックを外すと小窓に出なくなる")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 280)
    }

    private func action(_ id: String) -> Action {
        Actions.all.first { $0.id == id }!
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(id) },
            set: { isOn in
                if isOn {
                    hidden.remove(id)
                } else {
                    hidden.insert(id)
                }
                Actions.hiddenIDs = hidden
            })
    }
}
