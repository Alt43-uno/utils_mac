import AppKit
import MouseCraftCore
import MouseCraftNative

/// All generated events carry a tag so our own event tap never processes them again.
enum EventOutput {
    static let tag: Int64 = 0x4D4352414654
    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: tag)
        event.post(tap: .cghidEventTap)
    }
    static func key(_ code: UInt16, flags: UInt64 = 0) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = CGEventFlags(rawValue: flags); up.flags = down.flags
        post(down); post(up)
    }
    static func click(button: Int, count: Int = 1, flags: UInt64 = 0) {
        let index = button - 1
        let downType: CGEventType = index == 0 ? .leftMouseDown : index == 1 ? .rightMouseDown : .otherMouseDown
        let upType: CGEventType = index == 0 ? .leftMouseUp : index == 1 ? .rightMouseUp : .otherMouseUp
        let location = CGEvent(source: nil)?.location ?? .zero
        guard let cgButton = CGMouseButton(rawValue: UInt32(index)) else { return }
        for level in 1...max(1, count) {
            for type in [downType, upType] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) else { continue }
                event.flags = CGEventFlags(rawValue: flags)
                event.setIntegerValueField(.mouseEventClickState, value: Int64(level)); post(event)
            }
        }
    }
    static func scroll(_ vector: ScrollVector, flags: UInt64, phase: Int64 = 0) {
        guard vector.x.isFinite, vector.y.isFinite else { return }
        guard vector.x != 0 || vector.y != 0 || phase != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(min(Double(Int32.max), max(Double(Int32.min), vector.y))),
                                  wheel2: Int32(min(Double(Int32.max), max(Double(Int32.min), vector.x))), wheel3: 0) else { return }
        event.flags = CGEventFlags(rawValue: flags)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if phase != 0 { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase) }
        post(event)
    }
}

final class ActionExecutor {
    var notify: (String) -> Void = { _ in }
    var pause: () -> Void = {}
    private let command = Modifier.command.rawValue
    private let shift = Modifier.shift.rawValue
    func perform(_ action: MouseAction) {
        switch action.kind {
        case .none: break
        case .back: EventOutput.key(33, flags: command)
        case .forward: EventOutput.key(30, flags: command)
        case .missionControl: symbolic(32)
        case .appExpose: symbolic(33)
        case .desktop: symbolic(36)
        case .applications: symbolic(160)
        case .spaceLeft: symbolic(79)
        case .spaceRight: symbolic(81)
        case .lookup: symbolic(70)
        case .quickLook: EventOutput.key(49)
        case .zoomIn: EventOutput.key(24, flags: command)
        case .zoomOut: EventOutput.key(27, flags: command)
        case .resetZoom: EventOutput.key(29, flags: command)
        case .copy: EventOutput.key(8, flags: command)
        case .paste: EventOutput.key(9, flags: command)
        case .undo: EventOutput.key(6, flags: command)
        case .redo: EventOutput.key(6, flags: command | shift)
        case .closeTab: EventOutput.key(13, flags: command)
        case .newTab: EventOutput.key(17, flags: command)
        case .nextTab: EventOutput.key(48, flags: Modifier.control.rawValue)
        case .previousTab: EventOutput.key(48, flags: Modifier.control.rawValue | shift)
        case .middleClick: EventOutput.click(button: 3)
        case .leftClick: EventOutput.click(button: 1)
        case .rightClick: EventOutput.click(button: 2)
        case .shortcut: EventOutput.key(action.keyCode, flags: action.modifiers)
        case .openApplication:
            let url = URL(fileURLWithPath: action.applicationPath)
            guard Bundle(url: url) != nil else { notify("Приложение не найдено: \(url.lastPathComponent)"); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { DispatchQueue.main.async { self.notify(error.localizedDescription) } }
            }
        case .togglePause: pause()
        case .smartZoom:
            postNative(NativeGestureEvents.smartZoom())
        case .nativeZoomIn, .nativeZoomOut:
            postNative(NativeGestureEvents.magnify(0, phase: .began))
            postNative(NativeGestureEvents.magnify(action.kind == .nativeZoomIn ? 0.06 : -0.06, phase: .changed))
            postNative(NativeGestureEvents.magnify(0, phase: .ended))
        case .swipeLeft, .swipeRight:
            postNative(NativeGestureEvents.swipe(left: action.kind == .swipeLeft, phase: .began))
            postNative(NativeGestureEvents.swipe(left: action.kind == .swipeLeft, phase: .ended))
        }
    }
    private func postNative(_ event: CGEvent?) {
        guard let event else { notify("Нативный жест недоступен в этой версии macOS. Выберите действие через клавиши."); return }
        EventOutput.post(event)
    }
    /// Respect the user's existing shortcuts; never rewrite com.apple.symbolichotkeys.
    private func symbolic(_ id: Int) {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
        let hotkeys = domain?["AppleSymbolicHotKeys"] as? [String: Any]
        if let entry = hotkeys?[String(id)] as? [String: Any] {
            if let enabled = entry["enabled"] as? Bool, !enabled { notify("Системное сочетание отключено (\(id)). Включите его в настройках клавиатуры macOS."); return }
            if let value = entry["value"] as? [String: Any], let params = value["parameters"] as? [NSNumber], params.count >= 3 {
                let code = params[1].intValue
                if (0...127).contains(code) { EventOutput.key(UInt16(code), flags: params[2].uint64Value); return }
            }
        }
        switch id {
        case 32: EventOutput.key(126, flags: Modifier.control.rawValue)
        case 33: EventOutput.key(125, flags: Modifier.control.rawValue)
        case 36: EventOutput.key(103) // F11
        case 70: EventOutput.key(2, flags: command | Modifier.control.rawValue)
        case 79: EventOutput.key(123, flags: Modifier.control.rawValue)
        case 81: EventOutput.key(124, flags: Modifier.control.rawValue)
        case 160:
            let path = "/System/Applications/Launchpad.app"
            if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
        default: notify("Системное сочетание не найдено.")
        }
    }
}
