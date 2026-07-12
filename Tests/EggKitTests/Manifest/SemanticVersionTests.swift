@testable import EggKit
import Foundation
import Testing

struct SemanticVersionTests {
    // MARK: - Parsing

    @Test("parses strict SemVer strings and rejects invalid ones", arguments: ParseTestCase.allCases)
    func parseString(_ testCase: ParseTestCase) {
        let result = SemanticVersion(testCase.input)
        #expect((result != nil) == testCase.isValid, "input: \(testCase.input)")
        if let expected = testCase.expectedDescription {
            #expect(result?.description == expected)
        }
    }

    struct ParseTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let isValid: Bool
        let expectedDescription: String?

        static let allCases: [ParseTestCase] = [
            ParseTestCase(
                description: "plain version",
                input: "1.2.3",
                isValid: true,
                expectedDescription: "1.2.3",
            ),
            ParseTestCase(
                description: "zero version",
                input: "0.0.0",
                isValid: true,
                expectedDescription: "0.0.0",
            ),
            ParseTestCase(
                description: "prerelease identifiers",
                input: "1.2.3-rc.1",
                isValid: true,
                expectedDescription: "1.2.3-rc.1",
            ),
            ParseTestCase(
                description: "build metadata is preserved in description",
                input: "1.2.3+build.5",
                isValid: true,
                expectedDescription: "1.2.3+build.5",
            ),
            ParseTestCase(
                description: "prerelease and build metadata combined",
                input: "1.2.3-alpha.7+exp.sha.5114f85",
                isValid: true,
                expectedDescription: "1.2.3-alpha.7+exp.sha.5114f85",
            ),
            ParseTestCase(
                description: "v prefix is rejected by the strict initializer",
                input: "v1.2.3",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "two components are rejected",
                input: "1.2",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "four components are rejected",
                input: "1.2.3.4",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "leading zero in core is rejected",
                input: "01.2.3",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "leading zero in numeric prerelease identifier is rejected",
                input: "1.2.3-01",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "empty prerelease identifier is rejected",
                input: "1.2.3-rc..1",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "empty build identifier is rejected",
                input: "1.2.3+",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "non-numeric core is rejected",
                input: "version-1.2.0",
                isValid: false,
                expectedDescription: nil,
            ),
            ParseTestCase(
                description: "empty string is rejected",
                input: "",
                isValid: false,
                expectedDescription: nil,
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - Tag parsing

    @Test("parses Git tags, stripping exactly one leading v", arguments: TagTestCase.allCases)
    func parseTag(_ testCase: TagTestCase) {
        let result = SemanticVersion.parse(tag: testCase.tag)
        #expect((result != nil) == testCase.isValid, "tag: \(testCase.tag)")
        if let result, testCase.isValid {
            #expect(result.version.description == testCase.expectedDescription)
            #expect(result.hadVPrefix == testCase.expectedHadVPrefix)
        }
    }

    struct TagTestCase: CustomTestStringConvertible {
        let description: String
        let tag: String
        let isValid: Bool
        let expectedDescription: String
        let expectedHadVPrefix: Bool

        static let allCases: [TagTestCase] = [
            TagTestCase(
                description: "bare version tag",
                tag: "1.2.3",
                isValid: true,
                expectedDescription: "1.2.3",
                expectedHadVPrefix: false,
            ),
            TagTestCase(
                description: "v-prefixed tag",
                tag: "v1.2.3",
                isValid: true,
                expectedDescription: "1.2.3",
                expectedHadVPrefix: true,
            ),
            TagTestCase(
                description: "v-prefixed prerelease tag",
                tag: "v2.0.0-beta.1",
                isValid: true,
                expectedDescription: "2.0.0-beta.1",
                expectedHadVPrefix: true,
            ),
            TagTestCase(
                description: "double v prefix is rejected (only one v is stripped)",
                tag: "vv1.2.3",
                isValid: false,
                expectedDescription: "",
                expectedHadVPrefix: false,
            ),
            TagTestCase(
                description: "arbitrary tag text is rejected",
                tag: "release-2024-01",
                isValid: false,
                expectedDescription: "",
                expectedHadVPrefix: false,
            ),
            TagTestCase(
                description: "two-component tag is rejected (strict SemVer requires three)",
                tag: "v1.2",
                isValid: false,
                expectedDescription: "",
                expectedHadVPrefix: false,
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - Precedence (SemVer 2.0 §11)

    @Test("orders the SemVer 2.0 §11 precedence chain")
    func precedenceChain() throws {
        let chain = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "1.1.0",
            "2.0.0",
        ]
        let versions = try chain.map { try #require(SemanticVersion($0), "failed to parse \($0)") }
        for (index, lower) in versions.enumerated() {
            for higher in versions[versions.index(after: index)...] {
                #expect(lower < higher, "\(lower) should be < \(higher)")
                #expect(!(higher < lower), "\(higher) should not be < \(lower)")
            }
        }
    }

    @Test("build metadata is ignored for equality and precedence")
    func buildMetadataIgnored() throws {
        let plain = try #require(SemanticVersion("1.2.3"))
        let withMetadata = try #require(SemanticVersion("1.2.3+build.42"))
        #expect(plain == withMetadata)
        #expect(!(plain < withMetadata))
        #expect(!(withMetadata < plain))
        #expect(plain.hashValue == withMetadata.hashValue)
    }

    // MARK: - Range membership (from: / upToNextMajor)

    @Test("evaluates upToNextMajor range membership", arguments: RangeTestCase.allCases)
    func rangeMembership(_ testCase: RangeTestCase) throws {
        let lowerBound = try #require(SemanticVersion(testCase.from))
        let candidate = try #require(SemanticVersion(testCase.candidate))
        #expect(
            candidate.satisfies(upToNextMajorFrom: lowerBound) == testCase.isIncluded,
            "from: \(testCase.from), candidate: \(testCase.candidate)",
        )
    }

    struct RangeTestCase: CustomTestStringConvertible {
        let description: String
        let from: String
        let candidate: String
        let isIncluded: Bool

        static let allCases: [RangeTestCase] = [
            RangeTestCase(description: "lower bound itself", from: "1.0.0", candidate: "1.0.0", isIncluded: true),
            RangeTestCase(description: "patch bump", from: "1.0.0", candidate: "1.0.1", isIncluded: true),
            RangeTestCase(description: "minor bump", from: "1.0.0", candidate: "1.99.99", isIncluded: true),
            RangeTestCase(description: "next major is excluded", from: "1.0.0", candidate: "2.0.0", isIncluded: false),
            RangeTestCase(description: "below lower bound is excluded", from: "1.0.0", candidate: "0.9.9", isIncluded: false),
            RangeTestCase(
                description: "prerelease is excluded from a release-bounded range",
                from: "1.0.0",
                candidate: "1.5.0-beta.1",
                isIncluded: false,
            ),
            RangeTestCase(
                description: "next-major prerelease is excluded from a release-bounded range",
                from: "1.0.0",
                candidate: "2.0.0-alpha",
                isIncluded: false,
            ),
            RangeTestCase(
                description: "prerelease lower bound includes itself",
                from: "1.2.0-rc.1",
                candidate: "1.2.0-rc.1",
                isIncluded: true,
            ),
            RangeTestCase(
                description: "prerelease lower bound includes later prereleases",
                from: "1.2.0-rc.1",
                candidate: "1.2.0-rc.2",
                isIncluded: true,
            ),
            RangeTestCase(
                description: "prerelease lower bound includes the release",
                from: "1.2.0-rc.1",
                candidate: "1.2.0",
                isIncluded: true,
            ),
            RangeTestCase(
                description: "prerelease lower bound excludes lower-precedence prereleases",
                from: "1.2.0-rc.1",
                candidate: "1.2.0-beta.1",
                isIncluded: false,
            ),
            RangeTestCase(
                description: "prerelease lower bound still excludes the next major",
                from: "1.2.0-rc.1",
                candidate: "2.0.0",
                isIncluded: false,
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
