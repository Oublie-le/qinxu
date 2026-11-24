import Foundation
import Testing

// Small ordinary assertion helpers keep parameterized score fixtures readable.
// Failures are recorded in Swift Testing; no custom runner or swallowed failures.
private func failure(_ message: String, file: StaticString, line: UInt) {
    Issue.record(Comment(rawValue: message), sourceLocation: SourceLocation(
        fileID: "PianoCoreTests/" + URL(fileURLWithPath: String(describing: file)).lastPathComponent,
        filePath: String(describing: file), line: Int(line), column: 1))
}

func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
                               _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        if a != b { failure("Expected \(a) == \(b). \(message)", file: file, line: line) }
    } catch { failure("Unexpected error: \(error). \(message)", file: file, line: line) }
}
func expectEqual(_ lhs: @autoclosure () throws -> Double, _ rhs: @autoclosure () throws -> Double,
                 accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        if !a.isFinite || !b.isFinite || abs(a - b) > accuracy {
            failure("Expected \(a) ≈ \(b), tolerance \(accuracy). \(message)", file: file, line: line)
        }
    } catch { failure("Unexpected error: \(error). \(message)", file: file, line: line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { failure("Expected true. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func expectFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { failure("Expected false. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func expectNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { failure("Expected nil. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func expectNotNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() == nil { failure("Expected a value. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); failure("Expected an error. \(message)", file: file, line: line) }
    catch { handler(error) }
}
func expectNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch { failure("Unexpected error: \(error). \(message)", file: file, line: line) }
}
func requireValue<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let result = try value() else {
        failure("Required value was nil. \(message)", file: file, line: line)
        throw NSError(domain: "PianoCoreTests", code: 1)
    }
    return result
}
func failTest(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    failure(message, file: file, line: line)
}
