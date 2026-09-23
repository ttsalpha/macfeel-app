import AppKit
import SwiftUI

/// Owns the status item and its popover.
///
/// SwiftUI's `MenuBarExtra` cannot be opened from code, so launching the app
/// would only ever park an icon in the menu bar and leave the user staring at
/// nothing. Driving `NSStatusItem` directly is what makes "open the app and the
/// panel appears" possible.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var quitMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "laptopcomputer",
            accessibilityDescription: "MacFeel"
        )
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        let panel = NSPopover()
        panel.behavior = .transient
        // SwiftUI resizes the content instantly, so an AppKit glide afterwards
        // drags every visible row along with it. Costs the open fade.
        panel.animates = false
        panel.contentViewController = NSHostingController(rootView: RootView().environment(model))
        popover = panel

        installQuitShortcut()
        show()
    }

    /// Fires when the app is launched again while already running, which is what
    /// clicking it in Finder, Spotlight or the Dock does to an agent app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return true
    }

    /// The menu bar an agent app never shows is the only thing that would carry
    /// ⌘Q, so the panel handles the key itself. The monitor only sees events
    /// while the app is frontmost, which is exactly while the panel is up.
    private func installQuitShortcut() {
        quitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers?.lowercased() == "q"
            else { return event }
            MainActor.assumeIsolated { NSApp.terminate(nil) }
            return nil
        }
    }

    @objc private func toggle() {
        popover?.isShown == true ? popover?.performClose(nil) : show()
    }

    private func show() {
        guard let button = statusItem?.button, let popover else { return }
        // The user may have granted or revoked Input Monitoring in System
        // Settings while the app sat in the background, so recheck every time
        // the panel comes up rather than trusting what was true at launch.
        model.panelWillOpen()
        // Without activating, the panel can come up behind the keyboard focus of
        // whatever app was in front, and keystrokes never reach the shortcut.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
