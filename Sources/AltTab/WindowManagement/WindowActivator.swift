import AppKit
import ApplicationServices

enum WindowActivator {
    static func activate(_ window: WindowInfo) {
        MRUTracker.shared.bump(window.id)

        if window.isMinimized {
            window.ax.set(kAXMinimizedAttribute, kCFBooleanFalse)
            // De-miniaturisation is animated inside the owning app; raise once it lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { raise(window) }
        } else {
            raise(window)
        }
    }

    private static func raise(_ window: WindowInfo) {
        window.ax.set(kAXMainAttribute, kCFBooleanTrue)
        window.ax.perform(kAXRaiseAction)
        // AXFrontmost is the accessibility-native way to bring an app forward and,
        // unlike -[NSRunningApplication activate], it is not subject to the
        // "app must be recently active" restriction for background agents.
        AXUIElement.app(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }
}
