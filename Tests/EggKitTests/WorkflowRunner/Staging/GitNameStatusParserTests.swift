@testable import EggKit
import Foundation
import Path
import Testing

struct GitNameStatusParserTests {
    @Test(arguments: TestCase.allCases)
    func parse(_ testCase: TestCase) throws {
        let workingRoot = try AbsolutePath(validating: testCase.workingRoot)
        let workspaceRoot = try AbsolutePath(validating: testCase.workspaceRoot)

        let parser = GitNameStatusParser(
            workingRoot: workingRoot,
            workspaceRoot: workspaceRoot
        )

        let result = parser.parse(components: testCase.components.map { Substring($0) })

        let expectedAdded = try testCase.expectedAdded.map { try RelativePath(validating: $0) }
        let expectedModified = try testCase.expectedModified.map { try RelativePath(validating: $0) }
        let expectedDeleted = try testCase.expectedDeleted.map { try RelativePath(validating: $0) }
        let expected = ChangeSummary(added: expectedAdded, modified: expectedModified, deleted: expectedDeleted)

        #expect(result == expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let components: [String]
        let workingRoot: String
        let workspaceRoot: String
        let expectedAdded: [String]
        let expectedModified: [String]
        let expectedDeleted: [String]

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            TestCase(
                description: "parses empty components",
                components: [],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "parses single added file",
                components: ["A", "newfile.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["newfile.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "parses single modified file",
                components: ["M", "existing.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: [],
                expectedModified: ["existing.txt"],
                expectedDeleted: []
            ),
            TestCase(
                description: "parses single deleted file",
                components: ["D", "removed.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: ["removed.txt"]
            ),
            TestCase(
                description: "parses multiple changes of same type",
                components: ["A", "file1.txt", "A", "file2.txt", "A", "file3.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["file1.txt", "file2.txt", "file3.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "parses mixed changes",
                components: ["A", "new.txt", "M", "changed.txt", "D", "gone.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["new.txt"],
                expectedModified: ["changed.txt"],
                expectedDeleted: ["gone.txt"]
            ),
            TestCase(
                description: "parses rename as delete and add",
                components: ["R100", "old.txt", "new.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["new.txt"],
                expectedModified: [],
                expectedDeleted: ["old.txt"]
            ),
            TestCase(
                description: "parses rename with similarity score",
                components: ["R095", "original.txt", "renamed.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["renamed.txt"],
                expectedModified: [],
                expectedDeleted: ["original.txt"]
            ),
            TestCase(
                description: "strips working root prefix from path",
                components: ["A", "/work/src/file.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["src/file.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "strips staging root prefix from path",
                components: ["M", "/staging/lib/module.swift"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: [],
                expectedModified: ["lib/module.swift"],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles paths with nested directories",
                components: ["A", "src/components/Button.swift", "M", "tests/unit/ButtonTests.swift"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["src/components/Button.swift"],
                expectedModified: ["tests/unit/ButtonTests.swift"],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles unknown status by skipping",
                components: ["X", "unknown.txt", "A", "valid.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["valid.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles copy status by skipping",
                components: ["C", "src.txt", "dest.txt", "A", "new.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["new.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "sorts output paths alphabetically",
                components: ["A", "zebra.txt", "A", "apple.txt", "A", "mango.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["apple.txt", "mango.txt", "zebra.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles empty status line gracefully",
                components: ["", "A", "file.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["file.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles file paths with spaces",
                components: ["A", "path with spaces/file name.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["path with spaces/file name.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles mixed root prefixes",
                components: ["A", "/work/from-work.txt", "M", "/staging/from-staging.txt", "D", "no-prefix.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["from-work.txt"],
                expectedModified: ["from-staging.txt"],
                expectedDeleted: ["no-prefix.txt"]
            ),
            TestCase(
                description: "handles rename across directories",
                components: ["R100", "/work/old/file.txt", "/staging/new/file.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["new/file.txt"],
                expectedModified: [],
                expectedDeleted: ["old/file.txt"]
            ),
            TestCase(
                description: "handles multiple renames",
                components: ["R100", "a.txt", "b.txt", "R090", "x.txt", "y.txt"],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["b.txt", "y.txt"],
                expectedModified: [],
                expectedDeleted: ["a.txt", "x.txt"]
            ),
            TestCase(
                description: "handles complex realistic scenario",
                components: [
                    "A", "/work/Sources/NewFeature.swift",
                    "M", "/staging/Sources/Existing.swift",
                    "D", "Sources/Deprecated.swift",
                    "R100", "/work/Tests/OldTest.swift", "/staging/Tests/NewTest.swift",
                ],
                workingRoot: "/work",
                workspaceRoot: "/staging",
                expectedAdded: ["Sources/NewFeature.swift", "Tests/NewTest.swift"],
                expectedModified: ["Sources/Existing.swift"],
                expectedDeleted: ["Sources/Deprecated.swift", "Tests/OldTest.swift"]
            ),
        ]
    }
}
