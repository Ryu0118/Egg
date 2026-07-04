@testable import EggKit
import Foundation
import Testing

struct StepOutputParserTests {
    @Test(arguments: TestCase.allCases)
    func parse(_ testCase: TestCase) {
        let result = StepOutputParser.parse(testCase.stdout)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let stdout: String
        let expected: [String: String]

        static let allCases: [TestCase] = [
            TestCase(
                description: "parses basic key=value pairs",
                stdout: """
                version=1.0.0
                name=MyApp
                """,
                expected: ["version": "1.0.0", "name": "MyApp"],
            ),
            TestCase(
                description: "parses single key=value",
                stdout: "version=1.0.0",
                expected: ["version": "1.0.0"],
            ),
            TestCase(
                description: "parses value containing equals sign",
                stdout: "equation=x=y+z",
                expected: ["equation": "x=y+z"],
            ),
            TestCase(
                description: "parses with whitespace trimming",
                stdout: """
                  version  =  1.0.0
                name=MyApp
                """,
                expected: ["version": "1.0.0", "name": "MyApp"],
            ),
            TestCase(
                description: "skips empty lines",
                stdout: """
                version=1.0.0

                name=MyApp

                """,
                expected: ["version": "1.0.0", "name": "MyApp"],
            ),
            TestCase(
                description: "skips lines without equals sign",
                stdout: """
                version=1.0.0
                This is not a key-value pair
                name=MyApp
                """,
                expected: ["version": "1.0.0", "name": "MyApp"],
            ),
            TestCase(
                description: "skips lines with empty key",
                stdout: """
                version=1.0.0
                =value
                name=MyApp
                """,
                expected: ["version": "1.0.0", "name": "MyApp"],
            ),
            TestCase(
                description: "parses empty value",
                stdout: "key=",
                expected: ["key": ""],
            ),
            TestCase(
                description: "parses multi-line stdout with mixed content",
                stdout: """
                Starting process...
                version=1.0.0
                Debug output: processing files
                src-dir=/tmp/src
                files=3
                Done!
                """,
                expected: [
                    "version": "1.0.0",
                    "src-dir": "/tmp/src",
                    "files": "3",
                ],
            ),
            TestCase(
                description: "parses special characters in keys",
                stdout: """
                src-dir=/tmp/src
                app.name=MyApp
                BUILD_TYPE=DEBUG
                """,
                expected: [
                    "src-dir": "/tmp/src",
                    "app.name": "MyApp",
                    "BUILD_TYPE": "DEBUG",
                ],
            ),
            TestCase(
                description: "parses special characters in values",
                stdout: """
                path=/usr/local/bin
                url=https://example.com/api?key=value&foo=bar
                message=Hello, World!
                """,
                expected: [
                    "path": "/usr/local/bin",
                    "url": "https://example.com/api?key=value&foo=bar",
                    "message": "Hello, World!",
                ],
            ),
            TestCase(
                description: "parses empty stdout",
                stdout: "",
                expected: [:],
            ),
            TestCase(
                description: "parses whitespace-only stdout",
                stdout: "   \n  \n   ",
                expected: [:],
            ),
            TestCase(
                description: "parses with Windows-style line endings",
                stdout: "version=1.0.0\r\nname=MyApp",
                expected: ["version": "1.0.0\r\nname=MyApp"],
            ),
            TestCase(
                description: "overwrites duplicate keys with last value",
                stdout: """
                version=1.0.0
                version=2.0.0
                """,
                expected: ["version": "2.0.0"],
            ),
            TestCase(
                description: "parses realistic shell script output",
                stdout: """
                Preparing environment...
                version=1.0.0
                build-dir=/var/tmp/build
                Setting up dependencies
                dependency-count=5
                installed=true
                Build complete!
                """,
                expected: [
                    "version": "1.0.0",
                    "build-dir": "/var/tmp/build",
                    "dependency-count": "5",
                    "installed": "true",
                ],
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
