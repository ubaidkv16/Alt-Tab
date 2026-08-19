import ApplicationServices
import CoreGraphics

/// Private-but-universally-used bridge from an AXUIElement window to its CGWindowID.
/// There is no public equivalent; every window switcher on macOS relies on it.
/// If it ever fails we fall back to matching on (pid, title, frame).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ out: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    static func app(_ pid: pid_t) -> AXUIElement {
        let e = AXUIElementCreateApplication(pid)
        // Apps that hang must not hang us.
        AXUIElementSetMessagingTimeout(e, 0.25)
        return e
    }

    func raw(_ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success else { return nil }
        return v
    }

    func str(_ attr: String) -> String? { raw(attr) as? String }
    func flag(_ attr: String) -> Bool { (raw(attr) as? NSNumber)?.boolValue ?? false }

    func element(_ attr: String) -> AXUIElement? {
        guard let v = raw(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(v, to: AXUIElement.self)
    }

    func elements(_ attr: String) -> [AXUIElement] {
        (raw(attr) as? [AXUIElement]) ?? []
    }

    @discardableResult
    func set(_ attr: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attr as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    var windowID: CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(self, &wid) == .success && wid != 0 ? wid : nil
    }

    var frame: CGRect? {
        guard let p = raw(kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = raw(kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &origin)
        AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
