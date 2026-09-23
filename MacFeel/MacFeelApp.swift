import SwiftUI

@main
struct MacFeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The entire interface lives in the status item popover that AppDelegate
        // owns. This scene exists only because App requires one.
        Settings { EmptyView() }
            // Dropping the Settings menu item takes ⌘, with it. There is nothing
            // to configure outside the panel, so the shortcut only ever opened an
            // empty window.
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}
