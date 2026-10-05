import Foundation

public enum Modifier: UInt64, Codable, CaseIterable, Identifiable {
    case none = 0, shift = 131072, control = 262144, option = 524288, command = 1048576
    public var id: UInt64 { rawValue }
    public var title: String {
        switch self { case .none: return "None"; case .shift: return "⇧ Shift"
        case .control: return "⌃ Control"; case .option: return "⌥ Option"; case .command: return "⌘ Command" }
    }
    public func matches(_ flags: UInt64) -> Bool { self != .none && flags & rawValue != 0 }
    public static let mask: UInt64 = 131072 | 262144 | 524288 | 1048576
}

public enum Smoothness: String, Codable, CaseIterable, Identifiable {
    case off, regular, high
    public var id: String { rawValue }
    public var title: String { switch self { case .off: return "Off"; case .regular: return "Balanced"; case .high: return "Smooth" } }
    public var timeConstant: Double { switch self { case .off: return 0; case .regular: return 0.055; case .high: return 0.11 } }
}

public struct ScrollSettings: Codable, Equatable {
    public var enabled = true
    public var smoothness: Smoothness = .regular
    public var speed = 1.0
    public var reverse = true
    public var precision = false
    public var nativeZoom = false
    public var simulateTrackpad = false
    public var horizontalModifier: Modifier = .shift
    public var zoomModifier: Modifier = .command
    public var fastModifier: Modifier = .control
    public var preciseModifier: Modifier = .option
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case enabled, smoothness, speed, reverse, precision, nativeZoom, simulateTrackpad
        case horizontalModifier, zoomModifier, fastModifier, preciseModifier
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        smoothness = try c.decodeIfPresent(Smoothness.self, forKey: .smoothness) ?? smoothness
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? reverse
        precision = try c.decodeIfPresent(Bool.self, forKey: .precision) ?? precision
        nativeZoom = try c.decodeIfPresent(Bool.self, forKey: .nativeZoom) ?? nativeZoom
        simulateTrackpad = try c.decodeIfPresent(Bool.self, forKey: .simulateTrackpad) ?? simulateTrackpad
        horizontalModifier = try c.decodeIfPresent(Modifier.self, forKey: .horizontalModifier) ?? horizontalModifier
        zoomModifier = try c.decodeIfPresent(Modifier.self, forKey: .zoomModifier) ?? zoomModifier
        fastModifier = try c.decodeIfPresent(Modifier.self, forKey: .fastModifier) ?? fastModifier
        preciseModifier = try c.decodeIfPresent(Modifier.self, forKey: .preciseModifier) ?? preciseModifier
    }
    public func validated() -> Self {
        var value = self
        value.speed = speed.isFinite ? min(4, max(0.1, speed)) : 1
        return value
    }
}

public enum Trigger: String, Codable, CaseIterable, Identifiable {
    case click, doubleClick, tripleClick, hold, dragUp, dragDown, dragLeft, dragRight, scrollUp, scrollDown, pan
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .click: return "Click"; case .doubleClick: return "Double Click"; case .tripleClick: return "Triple Click"
        case .hold: return "Hold"; case .dragUp: return "Drag Up"; case .dragDown: return "Drag Down"
        case .dragLeft: return "Drag Left"; case .dragRight: return "Drag Right"
        case .scrollUp: return "Hold + Scroll Up"; case .scrollDown: return "Hold + Scroll Down"
        case .pan: return "Hold + 360° Scrolling"
        }
    }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, back, forward, missionControl, appExpose, desktop, applications, spaceLeft, spaceRight
    case lookup, quickLook, zoomIn, zoomOut, resetZoom, copy, paste, undo, redo, closeTab, newTab, nextTab, previousTab
    case middleClick, leftClick, rightClick, shortcut, openApplication, togglePause
    case nativeZoomIn, nativeZoomOut, smartZoom, swipeLeft, swipeRight
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "Disable Button"; case .back: return "Back"; case .forward: return "Forward"
        case .missionControl: return "Mission Control"; case .appExpose: return "App Exposé"
        case .desktop: return "Show Desktop"; case .applications: return "Applications / Launchpad"
        case .spaceLeft: return "Desktop to the Left"; case .spaceRight: return "Desktop to the Right"
        case .lookup: return "Look Up"; case .quickLook: return "Quick Look"
        case .zoomIn: return "Zoom In (⌘+)"; case .zoomOut: return "Zoom Out (⌘−)"; case .resetZoom: return "Reset Zoom (⌘0)"
        case .copy: return "Copy"; case .paste: return "Paste"; case .undo: return "Undo"; case .redo: return "Redo"
        case .closeTab: return "Close Tab"; case .newTab: return "New Tab"
        case .nextTab: return "Next Tab"; case .previousTab: return "Previous Tab"
        case .middleClick: return "Middle Click"; case .leftClick: return "Left Click"; case .rightClick: return "Right Click"
        case .shortcut: return "Custom Keyboard Shortcut"; case .openApplication: return "Open App"; case .togglePause: return "Pause MouseCraft"
        case .nativeZoomIn: return "Pinch: Zoom In · Experimental"
        case .nativeZoomOut: return "Pinch: Zoom Out · Experimental"
        case .smartZoom: return "Smart Zoom · Experimental"
        case .swipeLeft: return "Native Swipe Left · Experimental"
        case .swipeRight: return "Native Swipe Right · Experimental"
        }
    }
}

