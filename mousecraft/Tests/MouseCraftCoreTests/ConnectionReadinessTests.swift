import Testing
import MouseCraftCore

@Suite struct ConnectionReadinessTests {
    @Test func enabledSwitchCannotClaimReadyWithoutAccessibility() {
        #expect(ConnectionReadiness.evaluate(requested: true, accessibility: false, conflictingDriver: false, bypassedApplication: false) == .needsAccessibility)
    }
    @Test func grantAllowsConnectionWithoutChangingRequestedState() {
        #expect(ConnectionReadiness.evaluate(requested: true, accessibility: true, conflictingDriver: false, bypassedApplication: false) == .ready)
    }
    @Test func pausedAppDoesNotPromptForPermissions() {
        #expect(ConnectionReadiness.evaluate(requested: false, accessibility: false, conflictingDriver: false, bypassedApplication: false) == .disabled)
    }
    @Test func conflictsAndProfileBypassBlockProcessing() {
        #expect(ConnectionReadiness.evaluate(requested: true, accessibility: true, conflictingDriver: true, bypassedApplication: false) == .conflictingDriver)
        #expect(ConnectionReadiness.evaluate(requested: true, accessibility: true, conflictingDriver: false, bypassedApplication: true) == .bypassedApplication)
    }
}
