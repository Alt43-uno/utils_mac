import AppKit
import Combine

/// User preferences, backed by `UserDefaults`.
///
/// Every property publishes changes so SwiftUI settings controls and the runtime
/// components (hotkeys, thumbnail panel) stay in sync without extra plumbing.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let hotkeys = "hotkeys"
        static let saveDirectory = "saveDirectoryPath"
        static let copyToClipboard = "copyToClipboardAfterCapture"
        static let autoSaveToDisk = "autoSaveToDisk"
        static let imageFormat = "imageFormat"
        static let jpegQuality = "jpegQuality"
        static let playsSound = "playsCaptureSound"
        static let panelCorner = "panelCorner"
        static let panelScreenPolicy = "panelScreenPolicy"
        static let thumbnailWidth = "thumbnailWidth"
        static let restorePins = "restorePinnedScreenshots"
        static let excludeOwnWindows = "excludeOwnWindowsFromCapture"
        static let showsCursor = "showsCursorInCaptures"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
        static let hasRequestedScreenPermission = "hasRequestedScreenPermission"
    }

    private let defaults: UserDefaults

    // MARK: - Stored settings

    @Published var hotkeys: [CaptureMode: KeyCombo] {
        didSet { persistHotkeys() }
    }

    @Published var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: Key.saveDirectory) }
    }

    @Published var copyToClipboardAfterCapture: Bool {
        didSet { defaults.set(copyToClipboardAfterCapture, forKey: Key.copyToClipboard) }
    }

    @Published var autoSaveToDisk: Bool {
        didSet { defaults.set(autoSaveToDisk, forKey: Key.autoSaveToDisk) }
    }

    @Published var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) }
    }

    @Published var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: Key.jpegQuality) }
    }

    @Published var playsCaptureSound: Bool {
        didSet { defaults.set(playsCaptureSound, forKey: Key.playsSound) }
    }

    @Published var panelCorner: PanelCorner {
        didSet { defaults.set(panelCorner.rawValue, forKey: Key.panelCorner) }
    }

    @Published var panelScreenPolicy: PanelScreenPolicy {
        didSet { defaults.set(panelScreenPolicy.rawValue, forKey: Key.panelScreenPolicy) }
    }

    /// Width of a thumbnail card in points.
    @Published var thumbnailWidth: Double {
        didSet { defaults.set(thumbnailWidth, forKey: Key.thumbnailWidth) }
    }

    @Published var restorePinnedScreenshots: Bool {
        didSet { defaults.set(restorePinnedScreenshots, forKey: Key.restorePins) }
    }

    @Published var excludeOwnWindowsFromCapture: Bool {
        didSet { defaults.set(excludeOwnWindowsFromCapture, forKey: Key.excludeOwnWindows) }
    }

    @Published var showsCursorInCaptures: Bool {
        didSet { defaults.set(showsCursorInCaptures, forKey: Key.showsCursor) }
    }

    var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstRun) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstRun) }
    }

    /// Whether the system Screen Recording prompt has already been triggered
    /// once — macOS only shows it the first time.
    var hasRequestedScreenPermission: Bool {
        get { defaults.bool(forKey: Key.hasRequestedScreenPermission) }
        set { defaults.set(newValue, forKey: Key.hasRequestedScreenPermission) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHotkeys = defaults.data(forKey: Key.hotkeys)
            .flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) }
        var combos: [CaptureMode: KeyCombo] = [
            .area: .captureArea,
            .window: .captureWindow,
            .fullScreen: .captureFullScreen
        ]
        if let storedHotkeys {
            // A stored entry may be intentionally absent, meaning "no shortcut".
            combos = [:]
            for (rawMode, combo) in storedHotkeys {
                if let mode = CaptureMode(rawValue: rawMode) { combos[mode] = combo }
            }
        }
        self.hotkeys = combos

        if let path = defaults.string(forKey: Key.saveDirectory), !path.isEmpty {
            self.saveDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            self.saveDirectory = AppPaths.defaultSaveDirectory
        }

        self.copyToClipboardAfterCapture = defaults.object(forKey: Key.copyToClipboard) as? Bool ?? true
        self.autoSaveToDisk = defaults.object(forKey: Key.autoSaveToDisk) as? Bool ?? false
        self.imageFormat = defaults.string(forKey: Key.imageFormat).flatMap(ImageFormat.init(rawValue:)) ?? .png
        self.jpegQuality = defaults.object(forKey: Key.jpegQuality) as? Double ?? 0.9
        self.playsCaptureSound = defaults.object(forKey: Key.playsSound) as? Bool ?? true
        self.panelCorner = defaults.string(forKey: Key.panelCorner).flatMap(PanelCorner.init(rawValue:)) ?? .bottomLeft
        self.panelScreenPolicy = defaults.string(forKey: Key.panelScreenPolicy)
            .flatMap(PanelScreenPolicy.init(rawValue:)) ?? .screenWithMouse
        self.thumbnailWidth = defaults.object(forKey: Key.thumbnailWidth) as? Double ?? 172
        self.restorePinnedScreenshots = defaults.object(forKey: Key.restorePins) as? Bool ?? true
        self.excludeOwnWindowsFromCapture = defaults.object(forKey: Key.excludeOwnWindows) as? Bool ?? true
        self.showsCursorInCaptures = defaults.object(forKey: Key.showsCursor) as? Bool ?? false
    }

    // MARK: - Helpers

    private func persistHotkeys() {
        let encodable = Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: Key.hotkeys)
    }

    func setHotkey(_ combo: KeyCombo?, for mode: CaptureMode) {
        var updated = hotkeys
        // Keep shortcuts unique: clear the combo from any other action first.
        if let combo {
            for (key, value) in updated where value == combo && key != mode {
                updated.removeValue(forKey: key)
            }
            updated[mode] = combo
        } else {
            updated.removeValue(forKey: mode)
        }
        hotkeys = updated
    }

    func resetHotkeysToDefaults() {
        hotkeys = [.area: .captureArea, .window: .captureWindow, .fullScreen: .captureFullScreen]
    }

    /// Format + quality used for exports, as a single value.
    var exportQuality: Double {
        imageFormat == .jpeg ? jpegQuality : 1.0
    }
}
