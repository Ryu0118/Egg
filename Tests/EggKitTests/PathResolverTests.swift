@testable import EggKit
import Foundation
import Testing

struct PathResolverTests {
    static let workingDirectory = URL(filePath: "/Users/test/projects")
    static let homeDirectory = URL(filePath: "/Users/test")

    @Test(arguments: PathResolverTestCase.allCases)
    func resolveToAbsoluteURL(_ testCase: PathResolverTestCase) throws {
        let result = try EggKit.resolveToAbsoluteURL(
            testCase.input,
            workingDirectory: Self.workingDirectory,
            homeDirectory: Self.homeDirectory
        )

        #expect(result.path(percentEncoded: false) == testCase.expected)
    }
}

extension PathResolverTests {
    struct PathResolverTestCase: CustomTestStringConvertible, Sendable {
        let description: String
        let input: String
        let expected: String

        var testDescription: String { description }

        static let allCases: [PathResolverTestCase] = [
            // Whitespace trimming
            PathResolverTestCase(
                description: "trims trailing whitespace",
                input: "/tmp/path ",
                expected: "/tmp/path"
            ),
            PathResolverTestCase(
                description: "trims leading whitespace",
                input: " /tmp/path",
                expected: "/tmp/path"
            ),
            PathResolverTestCase(
                description: "trims leading and trailing whitespace",
                input: "  /tmp/path  ",
                expected: "/tmp/path"
            ),
            PathResolverTestCase(
                description: "preserves middle whitespace",
                input: "/tmp/path with spaces/file",
                expected: "/tmp/path with spaces/file"
            ),
            PathResolverTestCase(
                description: "trims whitespace with tilde expansion",
                input: "~/Documents ",
                expected: "/Users/test/Documents"
            ),

            // Tilde expansion
            PathResolverTestCase(
                description: "expands tilde slash",
                input: "~/projects/app",
                expected: "/Users/test/projects/app"
            ),
            PathResolverTestCase(
                description: "expands tilde only",
                input: "~",
                expected: "/Users/test"
            ),

            // Relative path resolution
            PathResolverTestCase(
                description: "resolves relative path from working directory",
                input: "subdir/file.txt",
                expected: "/Users/test/projects/subdir/file.txt"
            ),
            PathResolverTestCase(
                description: "resolves current directory",
                input: ".",
                expected: "/Users/test/projects/"
            ),

            // Absolute path
            PathResolverTestCase(
                description: "preserves absolute path",
                input: "/absolute/path/to/file",
                expected: "/absolute/path/to/file"
            ),
        ]
    }
}
