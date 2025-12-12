@testable import EggKit
import Foundation
import Testing

struct BuiltInMacrosTests {
    // MARK: - isReserved Tests

    @Test(arguments: IsReservedTestCase.allCases)
    func isReserved(_ testCase: IsReservedTestCase) {
        let result = BuiltInMacros.isReserved(testCase.name)
        #expect(result == testCase.expected)
    }

    struct IsReservedTestCase: CustomTestStringConvertible {
        let description: String
        let name: String
        let expected: Bool

        var testDescription: String { description }

        static let allCases: [IsReservedTestCase] = [
            // Reserved names
            IsReservedTestCase(
                description: "DATE is reserved",
                name: "___DATE___",
                expected: true
            ),
            IsReservedTestCase(
                description: "YEAR is reserved",
                name: "___YEAR___",
                expected: true
            ),
            IsReservedTestCase(
                description: "SYSTEM_USER is reserved",
                name: "___SYSTEM_USER___",
                expected: true
            ),
            IsReservedTestCase(
                description: "UUID is reserved",
                name: "___UUID___",
                expected: true
            ),

            // Non-reserved names
            IsReservedTestCase(
                description: "MODULE_NAME is not reserved",
                name: "___MODULE_NAME___",
                expected: false
            ),
            IsReservedTestCase(
                description: "CUSTOM is not reserved",
                name: "___CUSTOM___",
                expected: false
            ),
            IsReservedTestCase(
                description: "empty string is not reserved",
                name: "",
                expected: false
            ),
            IsReservedTestCase(
                description: "DATE without underscores is not reserved",
                name: "DATE",
                expected: false
            ),
        ]
    }

    // MARK: - resolve Tests

    @Test(arguments: ResolveTestCase.allCases)
    func resolve(_ testCase: ResolveTestCase) {
        let result = BuiltInMacros.resolve(testCase.input, context: testCase.context)
        #expect(result == testCase.expected)
    }

    struct ResolveTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let context: BuiltInMacroContext
        let expected: String

        var testDescription: String { description }

        static let fixedDate = Date(timeIntervalSince1970: 1_733_961_600) // 2024-12-12 00:00:00 UTC

        static let defaultContext = BuiltInMacroContext(
            workingDirectory: URL(filePath: "/tmp"),
            homeDirectory: URL(filePath: "/Users/testuser"),
            currentDate: fixedDate,
            environment: ["USER": "testuser"]
        )

