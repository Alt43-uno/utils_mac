import AppKit
import ApplicationServices
import Combine
import MouseCraftCore
import MouseCraftNative

final class MouseEngine: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var conflict = false
    @Published private(set) var status = "Выключено"
    @Published private(set) var lastInput = "Нажмите кнопку мыши после включения"
    @Published private(set) var activeApplication = ""
    @Published private(set) var receivedScrolls = 0
    @Published private(set) var processedScrolls = 0
    @Published private(set) var skippedContinuousScrolls = 0
    private let store: SettingsStore
    private let executor = ActionExecutor()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var permissionTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var router = GestureRouter()
    private var smoother = ScrollSmoother()
    private var current = Configuration()
    private var scrollFlags: UInt64 = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var scrolling = false
    private var scrollUsesPhases = false
    private var magnifying = false
    private var lastMagnify = 0.0
    private var releasing = Set<Int>()
    private var lastZoom = 0.0
    private var diagnosticsTime = 0.0

    init(store: SettingsStore) {
        self.store = store
        executor.notify = { [weak self] in self?.store.message = $0 }
        executor.pause = { [weak self] in self?.store.configuration.enabled = false }
        store.$configuration.sink { [weak self] config in
            // @Published emits before mutation; carry the new value explicitly.
            DispatchQueue.main.async { self?.apply(config) }
        }.store(in: &subscriptions)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        refresh()
    }
    func refresh() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
        conflict = NSWorkspace.shared.runningApplications.contains {
            ($0.bundleIdentifier?.hasPrefix("com.nuebling.mac-mouse-fix") ?? false) &&
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains("helper") ?? false)
        }
        apply(store.configuration)
    }
    func openAccessibility() {
        // Called only when the user presses the permission button. Register the app
        // with TCC so they do not have to locate a build folder and add it manually.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    private func apply(_ config: Configuration) {
        let front = NSWorkspace.shared.frontmostApplication
        activeApplication = front?.localizedName ?? ""
        let next = config.effective(for: front?.bundleIdentifier ?? "")
        if next != current { resetTransient(); current = next }
        let readiness = ConnectionReadiness.evaluate(requested: config.enabled, accessibility: accessibility,
                                                      conflictingDriver: conflict, bypassedApplication: !next.enabled)
        if readiness != .needsAccessibility { permissionTimer?.invalidate(); permissionTimer = nil }
        switch readiness {
        case .disabled: stop(); status = "Выключено"
        case .needsAccessibility:
            stop(); status = "Нужен доступ: Универсальный доступ"
            if permissionTimer == nil {
                let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
                timer.tolerance = 0.4; permissionTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        case .conflictingDriver: stop(); status = "Сначала выключите Mac Mouse Fix"
        case .bypassedApplication: stop(); status = "Исключение для \(activeApplication)"
        case .ready: start()
        }
    }
    private func start() {
        if let tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) { running = true; status = "Работает"; return }
        if tap != nil { stop() }
        let events: [CGEventType] = [.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .leftMouseDown, .rightMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MouseEngine>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = "Не удалось подключиться к мыши. Проверьте разрешения и перезапустите приложение."; return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true); running = true; status = "Работает"
    }
    func stop() {
        resetTransient()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; running = false
    }
    private func resetTransient() {
        releasing.formUnion(router.pressedButtons)
        router.reset(); smoother.reset(); timer?.invalidate(); timer = nil
        endScroll(); endMagnify()
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetTransient()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != EventOutput.tag else { return Unmanaged.passUnretained(event) }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
        if type == .otherMouseUp, releasing.remove(button) != nil { return nil }
        if type == .otherMouseDown { releasing.remove(button) }
        guard current.enabled else { return Unmanaged.passUnretained(event) }
        // Preserve the original down / drag / up sequence for web canvases and
        // other native middle-button behavior. Replaying a click cannot do this.
        if !current.buttonsEnabled {
            switch type {
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved:
                return Unmanaged.passUnretained(event)
            default: break
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let flags = event.flags.rawValue & Modifier.mask
        var result = GestureResult()
        switch type {
        case .otherMouseDown:
            let modifierNames = Modifier.allCases.filter { $0.matches(flags) }.map(\.title).joined(separator: " ")
            lastInput = "Кнопка \(button) · \(modifierNames.isEmpty ? "без модификаторов" : modifierNames)"
            result = router.down(button: button, flags: flags, time: now, configuration: current, doubleClickInterval: NSEvent.doubleClickInterval)
        case .otherMouseUp: result = router.up(button: button, time: now, doubleClickInterval: NSEvent.doubleClickInterval)
        case .mouseMoved, .otherMouseDragged:
            result = router.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            if !current.lockPointer { result.consumed = false }
        case .leftMouseDown, .rightMouseDown:
            smoother.reset(); endScroll(); endMagnify()
        case .scrollWheel:
            receivedScrolls += 1
            // Do not treat trackpad scroll as a wheel gesture even when a mouse button is held.
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
                skippedContinuousScrolls += 1
                if now - diagnosticsTime > 0.25 {
                    lastInput = "Непрерывная прокрутка: пропущена (трекпад / высокоточное колесо)"; diagnosticsTime = now
                }
                smoother.reset(); endScroll(); endMagnify(); return Unmanaged.passUnretained(event)
            }
            var y = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            var x = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            if y == 0 { y = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * 10 }
            if x == 0 { x = event.getDoubleValueField(.scrollWheelEventDeltaAxis2) * 10 }
            if current.buttonsEnabled { result = router.scroll(y: y) }
            if result.consumed { processedScrolls += 1 }
            if !result.consumed {
                switch ScrollTransform.apply(ScrollVector(x: x, y: y), continuous: false, flags: flags, settings: current.scroll) {
                case .passthrough: break
                case .zoom(let direction):
                    processedScrolls += 1
                    if current.scroll.nativeZoom {
                        if !magnifying, let began = NativeGestureEvents.magnify(0, phase: .began) { EventOutput.post(began); magnifying = true }
                        if let changed = NativeGestureEvents.magnify(Double(direction) * min(0.2, abs(y) / 400), phase: .changed) { EventOutput.post(changed) }
                        else { store.message = "Pinch недоступен. Отключите нативное масштабирование." }
                        lastMagnify = now; ensureTimer()
                    } else if now - lastZoom >= 0.055 { executor.perform(MouseAction(direction > 0 ? .zoomIn : .zoomOut)); lastZoom = now }
                    smoother.reset(); endScroll(); return nil
                case .scroll(let delta):
                    processedScrolls += 1
                    // Shift was consumed as an axis modifier. Keeping it on the output could rotate the axis twice.
                    let outputFlags = flags & ~(current.scroll.horizontalModifier.rawValue | current.scroll.fastModifier.rawValue | current.scroll.preciseModifier.rawValue)
                    if outputFlags != scrollFlags || scrollUsesPhases != current.scroll.simulateTrackpad { smoother.reset(); endScroll() }
                    endMagnify(); scrollUsesPhases = current.scroll.simulateTrackpad
                    scrollFlags = outputFlags
                    if current.scroll.smoothness == .off { EventOutput.scroll(delta, flags: scrollFlags) }
                    else { smoother.add(delta); ensureTimer() }
                    if now - diagnosticsTime > 0.25 { lastInput = String(format: "Колесо обрабатывается · X %.0f · Y %.0f", x, y); diagnosticsTime = now }
                    return nil
                }
            }
        default: break
        }
        execute(result.effects)
        if router.active { ensureTimer() }
        return result.consumed ? nil : Unmanaged.passUnretained(event)
    }
    private func execute(_ effects: [GestureEffect]) {
        for effect in effects {
            switch effect {
            case .action(let action): executor.perform(action)
            case .replayClick(let button, let count, let modifiers): EventOutput.click(button: button, count: count, flags: modifiers)
            case .pan(let vector):
                if !scrollUsesPhases { endScroll() }; scrollUsesPhases = true
                smoother.add(vector); scrollFlags = 0; ensureTimer()
            }
        }
    }
    private func ensureTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.001; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        execute(router.tick(time: now))
        if smoother.active {
            let delta = smoother.step(dt: now - lastTick, timeConstant: current.scroll.smoothness.timeConstant)
            if delta.magnitude > 0 {
                EventOutput.scroll(delta, flags: scrollFlags, phase: scrollUsesPhases ? (scrolling ? 2 : 1) : 0); scrolling = true
            }
        }
        lastTick = now
        if !smoother.active { endScroll() }
        if magnifying && now - lastMagnify > 0.15 { endMagnify() }
        if !smoother.active && !router.active && !magnifying { timer?.invalidate(); timer = nil }
    }
    private func endScroll() {
        if scrolling && scrollUsesPhases { EventOutput.scroll(ScrollVector(), flags: scrollFlags, phase: 4) }
        scrolling = false
    }
    private func endMagnify() {
        if magnifying, let event = NativeGestureEvents.magnify(0, phase: .ended) { EventOutput.post(event) }
        magnifying = false
    }
}
