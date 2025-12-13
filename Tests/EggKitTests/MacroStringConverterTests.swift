@testable import EggKit
import Testing
import Foundation

struct MacroStringConverterTests {
    private static let workingDirectory = URL(filePath: "/tmp/work", directoryHint: .isDirectory, relativeTo: nil)
    private static let homeDirectory = URL(filePath: "/tmp/home", directoryHint: .isDirectory, relativeTo: nil)

    @Test(arguments: ShellStringTestCase.allCases)
    func toShellString(_ testCase: ShellStringTestCase) throws {
        let result = try MacroStringConverter.toShellString(
            testCase.value,
            workingDirectory: Self.workingDirectory,
            homeDirectory: Self.homeDirectory
        )
        #expect(result == testCase.expectedResult)
    }

    struct ShellStringTestCase: CustomTestStringConvertible {
        let description: String
        let value: ResolvedMacro.Value
        let expectedResult: String

        var testDescription: String { description }

        static let allCases: [ShellStringTestCase] = [
            // String values
            ShellStringTestCase(
                description: "converts string value without quoting",
                value: .string("MyApp"),
                expectedResult: "MyApp"
            ),
            ShellStringTestCase(
                description: "converts string with spaces",
                value: .string("My App Name"),
                expectedResult: "My App Name"
            ),
            ShellStringTestCase(
                description: "converts string with special characters",
                value: .string("Hello \"World\""),
                expectedResult: "Hello \"World\""
            ),
            ShellStringTestCase(
                description: "converts empty string",
                value: .string(""),
                expectedResult: ""
            ),

            // Boolean values
            ShellStringTestCase(
                description: "converts true to 'true'",
                value: .boolean(true),
                expectedResult: "true"
            ),
            ShellStringTestCase(
                description: "converts false to 'false'",
                value: .boolean(false),
                expectedResult: "false"
            ),

            // Choice values
            ShellStringTestCase(
                description: "converts choice value",
                value: .choice("release"),
                expectedResult: "release"
            ),
            ShellStringTestCase(
                description: "converts choice with spaces",
                value: .choice("debug mode"),
                expectedResult: "debug mode"
            ),

            // Array values (default format: $elements.join(", "))
            ShellStringTestCase(
                description: "converts array to comma-separated string",
                value: .array(["iOS", "macOS", "watchOS"], format: nil),
                expectedResult: "iOS, macOS, watchOS"
            ),
            ShellStringTestCase(
                description: "converts single-element array",
                value: .array(["iOS"], format: nil),
                expectedResult: "iOS"
            ),
            ShellStringTestCase(
                description: "converts empty array",
                value: .array([], format: nil),
                expectedResult: ""
            ),
            ShellStringTestCase(
                description: "converts array with elements containing spaces",
                value: .array(["Apple Watch", "Apple TV"], format: nil),
                expectedResult: "Apple Watch, Apple TV"
            ),

            // Path values
            ShellStringTestCase(
                description: "converts absolute path",
                value: .path(URL(filePath: "/usr/local/bin")),
                expectedResult: "/usr/local/bin"
            ),
            ShellStringTestCase(
                description: "converts root path",
                value: .path(URL(filePath: "/")),
                expectedResult: "/"
            ),
            ShellStringTestCase(
                description: "converts path with spaces",
                value: .path(URL(filePath: "/tmp/My Folder")),
                expectedResult: "/tmp/My Folder"
            ),
            ShellStringTestCase(
                description: "normalizes dot components in absolute path",
                value: .path(
                    MacroStringConverterTests.workingDirectory
                        .appending(path: ".")
                        .appending(path: "Sources")
                        .appending(path: "Hoge")
                ),
                expectedResult: "/tmp/work/Sources/Hoge"
            ),
        ]
    }

    @Test(arguments: JavaScriptLiteralTestCase.allCases)
    func toJavaScriptLiteral(_ testCase: JavaScriptLiteralTestCase) {
        let result = MacroStringConverter.toJavaScriptLiteral(
            testCase.value,
            workingDirectory: Self.workingDirectory,
            homeDirectory: Self.homeDirectory
        )
        #expect(result == testCase.expectedResult)
    }

    struct JavaScriptLiteralTestCase: CustomTestStringConvertible {
        let description: String
        let value: ResolvedMacro.Value
        let expectedResult: String

        var testDescription: String { description }

