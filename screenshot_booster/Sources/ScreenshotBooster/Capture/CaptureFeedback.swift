import AppKit

/// Audible confirmation that a shot was taken.
enum CaptureFeedback {
    private static let sound: NSSound? = {
        // macOS does not expose its own shutter sound to third-party apps, so
        // fall back through a couple of system sounds.
        for name in ["Grab", "Tink", "Pop"] {
            if let sound = NSSound(named: NSSound.Name(name)) { return sound }
        }
        return nil
    }()

    static func playShutter() {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
