// Minimal assertion runner for Command Line Tools installations without XCTest.
// Runs the exact same ModelTests.swift cases; the source file is not duplicated.
import Foundation

class XCTestCase {}
func XCTAssertNil<T>(_ value: T?, _ message: String = "") { precondition(value == nil, message.isEmpty ? "Expected nil" : message) }
func XCTAssertNotNil<T>(_ value: T?, _ message: String = "") { precondition(value != nil, message.isEmpty ? "Expected a value" : message) }
func XCTAssertTrue(_ value: Bool, _ message: String = "") { precondition(value, message.isEmpty ? "Expected true" : message) }
func XCTAssertFalse(_ value: Bool, _ message: String = "") { precondition(!value, message.isEmpty ? "Expected false" : message) }
func XCTAssertEqual<T: Equatable>(_ value: T, _ expected: T, _ message: String = "") { precondition(value == expected, message.isEmpty ? "Values differ: \(value) vs \(expected)" : message) }

@main
enum PortableTestRunner {
    static func main() async throws {
        let tests = ModelTests()
        tests.testHostValidationRejectsShellAndSSHOptionInjection()
        tests.testSSHArgumentsPreserveAliasDefaultsAndVerifyHostKeys()
        tests.testPortValidation()
        try tests.testNullMetricsAreUnavailableRatherThanIdle()
        try tests.testConfigNeverContainsSessionPassword()
        try await tests.testBrokerRoundTripWithAskPassExecutable()
        print("Passed all 6 Swift model/auth checks.")
    }
}
