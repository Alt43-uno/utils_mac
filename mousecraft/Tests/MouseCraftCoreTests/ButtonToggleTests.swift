import Foundation
import Testing
@testable import MouseCraftCore

@Suite struct ButtonToggleTests {
    @Test func disabledButtonsLeaveMiddleDragAndClicksUntouched() {
        var config = Configuration(); config.buttonsEnabled = false
        for flags in [UInt64(0), Modifier.shift.rawValue, Modifier.option.rawValue, Modifier.command.rawValue] {
            var router = GestureRouter()
            let down = router.down(button: 3, flags: flags, time: 0, configuration: config, doubleClickInterval: 0.3)
            #expect(!down.consumed && down.effects.isEmpty)
            let drag = router.move(dx: 120, dy: 50)
            #expect(!drag.consumed && drag.effects.isEmpty)
            #expect(router.tick(time: 1).isEmpty)
            #expect(!router.scroll(y: 20).consumed)
            #expect(!router.up(button: 3, time: 2, doubleClickInterval: 0.3).consumed)
            #expect(!router.active)
        }
    }
    @Test func disablingButtonsDoesNotDisableWheelScrolling() {
        var config = Configuration(); config.buttonsEnabled = false
        config.scroll.reverse = false; config.scroll.speed = 2
        #expect(ScrollTransform.apply(ScrollVector(y: 10), continuous: false, flags: 0, settings: config.scroll) == .scroll(ScrollVector(y: 20)))
    }
    @Test func profileRulesCannotBypassTheGlobalButtonSwitch() {
        var config = Configuration(); config.buttonsEnabled = false
        var profile = AppProfile(name: "Browser", bundleID: "example.browser")
        profile.rules = [ButtonRule(button: 3, trigger: .pan)]
        config.profiles = [profile]
        var router = GestureRouter()
        #expect(!router.down(button: 3, flags: 0, time: 0, configuration: config.effective(for: profile.bundleID), doubleClickInterval: 0.3).consumed)
        #expect(!router.move(dx: 100, dy: 20).consumed)
    }
    @Test func savedSwitchPreservesAssignmentsAndCanBeReenabled() throws {
        var config = Configuration(); config.buttonsEnabled = false
        var restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)).validated()
        #expect(!restored.buttonsEnabled)
        #expect(restored.rules == config.rules)
        restored.buttonsEnabled = true
        var router = GestureRouter()
        #expect(router.down(button: 3, flags: 0, time: 0, configuration: restored, doubleClickInterval: 0.3).consumed)
        #expect(router.move(dx: 100, dy: 0).effects == [.action(MouseAction(.spaceRight))])
    }
    @Test func oldSettingsDecodeWithoutLosingAssignments() throws {
        let original = Configuration()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "buttonsEnabled")
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.buttonsEnabled)
        #expect(restored.rules == original.rules)
    }
    @Test func cancellingAnActiveGestureDropsDelayedActions() {
        var router = GestureRouter(); let config = Configuration()
        _ = router.down(button: 3, flags: 0, time: 0, configuration: config, doubleClickInterval: 0.3)
        _ = router.up(button: 3, time: 0.05, doubleClickInterval: 0.3)
        #expect(router.active)
        router.reset()
        #expect(router.tick(time: 1).isEmpty)
        #expect(!router.active)
    }
}
