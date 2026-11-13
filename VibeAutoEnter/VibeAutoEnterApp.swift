import SwiftUI
import UserNotifications

@main
struct VibeAutoEnterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("VibeAutoEnter", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var monitor: AutoEnterMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Notifications granted: \(granted)")
        }

        // Set up menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "return.left", accessibilityDescription: "VibeAutoEnter")
            button.toolTip = "VibeAutoEnter (Active)"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Set up popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 530)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        self.popover = popover

        // Start monitor immediately
        monitor = AutoEnterMonitor.shared
        monitor?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(sender)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
