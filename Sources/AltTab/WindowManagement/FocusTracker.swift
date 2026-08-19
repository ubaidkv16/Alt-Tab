import AppKit
import ApplicationServices

/// Keeps the MRU list current by observing focus changes, event-driven.
/// No polling, so idle CPU stays at zero.
final class FocusTracker {
    static let shared = FocusTracker()

    private var observers: [pid_t: AXObserver] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MRUTracker.shared.seed()

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(app.processIdentifier)
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            // Apps need a moment before their AX tree exists.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.attach(app.processIdentifier)
                WindowLister.shared.scheduleRefresh()
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observers.removeValue(forKey: app.processIdentifier)
            WindowLister.shared.scheduleRefresh()
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if self.observers[app.processIdentifier] == nil, app.activationPolicy == .regular {
                self.attach(app.processIdentifier)
            }
            if let wid = AXUIElement.app(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID {
                MRUTracker.shared.bump(wid)
            }
            WindowLister.shared.scheduleRefresh()
        }
    }

    private func attach(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusChanged, &observer) == .success, let observer else { return }

        let app = AXUIElement.app(pid)
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXApplicationActivatedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }
}

private let focusChanged: AXObserverCallback = { _, element, _, _ in
    if let wid = element.windowID {
        MRUTracker.shared.bump(wid)
    } else if let wid = element.element(kAXFocusedWindowAttribute)?.windowID {
        MRUTracker.shared.bump(wid)
    }
}
