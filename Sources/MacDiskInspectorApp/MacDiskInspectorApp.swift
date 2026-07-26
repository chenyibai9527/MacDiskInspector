import SwiftUI

@main
struct MacDiskInspectorApp: App {
    @StateObject private var model = InspectorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            MacDiskInspectorCommands(model: model)
        }

        Window("关于 Mac 磁盘扫描助手", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
    }
}

private struct MacDiskInspectorCommands: Commands {
    @ObservedObject var model: InspectorViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Mac 磁盘扫描助手") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .newItem) {
            Button("选择目录并扫描…") {
                model.chooseAndScan()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
    }
}
