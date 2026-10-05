import AppKit

/// Undocumented Quartz gesture ABI, isolated from the stable input pipeline.
/// Numeric protocol fields are checked by converting to AppKit events before use.
/// These events are built here, never posted: the caller owns delivery and permissions.
public enum NativeGestureEvents {
    public enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    private static func event(subtype: Int64, phase: Phase? = nil) -> CGEvent? {
        guard let event = CGEvent(source: nil), let type = CGEventType(rawValue: 29),
              let subtypeField = CGEventField(rawValue: 110), let phaseField = CGEventField(rawValue: 132) else { return nil }
        event.type = type
        event.flags = []
        event.setIntegerValueField(subtypeField, value: subtype)
        if let phase { event.setIntegerValueField(phaseField, value: phase.rawValue) }
        return event
    }
    public static func magnify(_ amount: Double, phase: Phase) -> CGEvent? {
        guard amount.isFinite, let event = event(subtype: 8, phase: phase), let field = CGEventField(rawValue: 113) else { return nil }
        event.setDoubleValueField(field, value: min(0.3, max(-0.3, amount)))
        guard NSEvent(cgEvent: event)?.type == .magnify else { return nil }
        return event
    }
    public static func smartZoom() -> CGEvent? {
        guard let event = event(subtype: 22), NSEvent(cgEvent: event)?.type == .smartMagnify else { return nil }
        return event
    }
    public static func swipe(left: Bool, phase: Phase) -> CGEvent? {
        guard let event = event(subtype: 16, phase: phase), let field = CGEventField(rawValue: 115) else { return nil }
        event.setIntegerValueField(field, value: phase == .ended ? 0 : left ? 4 : 8)
        guard NSEvent(cgEvent: event)?.type == .swipe else { return nil }
        return event
    }
}