        static let allCases: [ResolveTestCase] = [
            // DATE macro
            ResolveTestCase(
                description: "resolves ___DATE___ to default format",
                input: "Today is ___DATE___",
                context: defaultContext,
                expected: "Today is 2024-12-12"
            ),
            ResolveTestCase(
                description: "resolves ___DATE(yyyyMMdd)___ to custom format",
                input: "Date: ___DATE(yyyyMMdd)___",
                context: defaultContext,
                expected: "Date: 20241212"
            ),
            ResolveTestCase(
                description: "resolves ___DATE(MM/dd/yyyy)___ to custom format",
                input: "___DATE(MM/dd/yyyy)___",
                context: defaultContext,
                expected: "12/12/2024"
            ),
            ResolveTestCase(
                description: "resolves multiple DATE macros",
                input: "___DATE___ and ___DATE(yyyyMMdd)___",
                context: defaultContext,
                expected: "2024-12-12 and 20241212"
            ),

            // YEAR macro
            ResolveTestCase(
                description: "resolves ___YEAR___",
                input: "Copyright ___YEAR___",
                context: defaultContext,
                expected: "Copyright 2024"
            ),

            // SYSTEM_USER macro
            ResolveTestCase(
                description: "resolves ___SYSTEM_USER___",
                input: "Author: ___SYSTEM_USER___",
                context: defaultContext,
                expected: "Author: testuser"
            ),

            // UUID macro - can't test exact value, tested separately
            // Mixed macros
            ResolveTestCase(
                description: "resolves multiple different macros",
                input: "___YEAR___ by ___SYSTEM_USER___",
                context: defaultContext,
                expected: "2024 by testuser"
            ),

            // No macros
            ResolveTestCase(
                description: "returns unchanged text when no macros",
                input: "Hello World",
                context: defaultContext,
                expected: "Hello World"
            ),
            ResolveTestCase(
                description: "returns empty string unchanged",
                input: "",
                context: defaultContext,
                expected: ""
            ),

            // Partial matches (should not resolve)
            ResolveTestCase(
                description: "does not resolve incomplete macro prefix",
                input: "___DATE",
                context: defaultContext,
                expected: "___DATE"
            ),
            ResolveTestCase(
                description: "does not resolve incomplete macro suffix",
                input: "DATE___",
                context: defaultContext,
                expected: "DATE___"
            ),
        ]
    }

    // MARK: - UUID Tests (special case - unique per occurrence)

    @Test
    func resolveUUID_generatesValidUUID() {
        let context = BuiltInMacroContext(
            workingDirectory: URL(filePath: "/tmp"),
            homeDirectory: URL(filePath: "/Users/test"),
            currentDate: Date(),
            environment: [:]
        )

        let result = BuiltInMacros.resolve("___UUID___", context: context)

        // Should be a valid UUID format
        #expect(UUID(uuidString: result) != nil)
    }

    @Test
    func resolveUUID_generatesUniqueValuesPerOccurrence() {
        let context = BuiltInMacroContext(
            workingDirectory: URL(filePath: "/tmp"),
            homeDirectory: URL(filePath: "/Users/test"),
            currentDate: Date(),
            environment: [:]
        )

        let result = BuiltInMacros.resolve("___UUID___ ___UUID___", context: context)
        let uuids = result.split(separator: " ").map(String.init)

        #expect(uuids.count == 2)
        #expect(uuids[0] != uuids[1])
    }

    // MARK: - SYSTEM_USER fallback Tests

    @Test
    func resolveSystemUser_fallsBackToNSUserName_whenEnvMissing() {
        let context = BuiltInMacroContext(
            workingDirectory: URL(filePath: "/tmp"),
            homeDirectory: URL(filePath: "/Users/test"),
            currentDate: Date(),
            environment: [:] // No USER in environment
        )

        let result = BuiltInMacros.resolve("___SYSTEM_USER___", context: context)

        // Should fall back to NSUserName()
        #expect(result == NSUserName())
    }
}

// MARK: - BuiltInMacro Tests

struct BuiltInMacroTests {
    @Test
    func declare_createsSimpleMacro() {
        let macro = BuiltInMacro.declare("___TEST___") { _ in "resolved" }

        #expect(macro.name == "___TEST___")
        #expect(macro.acceptsArgument == false)
    }

    @Test
    func declareWithArgument_createsMacroThatAcceptsArgument() {
        let macro = BuiltInMacro.declareWithArgument("___TEST___") { arg, _ in
            arg ?? "default"
        }

        #expect(macro.name == "___TEST___")
        #expect(macro.acceptsArgument == true)
    }

    @Test(arguments: ArgumentExtractionTestCase.allCases)
    func declareWithArgument_extractsArgumentCorrectly(_ testCase: ArgumentExtractionTestCase) {
        // Use BuiltInMacros.DATE which is declared with argument to test extraction
        // We test this indirectly by checking the output format changes based on argument
        let context = BuiltInMacroContext(
            workingDirectory: URL(filePath: "/tmp"),
            homeDirectory: URL(filePath: "/Users/test"),
            currentDate: Date(timeIntervalSince1970: 1_733_961_600), // 2024-12-12
            environment: [:]
        )

        let result = BuiltInMacros.resolve(testCase.matchedString, context: context)
        #expect(result == testCase.expectedResult)
    }

    struct ArgumentExtractionTestCase: CustomTestStringConvertible {
        let description: String
        let matchedString: String
        let expectedResult: String

        var testDescription: String { description }

        static let allCases: [ArgumentExtractionTestCase] = [
            ArgumentExtractionTestCase(
                description: "DATE with yyyyMMdd format",
                matchedString: "___DATE(yyyyMMdd)___",
                expectedResult: "20241212"
            ),
            ArgumentExtractionTestCase(
                description: "DATE with yyyy-MM-dd format",
                matchedString: "___DATE(yyyy-MM-dd)___",
                expectedResult: "2024-12-12"
            ),
            ArgumentExtractionTestCase(
                description: "DATE without argument uses default format",
                matchedString: "___DATE___",
                expectedResult: "2024-12-12"
            ),
            ArgumentExtractionTestCase(
                description: "DATE with MM/dd/yyyy format",
                matchedString: "___DATE(MM/dd/yyyy)___",
                expectedResult: "12/12/2024"
            ),
        ]
    }
}
