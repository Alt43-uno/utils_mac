import AppKit
import Carbon.HIToolbox

/// Registers system-wide shortcuts through the Carbon hot key API, which is
/// still the only way to get global shortcuts without Accessibility permission.
final class HotkeyManager {
    /// Stable identifiers so re-registering keeps the same Carbon hot key IDs.
    enum Action: UInt32, CaseIterable {
        case captureArea = 1
        case captureWindow = 2
        case captureFullScreen = 3

        var mode: CaptureMode {
            switch self {
            case .captureArea: return .area
            case .captureWindow: return .window
            case .captureFullScreen: return .fullScreen
            }
        }

        init?(mode: CaptureMode) {
            switch mode {
            case .area: self = .captureArea
            case .window: self = .captureWindow
            case .fullScreen: self = .captureFullScreen
            }
        }
    }

    /// Invoked on the main thread when a registered shortcut fires.
    var onAction: ((Action) -> Void)?

    private static let signature: OSType = 0x53534254 // 'SSBT'
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    // MARK: - Registration

    /// Replaces all registrations. Returns the actions that could not be bound
    /// (usually because another app already owns the combination).
    @discardableResult
    func apply(_ combos: [CaptureMode: KeyCombo]) -> [Action] {
        unregisterAll()
        var failures: [Action] = []
        for action in Action.allCases {
            guard let combo = combos[action.mode], combo.isValid else { continue }
            if !register(action: action, combo: combo) {
                failures.append(action)
            }
        }
        return failures
    }

    private func register(action: Action, combo: KeyCombo) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(UInt32(combo.keyCode),
                                         combo.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        guard status == noErr, let reference else {
            Log.hotkeys.error("RegisterEventHotKey failed for \(action.rawValue, privacy: .public) status=\(status, privacy: .public)")
            return false
        }
        hotKeyRefs[action.rawValue] = reference
        Log.hotkeys.info("Registered \(combo.displayString, privacy: .public) for \(String(describing: action), privacy: .public)")
        return true
    }

    func unregisterAll() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
    }

    // MARK: - Carbon plumbing

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotkeyManager.signature,
                  let action = Action(rawValue: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onAction?(action)
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }
}
