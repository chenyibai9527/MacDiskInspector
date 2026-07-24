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
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("选择目录并扫描…") {
                    model.chooseAndScan()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
