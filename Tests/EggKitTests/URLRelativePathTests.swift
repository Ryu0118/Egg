@testable import EggKit
import Foundation
import Testing

struct URLRelativePathTests {
    @Test(
        "computes a path relative to a base directory, falling back to the absolute path when the target isn't under the base",
        arguments: RelativePathTestCase.allCases,
    )
    func relativePath(_ testCase: RelativePathTestCase) {
        let target = URL(filePath: testCase.targetPath)
        let base = URL(filePath: testCase.basePath)

        let result = target.relativePath(from: base)

        #expect(result == testCase.expected)
    }

    @Test(
        "determines whether a target path is contained within a base directory, rejecting partial-prefix false positives",
        arguments: IsUnderTestCase.allCases,
    )
    func isUnder(_ testCase: IsUnderTestCase) {
        let target = URL(filePath: testCase.targetPath)
        let base = URL(filePath: testCase.basePath)

        let result = target.isUnder(base)

        #expect(result == testCase.expected)
    }

    @Test("appends a relative path segment to a base URL to form the combined absolute path")
    func appendingRelativePath() {
        let base = URL(filePath: "/Users/user/Projects")
        let result = base.appendingRelativePath("MyApp/Sources")

        #expect(result.path(percentEncoded: false) == "/Users/user/Projects/MyApp/Sources")
    }

    @Test("appending an empty relative path leaves the base URL unchanged")
    func appendingRelativePathWithEmptyString() {
        let base = URL(filePath: "/Users/user/Projects")
        let result = base.appendingRelativePath("")

        #expect(result.path(percentEncoded: false) == "/Users/user/Projects")
    }

    @Test("appending \".\" as the relative path leaves the base URL unchanged")
    func appendingRelativePathWithDot() {
        let base = URL(filePath: "/Users/user/Projects")
        let result = base.appendingRelativePath(".")

        #expect(result.path(percentEncoded: false) == "/Users/user/Projects")
    }
}

extension URLRelativePathTests {
    struct RelativePathTestCase: CustomTestStringConvertible {
        let description: String
        let targetPath: String
        let basePath: String
        let expected: String

        static let allCases: [RelativePathTestCase] = [
            // Basic cases
            RelativePathTestCase(
                description: "returns relative path for subdirectory",
                targetPath: "/Users/user/Projects/MyApp",
                basePath: "/Users/user/Projects",
                expected: "MyApp",
            ),
            RelativePathTestCase(
                description: "returns relative path for deeply nested subdirectory",
                targetPath: "/Users/user/Projects/MyApp/Sources/Models",
                basePath: "/Users/user/Projects",
                expected: "MyApp/Sources/Models",
            ),
            RelativePathTestCase(
                description: "returns dot for same path",
                targetPath: "/Users/user/Projects",
                basePath: "/Users/user/Projects",
                expected: ".",
            ),

            // Trailing slash handling
            RelativePathTestCase(
                description: "handles base path with trailing slash",
                targetPath: "/Users/user/Projects/MyApp",
                basePath: "/Users/user/Projects/",
                expected: "MyApp",
            ),
            RelativePathTestCase(
                description: "handles target path with trailing slash",
                targetPath: "/Users/user/Projects/MyApp/",
                basePath: "/Users/user/Projects",
                expected: "MyApp",
            ),
            RelativePathTestCase(
                description: "handles both paths with trailing slash",
                targetPath: "/Users/user/Projects/MyApp/",
                basePath: "/Users/user/Projects/",
                expected: "MyApp",
            ),
            RelativePathTestCase(
                description: "returns dot for same path with trailing slashes",
                targetPath: "/Users/user/Projects/",
                basePath: "/Users/user/Projects/",
                expected: ".",
            ),

            // Not under base - returns absolute path
            RelativePathTestCase(
                description: "returns absolute path when target is not under base",
                targetPath: "/var/tmp/file",
                basePath: "/Users/user/Projects",
                expected: "/var/tmp/file",
            ),
            RelativePathTestCase(
                description: "returns absolute path when paths are siblings",
                targetPath: "/Users/user/Documents",
                basePath: "/Users/user/Projects",
                expected: "/Users/user/Documents",
            ),
            RelativePathTestCase(
                description: "returns absolute path when target is parent of base",
                targetPath: "/Users/user",
                basePath: "/Users/user/Projects",
                expected: "/Users/user",
            ),

            // Edge case: partial prefix match (not a real subdirectory)
            RelativePathTestCase(
                description: "returns absolute path when target has similar prefix but is not subdirectory",
                targetPath: "/Users/user/ProjectsBackup",
                basePath: "/Users/user/Projects",
                expected: "/Users/user/ProjectsBackup",
            ),

            // Root paths
            RelativePathTestCase(
                description: "handles root as base",
                targetPath: "/Users/user",
                basePath: "/",
                expected: "/Users/user",
            ),
            RelativePathTestCase(
                description: "returns dot for root to root",
                targetPath: "/",
                basePath: "/",
                expected: ".",
            ),

            // Single component
            RelativePathTestCase(
                description: "returns single component for immediate child",
                targetPath: "/Users/user/Projects/file.txt",
                basePath: "/Users/user/Projects",
                expected: "file.txt",
            ),
        ]

