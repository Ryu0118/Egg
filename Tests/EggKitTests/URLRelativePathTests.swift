@testable import EggKit
import Foundation
import Testing

struct URLRelativePathTests {
    @Test(arguments: RelativePathTestCase.allCases)
    func `relative path`(_ testCase: RelativePathTestCase) {
        let target = URL(filePath: testCase.targetPath)
        let base = URL(filePath: testCase.basePath)

        let result = target.relativePath(from: base)

        #expect(result == testCase.expected)
    }

    @Test(arguments: IsUnderTestCase.allCases)
    func `is under`(_ testCase: IsUnderTestCase) {
        let target = URL(filePath: testCase.targetPath)
        let base = URL(filePath: testCase.basePath)

        let result = target.isUnder(base)

        #expect(result == testCase.expected)
    }

    @Test
    func `appending relative path`() {
        let base = URL(filePath: "/Users/user/Projects")
        let result = base.appendingRelativePath("MyApp/Sources")

        #expect(result.path(percentEncoded: false) == "/Users/user/Projects/MyApp/Sources")
    }

    @Test
    func `appending relative path with empty string`() {
        let base = URL(filePath: "/Users/user/Projects")
        let result = base.appendingRelativePath("")

        #expect(result.path(percentEncoded: false) == "/Users/user/Projects")
    }

    @Test
    func `appending relative path with dot`() {
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

        var testDescription: String {
            description
        }

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
    }

    struct IsUnderTestCase: CustomTestStringConvertible {
        let description: String
        let targetPath: String
        let basePath: String
        let expected: Bool

        var testDescription: String {
            description
        }

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
    }
}
