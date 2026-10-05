import Foundation

public enum GestureEffect: Equatable {
    case action(MouseAction)
    case replayClick(button: Int, count: Int, modifiers: UInt64)
    case pan(ScrollVector)
}

public struct GestureResult {
    public var consumed: Bool
    public var effects: [GestureEffect]
    public init(consumed: Bool = false, effects: [GestureEffect] = []) { self.consumed = consumed; self.effects = effects }
}

public struct GestureRouter {
    private struct Press {
        var started: Double
        var delta = ScrollVector()
        var used = false
        var rules: [ButtonRule]
        var modifiers: UInt64
        var holdDelay: Double
        var threshold: Double
    }
    private struct PendingClick {
        var deadline: Double
        var count: Int
        var rules: [ButtonRule]
        var modifiers: UInt64
    }
    private var presses: [Int: Press] = [:]
    private var pending: [Int: PendingClick] = [:]
    public var active: Bool { !presses.isEmpty || !pending.isEmpty }
    public var pressedButtons: Set<Int> { Set(presses.keys) }
    public init() {}
    public mutating func reset() { presses.removeAll(); pending.removeAll() }
    public mutating func down(button: Int, flags: UInt64, time: Double, configuration: Configuration, doubleClickInterval: Double) -> GestureResult {
        guard configuration.buttonsEnabled else { return GestureResult() }
        let relevant = configuration.rules.filter { $0.button == button && (flags & $0.modifiers) == $0.modifiers }
        guard !relevant.isEmpty else { return GestureResult() }
        let specificity = relevant.map { $0.modifiers.nonzeroBitCount }.max() ?? 0
        let selected = relevant.filter { $0.modifiers.nonzeroBitCount == specificity }
        var effects: [GestureEffect] = []
        if let click = pending[button], time >= click.deadline || click.modifiers != flags & Modifier.mask || click.rules != selected {
            effects.append(clickEffect(button: button, count: click.count, rules: click.rules, flags: click.modifiers))
            pending.removeValue(forKey: button)
        }
        presses[button] = Press(started: time, rules: selected, modifiers: flags & Modifier.mask,
                                holdDelay: configuration.holdDelay, threshold: configuration.dragThreshold)
        // A second press must not race the deadline of the previous release.
        if pending[button] != nil { pending[button]?.deadline = time + max(0.1, doubleClickInterval) }
        return GestureResult(consumed: true, effects: effects)
    }
    public mutating func up(button: Int, time: Double, doubleClickInterval: Double) -> GestureResult {
        guard let press = presses.removeValue(forKey: button) else { return GestureResult() }
        guard !press.used else { pending.removeValue(forKey: button); return GestureResult(consumed: true) }
        let count = (pending.removeValue(forKey: button)?.count ?? 0) + 1
        let maxCount = press.rules.contains(where: { $0.trigger == .tripleClick }) ? 3 : press.rules.contains(where: { $0.trigger == .doubleClick }) ? 2 : 1
        if count < maxCount {
            pending[button] = PendingClick(deadline: time + doubleClickInterval, count: count, rules: press.rules, modifiers: press.modifiers)
            return GestureResult(consumed: true)
        }
        return GestureResult(consumed: true, effects: [clickEffect(button: button, count: count, rules: press.rules, flags: press.modifiers)])
    }
    private func clickEffect(button: Int, count: Int, rules: [ButtonRule], flags: UInt64) -> GestureEffect {
        let trigger: Trigger = count >= 3 ? .tripleClick : count == 2 ? .doubleClick : .click
        if let rule = rules.first(where: { $0.trigger == trigger }) { return .action(rule.action) }
        return .replayClick(button: button, count: count, modifiers: flags)
    }
    public mutating func move(dx: Double, dy: Double) -> GestureResult {
        guard let button = presses.keys.sorted().last, var press = presses[button] else { return GestureResult() }
        if press.rules.contains(where: { $0.trigger == .pan }) {
            press.used = true; presses[button] = press
            return GestureResult(consumed: true, effects: [.pan(ScrollVector(x: -dx, y: -dy))])
        }
        let hasDrag = press.rules.contains { [.dragUp, .dragDown, .dragLeft, .dragRight].contains($0.trigger) }
        guard hasDrag else { return GestureResult() }
        if press.used { return GestureResult(consumed: true) }
        press.delta.x += dx; press.delta.y += dy
        var effects: [GestureEffect] = []
        if press.delta.magnitude >= press.threshold {
            let trigger: Trigger = abs(press.delta.x) > abs(press.delta.y)
                ? (press.delta.x < 0 ? .dragLeft : .dragRight) : (press.delta.y < 0 ? .dragUp : .dragDown)
            if let rule = press.rules.first(where: { $0.trigger == trigger }) { effects = [.action(rule.action)]; press.used = true }
        }
        presses[button] = press
        return GestureResult(consumed: true, effects: effects)
    }
    public mutating func scroll(y: Double) -> GestureResult {
        guard y != 0, let button = presses.keys.sorted().last, var press = presses[button] else { return GestureResult() }
        let trigger: Trigger = y > 0 ? .scrollUp : .scrollDown
        guard let rule = press.rules.first(where: { $0.trigger == trigger }) else { return GestureResult() }
        let repeatable: Set<ActionKind> = [.zoomIn, .zoomOut, .nativeZoomIn, .nativeZoomOut, .back, .forward, .nextTab, .previousTab]
        let effects: [GestureEffect] = !press.used || repeatable.contains(rule.action.kind) ? [.action(rule.action)] : []
        press.used = true; presses[button] = press
        return GestureResult(consumed: true, effects: effects)
    }
    public mutating func tick(time: Double) -> [GestureEffect] {
        var effects: [GestureEffect] = []
        for button in pending.keys.sorted() {
            guard let click = pending[button], time >= click.deadline, presses[button] == nil else { continue }
            effects.append(clickEffect(button: button, count: click.count, rules: click.rules, flags: click.modifiers))
            pending.removeValue(forKey: button)
        }
        for button in presses.keys.sorted() {
            guard var press = presses[button], !press.used, time - press.started >= press.holdDelay,
                  let rule = press.rules.first(where: { $0.trigger == .hold }) else { continue }
            press.used = true; presses[button] = press; effects.append(.action(rule.action))
        }
        return effects
    }
}
