import AppKit
import Carbon.HIToolbox

/// A global shortcut: a virtual key code plus modifier flags.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// Raw value of `NSEvent.ModifierFlags`, already masked to device-independent flags.
    var modifierFlags: UInt

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// At least one non-shift modifier is required, otherwise the shortcut would
    /// swallow ordinary typing system-wide.
    var isValid: Bool {
        let required: NSEvent.ModifierFlags = [.command, .control, .option]
        return !modifiers.intersection(required).isEmpty
    }

    /// Carbon modifier mask used by `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayString: String {
        Self.modifierString(modifiers) + KeyCodeNames.name(for: keyCode)
    }

    /// The ⌃⌥⇧⌘ prefix on its own, in the order macOS uses.
    static func modifierString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    static let captureArea = KeyCombo(keyCode: UInt16(kVK_ANSI_1), modifierFlags: [.control, .shift])
    static let captureWindow = KeyCombo(keyCode: UInt16(kVK_ANSI_2), modifierFlags: [.control, .shift])
    static let captureFullScreen = KeyCombo(keyCode: UInt16(kVK_ANSI_3), modifierFlags: [.control, .shift])
}
