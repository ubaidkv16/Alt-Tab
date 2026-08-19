import AppKit
import Carbon.HIToolbox

enum NavDirection { case left, right, up, down }

/// Global keyboard monitor.
///
/// A CGEventTap is used rather than NSEvent global monitors because only a tap
/// can *consume* the keystroke — otherwise Option+Tab would also reach the
/// frontmost application. Runs on its own thread so a slow main thread can never
/// make macOS disable the tap.
final class EventTap {
    static let shared = EventTap()

    var onCycle: ((_ backwards: Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onNavigate: ((NavDirection) -> Void)?

    private let lock = NSLock()
    private var _open = false
    private var next = Settings.shared.nextShortcut
    private var previous = Settings.shared.previousShortcut
    private var cancel = Settings.shared.cancelShortcut

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private(set) var running = false

    var switcherOpen: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _open }
        set { lock.lock(); _open = newValue; lock.unlock() }
    }

    func reloadShortcuts() {
        lock.lock()
        next = Settings.shared.nextShortcut
        previous = Settings.shared.previousShortcut
        cancel = Settings.shared.cancelShortcut
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        guard !running, Permissions.accessibility else { return false }
        running = true
        let ready = DispatchSemaphore(value: 0)
        var ok = false

        let thread = Thread { [weak self] in
            guard let self else { return }
            let mask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { ready.signal(); return }

            self.tap = tap
            self.runLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ok = true
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        thread.name = "com.wobble.alttab.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()

        _ = ready.wait(timeout: .now() + 2)
        if !ok { running = false }
        return ok
    }

    func stop() {
        guard running else { return }
        running = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
    }

    // MARK: - Tap thread

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        lock.lock()
        let open = _open
        let next = self.next, previous = self.previous, cancel = self.cancel
        lock.unlock()

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

        if type == .flagsChanged {
            let hold = next.holdFlag
            if open && !hold.isEmpty && !flags.contains(hold) {
                DispatchQueue.main.async { self.onCommit?() }
            }
            return pass
        }

        if type == .keyUp {
            return open ? nil : pass
        }

        guard type == .keyDown else { return pass }

        // Safety net: if the held modifier vanished without us seeing the
        // flagsChanged, close rather than keep swallowing the keyboard.
        let hold = next.holdFlag
        if open && !hold.isEmpty && !flags.contains(hold) {
            DispatchQueue.main.async { self.onCommit?() }
            return pass
        }

        if matches(previous, code, flags) {
            DispatchQueue.main.async { self.onCycle?(true) }
            return nil
        }
        if matches(next, code, flags) {
            DispatchQueue.main.async { self.onCycle?(false) }
            return nil
        }

        guard open else { return pass }

        // While the switcher is up we own the keyboard.
        if code == cancel.keyCode {
            DispatchQueue.main.async { self.onCancel?() }
        } else if code == UInt16(kVK_Return) || code == UInt16(kVK_ANSI_KeypadEnter) {
            DispatchQueue.main.async { self.onCommit?() }
        } else if let dir = direction(for: code) {
            DispatchQueue.main.async { self.onNavigate?(dir) }
        }
        return nil
    }

    private func matches(_ s: Shortcut, _ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return code == s.keyCode && flags.intersection(relevant) == s.flags.intersection(relevant)
    }

    private func direction(for code: UInt16) -> NavDirection? {
        switch Int(code) {
        case kVK_LeftArrow: return .left
        case kVK_RightArrow: return .right
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        default: return nil
        }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