        var testDescription: String {
            description
        }
    }

    struct IsUnderTestCase: CustomTestStringConvertible {
        let description: String
        let targetPath: String
        let basePath: String
        let expected: Bool

        static let allCases: [IsUnderTestCase] = [
            // Under base
            IsUnderTestCase(
                description: "returns true for subdirectory",
                targetPath: "/Users/user/Projects/MyApp",
                basePath: "/Users/user/Projects",
                expected: true,
            ),
            IsUnderTestCase(
                description: "returns true for deeply nested subdirectory",
                targetPath: "/Users/user/Projects/MyApp/Sources/Models",
                basePath: "/Users/user/Projects",
                expected: true,
            ),
            IsUnderTestCase(
                description: "returns true for same path",
                targetPath: "/Users/user/Projects",
                basePath: "/Users/user/Projects",
                expected: true,
            ),

            // Trailing slash handling
            IsUnderTestCase(
                description: "returns true with base trailing slash",
                targetPath: "/Users/user/Projects/MyApp",
                basePath: "/Users/user/Projects/",
                expected: true,
            ),
            IsUnderTestCase(
                description: "returns true with target trailing slash",
                targetPath: "/Users/user/Projects/MyApp/",
                basePath: "/Users/user/Projects",
                expected: true,
            ),
            IsUnderTestCase(
                description: "returns true for same path with trailing slashes",
                targetPath: "/Users/user/Projects/",
                basePath: "/Users/user/Projects/",
                expected: true,
            ),

            // Not under base
            IsUnderTestCase(
                description: "returns false for unrelated path",
                targetPath: "/var/tmp/file",
                basePath: "/Users/user/Projects",
                expected: false,
            ),
            IsUnderTestCase(
                description: "returns false for sibling path",
                targetPath: "/Users/user/Documents",
                basePath: "/Users/user/Projects",
                expected: false,
            ),
            IsUnderTestCase(
                description: "returns false when target is parent of base",
                targetPath: "/Users/user",
                basePath: "/Users/user/Projects",
                expected: false,
            ),

            // Critical edge case: partial prefix match
            IsUnderTestCase(
                description: "returns false when target has similar prefix but is not subdirectory",
                targetPath: "/Users/user/ProjectsBackup",
                basePath: "/Users/user/Projects",
                expected: false,
            ),
            IsUnderTestCase(
                description: "returns false for prefix match without path separator",
                targetPath: "/foo/barbaz",
                basePath: "/foo/bar",
                expected: false,
            ),

            // Root handling
            IsUnderTestCase(
                description: "returns false when base is root",
                targetPath: "/Users/user",
                basePath: "/",
                expected: false,
            ),
            IsUnderTestCase(
                description: "returns true for root under root",
                targetPath: "/",
                basePath: "/",
                expected: true,
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