        static let allCases: [JavaScriptLiteralTestCase] = [
            // String values - quoted
            JavaScriptLiteralTestCase(
                description: "quotes string value",
                value: .string("MyApp"),
                expectedResult: "\"MyApp\""
            ),
            JavaScriptLiteralTestCase(
                description: "quotes string with spaces",
                value: .string("My App Name"),
                expectedResult: "\"My App Name\""
            ),
            JavaScriptLiteralTestCase(
                description: "escapes quotes in string",
                value: .string("Hello \"World\""),
                expectedResult: "\"Hello \\\"World\\\"\""
            ),
            JavaScriptLiteralTestCase(
                description: "escapes newlines in string",
                value: .string("Line1\nLine2"),
                expectedResult: "\"Line1\\nLine2\""
            ),
            JavaScriptLiteralTestCase(
                description: "escapes tabs in string",
                value: .string("Col1\tCol2"),
                expectedResult: "\"Col1\\tCol2\""
            ),
            JavaScriptLiteralTestCase(
                description: "escapes carriage returns in string",
                value: .string("Line1\rLine2"),
                expectedResult: "\"Line1\\rLine2\""
            ),
            JavaScriptLiteralTestCase(
                description: "quotes empty string",
                value: .string(""),
                expectedResult: "\"\""
            ),

            // Boolean values - unquoted
            JavaScriptLiteralTestCase(
                description: "converts true without quotes",
                value: .boolean(true),
                expectedResult: "true"
            ),
            JavaScriptLiteralTestCase(
                description: "converts false without quotes",
                value: .boolean(false),
                expectedResult: "false"
            ),

            // Choice values - quoted
            JavaScriptLiteralTestCase(
                description: "quotes choice value",
                value: .choice("release"),
                expectedResult: "\"release\""
            ),
            JavaScriptLiteralTestCase(
                description: "quotes choice with spaces",
                value: .choice("debug mode"),
                expectedResult: "\"debug mode\""
            ),

            // Array values - JSON array with quoted elements
            JavaScriptLiteralTestCase(
                description: "converts array to JSON array",
                value: .array(["iOS", "macOS", "watchOS"], format: nil),
                expectedResult: "[\"iOS\", \"macOS\", \"watchOS\"]"
            ),
            JavaScriptLiteralTestCase(
                description: "converts single-element array to JSON",
                value: .array(["iOS"], format: nil),
                expectedResult: "[\"iOS\"]"
            ),
            JavaScriptLiteralTestCase(
                description: "converts empty array to JSON",
                value: .array([], format: nil),
                expectedResult: "[]"
            ),
            JavaScriptLiteralTestCase(
                description: "quotes array elements with spaces",
                value: .array(["Apple Watch", "Apple TV"], format: nil),
                expectedResult: "[\"Apple Watch\", \"Apple TV\"]"
            ),
            JavaScriptLiteralTestCase(
                description: "escapes special characters in array elements",
                value: .array(["Item \"1\"", "Item \"2\""], format: nil),
                expectedResult: "[\"Item \\\"1\\\"\", \"Item \\\"2\\\"\"]"
            ),

            // Path values - quoted
            JavaScriptLiteralTestCase(
                description: "quotes absolute path",
                value: .path(URL(filePath: "/usr/local/bin")),
                expectedResult: "\"/usr/local/bin\""
            ),
            JavaScriptLiteralTestCase(
                description: "quotes root path",
                value: .path(URL(filePath: "/")),
                expectedResult: "\"/\""
            ),
            JavaScriptLiteralTestCase(
                description: "quotes path with spaces",
                value: .path(URL(filePath: "/tmp/My Folder")),
                expectedResult: "\"/tmp/My Folder\""
            ),
            JavaScriptLiteralTestCase(
                description: "normalizes dot components in quoted path",
                value: .path(
                    MacroStringConverterTests.workingDirectory
                        .appending(path: ".")
                        .appending(path: "Sources")
                        .appending(path: "Hoge")
                ),
                expectedResult: "\"/tmp/work/Sources/Hoge\""
            ),
        ]
    }

    @Test(arguments: EscapeAndQuoteTestCase.allCases)
    func escapeAndQuote(_ testCase: EscapeAndQuoteTestCase) {
        let result = MacroStringConverter.escapeAndQuote(testCase.input)
        #expect(result == testCase.expectedResult)
    }

    struct EscapeAndQuoteTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expectedResult: String

        var testDescription: String { description }

        static let allCases: [EscapeAndQuoteTestCase] = [
            EscapeAndQuoteTestCase(
                description: "quotes plain string",
                input: "hello",
                expectedResult: "\"hello\""
            ),
            EscapeAndQuoteTestCase(
                description: "escapes double quotes",
                input: "Hello \"World\"",
                expectedResult: "\"Hello \\\"World\\\"\""
            ),
            EscapeAndQuoteTestCase(
                description: "escapes newlines",
                input: "Line1\nLine2\nLine3",
                expectedResult: "\"Line1\\nLine2\\nLine3\""
            ),
            EscapeAndQuoteTestCase(
                description: "escapes tabs",
                input: "Col1\tCol2\tCol3",
                expectedResult: "\"Col1\\tCol2\\tCol3\""
            ),
            EscapeAndQuoteTestCase(
                description: "escapes carriage returns",
                input: "Line1\rLine2",
                expectedResult: "\"Line1\\rLine2\""
            ),
            EscapeAndQuoteTestCase(
                description: "escapes multiple special characters",
                input: "Path: \"/tmp/test\"\nStatus: OK",
                expectedResult: "\"Path: \\\"/tmp/test\\\"\\nStatus: OK\""
            ),
            EscapeAndQuoteTestCase(
                description: "handles empty string",
                input: "",
                expectedResult: "\"\""
            ),
            EscapeAndQuoteTestCase(
                description: "handles string with only quotes",
                input: "\"\"\"",
                expectedResult: "\"\\\"\\\"\\\"\""
            ),
        ]
    }
}
