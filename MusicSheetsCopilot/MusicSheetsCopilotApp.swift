import SwiftUI

@main
struct MusicSheetsCopilotApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            NavigationStack {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open MusicXML File...") {
                    NotificationCenter.default.post(name: .openDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let openDocument = Notification.Name("openDocument")
}
