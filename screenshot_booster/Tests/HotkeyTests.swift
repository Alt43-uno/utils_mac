import AppKit

@MainActor
func runHotkeyTests(_ runner: inout TestRunner) {
    runner.section("Recognition shortcut settings")
    let suite = "com.screenshotbooster.tests.hotkeys"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    // Simulate an existing installation with a customized area binding and an
    // intentionally disabled window binding, before OCR shortcuts existed.
    let legacy: [String: KeyCombo] = [CaptureMode.area.rawValue: .captureFullScreen]
    defaults.set(try! JSONEncoder().encode(legacy), forKey: "hotkeys")
    let settings = SettingsStore(defaults: defaults)
    runner.expect(settings.recognitionHotkey?.displayString == "⌃⇧4",
                  "existing installations receive Control-Shift-4 for combined text and QR recognition")
    runner.expect(settings.hotkeys[.area] == .captureFullScreen && settings.hotkeys[.window] == nil,
                  "adding OCR preserves existing capture bindings and disabled shortcuts")

    settings.setRecognitionHotkey(nil)
    runner.expect(SettingsStore(defaults: defaults).recognitionHotkey == nil,
                  "disabling recognition survives a settings reload")
    settings.setRecognitionHotkey(.captureFullScreen)
    runner.expect(settings.hotkeys[.area] == nil,
                  "assigning a used shortcut to recognition clears the old capture binding")
    runner.expect(SettingsStore(defaults: defaults).recognitionHotkey == .captureFullScreen,
                  "custom recognition bindings survive a settings reload")
    settings.setHotkey(.captureFullScreen, for: .window)
    runner.expect(settings.recognitionHotkey == nil && settings.hotkeys[.window] == .captureFullScreen,
                  "assigning the recognition shortcut to capture keeps bindings unique")
    settings.resetHotkeysToDefaults()
    let restored = SettingsStore(defaults: defaults)
    runner.expect(restored.recognitionHotkey == .recognizeContent && restored.hotkeys.count == 3,
                  "reset restores all four shortcuts and persists them")
}
