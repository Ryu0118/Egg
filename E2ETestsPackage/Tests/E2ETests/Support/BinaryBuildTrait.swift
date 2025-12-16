import Foundation
import Testing

/// Suite trait that ensures the binary is built before tests run
struct BinaryBuildTrait: SuiteTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Ensure binary is built before running tests
        _ = try await BinaryBuildState.shared.getBinaryPath()

        // Execute the test
        try await function()
    }
}

extension Trait where Self == BinaryBuildTrait {
    /// Trait that builds the CLI binary once before test suite execution
    static var buildBinary: Self { BinaryBuildTrait() }
}
