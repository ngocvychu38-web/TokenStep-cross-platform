import AppKit

enum WindowFocus {
    static func bringMainWindowToFront() {
        focus(after: 0.10, closeTransientPanels: false)
        focus(after: 0.24, closeTransientPanels: true)
    }

    private static func focus(after delay: TimeInterval, closeTransientPanels: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)

            let mainWindows = NSApp.windows.filter { $0.title == "TokenStep" || $0.identifier?.rawValue == "main" }
            if closeTransientPanels {
                for window in NSApp.windows where window.title.isEmpty && !mainWindows.contains(window) {
                    window.close()
                }
            }

            for window in mainWindows {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
