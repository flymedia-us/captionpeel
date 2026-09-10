import SwiftUI

@main
struct CaptionPeelApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("CaptionPeel") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Export SRT…") {
                    model.presentSavePanel()
                }
                .keyboardShortcut("s")
                .disabled(model.cues.isEmpty)
            }
        }
    }
}
