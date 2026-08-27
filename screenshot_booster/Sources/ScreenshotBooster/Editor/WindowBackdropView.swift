import AppKit
import SwiftUI

/// Blurs whatever is behind the window.
///
/// Liquid Glass samples content *inside* the window, so it cannot blur other
/// applications showing through a transparent window — that is what
/// `NSVisualEffectView` in `.behindWindow` mode is for. The glass pills then sit
/// on top of this.
struct WindowBackdropView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        // The editor is a light-on-dark surface regardless of system appearance,
        // so the screenshot is judged against a neutral ground.
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
