import Foundation
import Testing
@testable import MouseCraftCore

@Suite struct CoreTests {
    @Test func testContinuousInputIsUntouchedIncludingZoomModifier() {
        #expect((ScrollTransform.apply(ScrollVector(y: 20), continuous: true, flags: Modifier.command.rawValue, settings: ScrollSettings())) == (.passthrough))
    }
    @Test func testDisabledScrollIsUntouched() {
        var s = ScrollSettings(); s.enabled = false
        #expect((ScrollTransform.apply(ScrollVector(y: 20), continuous: false, flags: 0, settings: s)) == (.passthrough))
    }
    @Test func testReverseSpeedAndModifiersCompose() {
        var s = ScrollSettings(); s.speed = 2
        let flags = Modifier.shift.rawValue | Modifier.control.rawValue | Modifier.option.rawValue
        #expect((ScrollTransform.apply(ScrollVector(y: 10), continuous: false, flags: flags, settings: s)) == (.scroll(ScrollVector(x: -15))))
    }
    @Test func testZoomTakesPriorityAndFollowsDirection() {
        let s = ScrollSettings()
        #expect((ScrollTransform.apply(ScrollVector(y: 10), continuous: false, flags: Modifier.command.rawValue | Modifier.shift.rawValue, settings: s)) == (.zoom(-1)))
    }
    @Test func testNoneModifierDoesNotMatch() {
        var s = ScrollSettings(); s.horizontalModifier = .none; s.reverse = false
        #expect((ScrollTransform.apply(ScrollVector(y: 10), continuous: false, flags: 0, settings: s)) == (.scroll(ScrollVector(y: 10))))
    }
    @Test func testPrecisionForSlowWheel() {
        var s = ScrollSettings(); s.reverse = false; s.precision = true
        #expect((ScrollTransform.apply(ScrollVector(y: 10), continuous: false, flags: 0, settings: s)) == (.scroll(ScrollVector(y: 4))))
    }
    @Test func testSmoothingConservesDistanceAtDifferentRefreshRates() {
        for hz in [60.0, 120, 144] {
            var smoother = ScrollSmoother(); smoother.add(ScrollVector(x: 57, y: 240))
            var x = 0.0, y = 0.0
            for _ in 0..<Int(hz * 3) { let step = smoother.step(dt: 1 / hz, timeConstant: 0.11); x += step.x; y += step.y }
            #expect(!(smoother.active))
            #expect(abs((x + smoother.fractional.x) - (57)) <= 0.001)
            #expect(abs((y + smoother.fractional.y) - (240)) <= 0.001)
        }
    }
    @Test func testReversalStopsOldMomentumImmediately() {
        var smoother = ScrollSmoother(); smoother.add(ScrollVector(y: 100)); smoother.add(ScrollVector(y: -10))
        #expect((smoother.remaining.y) == (-10)); #expect((smoother.step(dt: 0.016, timeConstant: 0.055).y) < (0))
    }
    @Test func testFractionalWheelDistanceAccumulates() {
        var smoother = ScrollSmoother(); var distance = 0.0
        for _ in 0..<10 { smoother.add(ScrollVector(y: 0.25)); distance += smoother.step(dt: 0.016, timeConstant: 0).y }
        #expect((distance) == (2)); #expect(abs((smoother.fractional.y) - (0.5)) <= 0.001)
    }
    @Test func testUnmappedButtonPassesThrough() {
        var router = GestureRouter()
        #expect(!(router.down(button: 6, flags: 0, time: 0, configuration: Configuration(), doubleClickInterval: 0.3).consumed))
    }
    @Test func testClickMappingFiresOnRelease() {
        var router = GestureRouter(); var config = Configuration(); config.rules = [ButtonRule(action: MouseAction(.back))]
        #expect(router.down(button: 4, flags: 0, time: 0, configuration: config, doubleClickInterval: 0.3).consumed)
        #expect((router.up(button: 4, time: 0.1, doubleClickInterval: 0.3).effects) == ([.action(MouseAction(.back))]))
        #expect(!(router.active))
    }
    @Test func testDoubleClickDoesNotAlsoFireSingleClick() {
        var router = GestureRouter(); var c = Configuration()
        c.rules = [ButtonRule(action: MouseAction(.back)), ButtonRule(trigger: .doubleClick, action: MouseAction(.forward))]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect(router.up(button: 4, time: 0.05, doubleClickInterval: 0.3).effects.isEmpty)
        _ = router.down(button: 4, flags: 0, time: 0.15, configuration: c, doubleClickInterval: 0.3)
        #expect((router.up(button: 4, time: 0.2, doubleClickInterval: 0.3).effects) == ([.action(MouseAction(.forward))]))
        #expect(router.tick(time: 1).isEmpty)
    }
    @Test func testSingleClickWaitsOnlyWhenDoubleMappingExists() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(action: MouseAction(.back)), ButtonRule(trigger: .doubleClick)]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        _ = router.up(button: 4, time: 0.1, doubleClickInterval: 0.3)
        #expect(router.tick(time: 0.2).isEmpty)
        #expect((router.tick(time: 0.5)) == ([.action(MouseAction(.back))]))
    }
    @Test func testTripleClick() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(trigger: .tripleClick, action: MouseAction(.desktop))]
        for i in 0..<3 {
            let time = Double(i) * 0.1
            _ = router.down(button: 4, flags: 0, time: time, configuration: c, doubleClickInterval: 0.3)
            let result = router.up(button: 4, time: time + 0.02, doubleClickInterval: 0.3)
            if i < 2 { #expect(result.effects.isEmpty) } else { #expect((result.effects) == ([.action(MouseAction(.desktop))])) }
        }
    }
    @Test func testHoldSuppressesReleaseClickAndOnlyFiresOnce() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(), ButtonRule(trigger: .hold, action: MouseAction(.missionControl))]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect((router.tick(time: 0.5)) == ([.action(MouseAction(.missionControl))]))
        #expect(router.tick(time: 0.8).isEmpty)
        #expect(router.up(button: 4, time: 1, doubleClickInterval: 0.3).effects.isEmpty)
    }
    @Test func testDragThresholdAndSingleFire() {
        var router = GestureRouter(); var c = Configuration(); c.rules = Configuration.defaultRules
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect(router.move(dx: 0, dy: -10).effects.isEmpty)
        #expect((router.move(dx: 0, dy: -20).effects) == ([.action(MouseAction(.missionControl))]))
        #expect(router.move(dx: 0, dy: -100).effects.isEmpty)
        #expect(router.up(button: 4, time: 0.3, doubleClickInterval: 0.3).effects.isEmpty)
    }
    @Test func testScrollGestureSuppressesClick() {
        var router = GestureRouter(); var c = Configuration(); c.rules = Configuration.defaultRules
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect((router.scroll(y: 10).effects) == ([.action(MouseAction(.desktop))]))
        #expect(router.scroll(y: 10).effects.isEmpty)
        #expect(router.up(button: 4, time: 0.3, doubleClickInterval: 0.3).effects.isEmpty)
    }
    @Test func testPanIsContinuousAndSuppressesClick() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(trigger: .pan)]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect((router.move(dx: 8, dy: -5).effects) == ([.pan(ScrollVector(x: -8, y: 5))]))
        #expect((router.move(dx: -3, dy: 4).effects) == ([.pan(ScrollVector(x: 3, y: -4))]))
        #expect(router.up(button: 4, time: 0.3, doubleClickInterval: 0.3).effects.isEmpty)
    }
    @Test func testSpecificModifierRulesOverrideGenericRules() {
        var router = GestureRouter(); var c = Configuration()
        c.rules = [ButtonRule(action: MouseAction(.back)), ButtonRule(modifiers: Modifier.shift.rawValue, action: MouseAction(.copy))]
        _ = router.down(button: 4, flags: Modifier.shift.rawValue, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect((router.up(button: 4, time: 0.1, doubleClickInterval: 0.3).effects) == ([.action(MouseAction(.copy))]))
    }
    @Test func testGestureOnlyRuleReplaysUnmappedClickWithOriginalModifiers() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(trigger: .dragUp)]
        _ = router.down(button: 4, flags: Modifier.option.rawValue, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect((router.up(button: 4, time: 0.1, doubleClickInterval: 0.3).effects) == ([.replayClick(button: 4, count: 1, modifiers: Modifier.option.rawValue)]))
    }
    @Test func testResetCancelsPendingGestures() {
        var router = GestureRouter(); var c = Configuration(); c.rules = [ButtonRule(trigger: .hold)]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        router.reset(); #expect(!(router.active)); #expect(router.tick(time: 5).isEmpty)
    }
    @Test func testProfileOverridesAndBypass() {
        var c = Configuration(); c.enabled = true
        var p = AppProfile(name: "CAD", bundleID: "test.cad"); p.bypass = true; p.rules = []; c.profiles = [p]
        #expect(!(c.effective(for: "test.cad").enabled)); #expect((c.effective(for: "test.cad").rules) == ([]))
        #expect(c.effective(for: "other").enabled)
    }
    @Test func testRoundTripAndValidate() throws {
        let c = Configuration(); let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(c)).validated()
        #expect((c) == (restored))
    }
    @Test func testMalformedImportsCannotMapPrimaryButtonsOrDuplicateRules() {
        var c = Configuration(); c.rules = [ButtonRule(button: 1)]
        #expect(throws: (any Error).self) { try c.validated() }
        c.rules = [ButtonRule(), ButtonRule()]; #expect(throws: (any Error).self) { try c.validated() }
        c.version = 999; #expect(throws: (any Error).self) { try c.validated() }
    }
    @Test func testImportedExtremesAreClamped() throws {
        var c = Configuration(); c.scroll.speed = 1000; c.dragThreshold = -1; c.holdDelay = 100
        let valid = try c.validated(); #expect((valid.scroll.speed) == (4)); #expect((valid.dragThreshold) == (8)); #expect((valid.holdDelay) == (2))
    }
    @Test func expiredClickCannotBecomeADoubleClickWhenTimerWasDelayed() {
        var router = GestureRouter(); var c = Configuration()
        c.rules = [ButtonRule(action: MouseAction(.back)), ButtonRule(trigger: .doubleClick, action: MouseAction(.forward))]
        _ = router.down(button: 4, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        _ = router.up(button: 4, time: 0.1, doubleClickInterval: 0.3)
        let next = router.down(button: 4, flags: 0, time: 0.8, configuration: c, doubleClickInterval: 0.3)
        #expect(next.effects == [.action(MouseAction(.back))])
        #expect(router.up(button: 4, time: 0.9, doubleClickInterval: 0.3).effects.isEmpty)
        #expect(router.tick(time: 1.3) == [.action(MouseAction(.back))])
    }
    @Test func oldScrollConfigurationsReceiveNewDefaults() throws {
        let old = Data("{\"speed\":2,\"reverse\":false}".utf8)
        let value = try JSONDecoder().decode(ScrollSettings.self, from: old)
        #expect(value.speed == 2); #expect(!value.reverse); #expect(!value.nativeZoom); #expect(!value.simulateTrackpad)
    }
    @Test func threeButtonPresetIsValidAndUsesOnlyWheelButton() throws {
        let c = try Configuration().validated()
        #expect(c.rules.allSatisfy { $0.button == 3 })
        #expect(c.rules.contains { $0.trigger == .pan && $0.modifiers == Modifier.option.rawValue })
    }
    @Test func threeButtonWheelDragAndShiftScrollAreAccessibleWithoutSideButtons() {
        var router = GestureRouter(); let c = Configuration()
        _ = router.down(button: 3, flags: 0, time: 0, configuration: c, doubleClickInterval: 0.3)
        #expect(router.move(dx: 0, dy: -40).effects == [.action(MouseAction(.missionControl))])
        #expect(router.up(button: 3, time: 0.2, doubleClickInterval: 0.3).effects.isEmpty)
        _ = router.down(button: 3, flags: Modifier.shift.rawValue, time: 0.5, configuration: c, doubleClickInterval: 0.3)
        #expect(router.scroll(y: 10).effects == [.action(MouseAction(.desktop))])
        #expect(router.up(button: 3, time: 0.7, doubleClickInterval: 0.3).effects.isEmpty)
    }
}
