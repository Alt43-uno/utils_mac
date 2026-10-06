import Testing
import Foundation

private func location(_ file: String, _ id: String, _ line: Int) -> SourceLocation { SourceLocation(fileID: id, filePath: file, line: line, column: 1) }
func recordFailure(_ message: String, file: String = #filePath, id: String = #fileID, line: Int = #line) {
    Issue.record(Comment(rawValue: message), sourceLocation: location(file, id, line))
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #filePath, id: String = #fileID, line: Int = #line) {
    if actual != expected { recordFailure("\(message) Expected \(expected), got \(actual)", file: file, id: id, line: line) }
}
func checkEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: String = #filePath, id: String = #fileID, line: Int = #line) {
    if abs(actual - expected) > accuracy { recordFailure("Expected \(expected) ± \(accuracy), got \(actual)", file: file, id: id, line: line) }
}
func checkTrue(_ value: Bool, _ message: String = "", file: String = #filePath, id: String = #fileID, line: Int = #line) {
    if !value { recordFailure("Expected true. " + message, file: file, id: id, line: line) }
}
func checkFalse(_ value: Bool, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(!value, file: file, id: id, line: line) }
func checkNil<T>(_ value: T?, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(value == nil, file: file, id: id, line: line) }
func checkNotNil<T>(_ value: T?, _ message: String = "", file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(value != nil, message, file: file, id: id, line: line) }
func checkLess<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(a < b, "\(a) < \(b)", file: file, id: id, line: line) }
func checkGreater<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(a > b, "\(a) > \(b)", file: file, id: id, line: line) }
func checkLessOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(a <= b, "\(a) <= \(b)", file: file, id: id, line: line) }
func checkGreaterOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, id: String = #fileID, line: Int = #line) { checkTrue(a >= b, "\(a) >= \(b)", file: file, id: id, line: line) }
func checkThrows<T>(_ body: @autoclosure () throws -> T, file: String = #filePath, id: String = #fileID, line: Int = #line, handler: (Error) -> Void = { _ in }) {
    do { _ = try body(); recordFailure("Expected an error", file: file, id: id, line: line) } catch { handler(error) }
}
func checkNoThrow<T>(_ body: @autoclosure () throws -> T, file: String = #filePath, id: String = #fileID, line: Int = #line) {
    do { _ = try body() } catch { recordFailure("Unexpected error: \(error)", file: file, id: id, line: line) }
}