public struct MouseAction: Codable, Equatable {
    public var kind: ActionKind
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var applicationPath: String
    public init(_ kind: ActionKind, keyCode: UInt16 = 0, modifiers: UInt64 = Modifier.command.rawValue, applicationPath: String = "") {
        self.kind = kind; self.keyCode = keyCode; self.modifiers = modifiers; self.applicationPath = applicationPath
    }
}

public struct ButtonRule: Codable, Equatable, Identifiable {
    public var id: UUID
    /// Human numbering: 1 = left, 2 = right, 3 = wheel, 4/5 = side buttons.
    public var button: Int
    public var trigger: Trigger
    public var modifiers: UInt64
    public var action: MouseAction
    public init(button: Int = 4, trigger: Trigger = .click, modifiers: UInt64 = 0, action: MouseAction = MouseAction(.back)) {
        id = UUID(); self.button = button; self.trigger = trigger; self.modifiers = modifiers; self.action = action
    }
}

public struct AppProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleID: String
    public var bypass: Bool
    public var scroll: ScrollSettings?
    public var rules: [ButtonRule]?
    public init(name: String, bundleID: String) {
        id = UUID(); self.name = name; self.bundleID = bundleID; bypass = false
    }
}

public struct Configuration: Codable, Equatable {
    public var version = 1
    public var enabled = false
    public var scroll = ScrollSettings()
    public var buttonsEnabled = true
    public var rules = Self.threeButtonRules
    public var profiles: [AppProfile] = []
    public var lockPointer = true
    public var holdDelay = 0.4
    public var dragThreshold = 28.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case version, enabled, scroll, buttonsEnabled, rules, profiles, lockPointer, holdDelay, dragThreshold
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        scroll = try values.decode(ScrollSettings.self, forKey: .scroll)
        // Older saved settings keep their existing behavior and assignments.
        buttonsEnabled = try values.decodeIfPresent(Bool.self, forKey: .buttonsEnabled) ?? true
        rules = try values.decode([ButtonRule].self, forKey: .rules)
        profiles = try values.decode([AppProfile].self, forKey: .profiles)
        lockPointer = try values.decode(Bool.self, forKey: .lockPointer)
        holdDelay = try values.decode(Double.self, forKey: .holdDelay)
        dragThreshold = try values.decode(Double.self, forKey: .dragThreshold)
    }
    public static var threeButtonRules: [ButtonRule] {
        [ButtonRule(button: 3, action: MouseAction(.middleClick)),
         ButtonRule(button: 3, trigger: .doubleClick, action: MouseAction(.lookup)),
         ButtonRule(button: 3, trigger: .hold, action: MouseAction(.quickLook)),
         ButtonRule(button: 3, trigger: .dragUp, action: MouseAction(.missionControl)),
         ButtonRule(button: 3, trigger: .dragDown, action: MouseAction(.appExpose)),
         ButtonRule(button: 3, trigger: .dragLeft, action: MouseAction(.spaceLeft)),
         ButtonRule(button: 3, trigger: .dragRight, action: MouseAction(.spaceRight)),
         ButtonRule(button: 3, trigger: .scrollUp, action: MouseAction(.zoomIn)),
         ButtonRule(button: 3, trigger: .scrollDown, action: MouseAction(.zoomOut)),
         ButtonRule(button: 3, modifiers: Modifier.shift.rawValue, action: MouseAction(.middleClick)),
         ButtonRule(button: 3, trigger: .scrollUp, modifiers: Modifier.shift.rawValue, action: MouseAction(.desktop)),
         ButtonRule(button: 3, trigger: .scrollDown, modifiers: Modifier.shift.rawValue, action: MouseAction(.applications)),
         ButtonRule(button: 3, trigger: .pan, modifiers: Modifier.option.rawValue, action: MouseAction(.none)),
         ButtonRule(button: 3, modifiers: Modifier.control.rawValue, action: MouseAction(.resetZoom)),
         ButtonRule(button: 3, modifiers: Modifier.command.rawValue, action: MouseAction(.newTab)),
         ButtonRule(button: 3, trigger: .dragLeft, modifiers: Modifier.command.rawValue, action: MouseAction(.back)),
         ButtonRule(button: 3, trigger: .dragRight, modifiers: Modifier.command.rawValue, action: MouseAction(.forward))]
    }
    public static var defaultRules: [ButtonRule] {
        [ButtonRule(button: 4, action: MouseAction(.lookup)),
         ButtonRule(button: 4, trigger: .dragUp, action: MouseAction(.missionControl)),
         ButtonRule(button: 4, trigger: .dragDown, action: MouseAction(.appExpose)),
         ButtonRule(button: 4, trigger: .dragLeft, action: MouseAction(.spaceLeft)),
         ButtonRule(button: 4, trigger: .dragRight, action: MouseAction(.spaceRight)),
         ButtonRule(button: 4, trigger: .scrollUp, action: MouseAction(.desktop)),
         ButtonRule(button: 4, trigger: .scrollDown, action: MouseAction(.applications)),
         ButtonRule(button: 5, action: MouseAction(.back)),
         ButtonRule(button: 5, trigger: .dragLeft, action: MouseAction(.back)),
         ButtonRule(button: 5, trigger: .dragRight, action: MouseAction(.forward)),
         ButtonRule(button: 5, trigger: .scrollUp, action: MouseAction(.zoomIn)),
         ButtonRule(button: 5, trigger: .scrollDown, action: MouseAction(.zoomOut))]
    }
    public func effective(for bundleID: String) -> Self {
        var result = self
        if let profile = profiles.first(where: { $0.bundleID == bundleID }) {
            if profile.bypass { result.enabled = false }
            if let scroll = profile.scroll { result.scroll = scroll }
            if let rules = profile.rules { result.rules = rules }
        }
        return result
    }
    public func validated() throws -> Self {
        guard version == 1 else { throw ConfigurationError.unsupportedVersion }
        var result = self
        result.scroll = scroll.validated()
        result.holdDelay = holdDelay.isFinite ? min(2, max(0.15, holdDelay)) : 0.4
        result.dragThreshold = dragThreshold.isFinite ? min(200, max(8, dragThreshold)) : 28
        guard profiles.count <= 200, rules.count <= 500 else { throw ConfigurationError.tooManyRules }
        try Self.validateRules(rules)
        guard Set(profiles.map(\.bundleID)).count == profiles.count,
              Set(profiles.map(\.id)).count == profiles.count else { throw ConfigurationError.duplicateProfile }
        for index in result.profiles.indices {
            guard !result.profiles[index].bundleID.isEmpty else { throw ConfigurationError.invalidProfile }
            result.profiles[index].scroll = result.profiles[index].scroll?.validated()
            if let rules = result.profiles[index].rules { try Self.validateRules(rules) }
        }
        return result
    }
    private static func validateRules(_ rules: [ButtonRule]) throws {
        guard rules.count <= 500, Set(rules.map(\.id)).count == rules.count else { throw ConfigurationError.tooManyRules }
        var signatures = Set<String>()
        for rule in rules {
            guard (3...32).contains(rule.button), rule.action.keyCode <= 127,
                  rule.modifiers & ~Modifier.mask == 0, rule.action.modifiers & ~Modifier.mask == 0 else { throw ConfigurationError.invalidRule }
            let signature = "\(rule.button):\(rule.trigger.rawValue):\(rule.modifiers)"
            guard signatures.insert(signature).inserted else { throw ConfigurationError.duplicateRule }
            if rule.action.kind == .openApplication {
                guard rule.action.applicationPath.hasPrefix("/"), rule.action.applicationPath.hasSuffix(".app") else { throw ConfigurationError.invalidRule }
            }
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case unsupportedVersion, tooManyRules, duplicateProfile, invalidProfile, invalidRule, duplicateRule
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This settings version is not supported."
        case .tooManyRules: return "Too many rules or duplicate identifiers."
        case .duplicateProfile: return "Duplicate app profiles."
        case .invalidProfile: return "Enter the app's bundle ID."
        case .invalidRule: return "Invalid button, key, modifiers, or app path."
        case .duplicateRule: return "An assignment already exists for this button, gesture, and modifiers."
        }
    }
}
