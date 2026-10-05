import Foundation

public enum ConnectionReadiness: Equatable {
    case disabled, needsAccessibility, conflictingDriver, bypassedApplication, ready

    public static func evaluate(requested: Bool, accessibility: Bool, conflictingDriver: Bool, bypassedApplication: Bool) -> Self {
        guard requested else { return .disabled }
        guard accessibility else { return .needsAccessibility }
        guard !conflictingDriver else { return .conflictingDriver }
        guard !bypassedApplication else { return .bypassedApplication }
        return .ready
    }
}
