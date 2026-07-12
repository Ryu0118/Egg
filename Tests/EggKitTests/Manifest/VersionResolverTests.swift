@testable import EggKit
import Foundation
import Testing

struct VersionResolverTests {
    private static let lockedSHA = String(repeating: "a", count: 40)
    private static let tipSHA = String(repeating: "b", count: 40)

    // MARK: - Lock reuse decisions (sync)

    @Test("applies the Package.resolved reuse rules", arguments: ReuseTestCase.allCases)
    func lockReuse(_ testCase: ReuseTestCase) {
        let resolution = VersionResolver.reusableResolution(
            for: testCase.requirement,
            locked: testCase.locked,
        )
        #expect((resolution != nil) == testCase.expectReuse)
        if let resolution, testCase.expectReuse {
            #expect(resolution.reusedLock)
            #expect(resolution.revision == Self.lockedSHA)
        }
    }

    struct ReuseTestCase: CustomTestStringConvertible {
        let description: String
        let requirement: VersionRequirement
        let locked: LockedResolution?
        let expectReuse: Bool

        static let allCases: [ReuseTestCase] = [
            ReuseTestCase(
                description: "no lock entry resolves fresh",
                requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
                locked: nil,
                expectReuse: false,
            ),
            ReuseTestCase(
                description: "locked version inside the from range is reused",
                requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
                locked: LockedResolution(version: "1.1.0", tag: "v1.1.0", revision: lockedSHA),
                expectReuse: true,
            ),
            ReuseTestCase(
                description: "locked version outside a bumped from range re-resolves",
                requirement: .from(SemanticVersion(major: 2, minor: 0, patch: 0)),
                locked: LockedResolution(version: "1.1.0", tag: "v1.1.0", revision: lockedSHA),
                expectReuse: false,
            ),
            ReuseTestCase(
                description: "exact match on the locked version is reused",
                requirement: .exact(SemanticVersion(major: 1, minor: 1, patch: 0)),
                locked: LockedResolution(version: "1.1.0", tag: "1.1.0", revision: lockedSHA),
                expectReuse: true,
            ),
            ReuseTestCase(
                description: "exact mismatch re-resolves",
                requirement: .exact(SemanticVersion(major: 1, minor: 2, patch: 0)),
                locked: LockedResolution(version: "1.1.0", tag: "1.1.0", revision: lockedSHA),
                expectReuse: false,
            ),
            ReuseTestCase(
                description: "same branch pins to the locked SHA even if the tip moved",
                requirement: .branch("main"),
                locked: LockedResolution(branch: "main", revision: lockedSHA),
                expectReuse: true,
            ),
            ReuseTestCase(
                description: "different branch re-resolves",
                requirement: .branch("develop"),
                locked: LockedResolution(branch: "main", revision: lockedSHA),
                expectReuse: false,
            ),
            ReuseTestCase(
                description: "matching revision is trivially reused",
                requirement: .revision(lockedSHA),
                locked: LockedResolution(revision: lockedSHA),
                expectReuse: true,
            ),
            ReuseTestCase(
                description: "changed revision re-resolves",
                requirement: .revision(tipSHA),
                locked: LockedResolution(revision: lockedSHA),
                expectReuse: false,
            ),
            ReuseTestCase(
                description: "lock without a version cannot satisfy from",
                requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
                locked: LockedResolution(branch: "main", revision: lockedSHA),
                expectReuse: false,
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - Fresh tag resolution

    @Test("picks the highest version satisfying from, excluding prereleases")
    func fromPicksHighest() throws {
        let tags = [
            GitRemoteTag(name: "1.0.0", objectSHA: sha("10")),
            GitRemoteTag(name: "v1.1.0", objectSHA: sha("11"), peeledSHA: sha("1p")),
            GitRemoteTag(name: "1.2.0-rc.1", objectSHA: sha("12")),
            GitRemoteTag(name: "2.0.0", objectSHA: sha("20")),
            GitRemoteTag(name: "not-a-version", objectSHA: sha("ff")),
        ]

        let resolution = try VersionResolver.resolve(
            requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
            tags: tags,
            url: "https://github.com/owner/repo.git",
        )

        #expect(resolution.version == SemanticVersion(major: 1, minor: 1, patch: 0))
        #expect(resolution.tag == "v1.1.0")
        #expect(resolution.revision == sha("1p"), "annotated tags resolve to the peeled SHA")
        #expect(!resolution.reusedLock)
    }

    @Test("includes prereleases only when the lower bound is a prerelease")
    func prereleaseLowerBound() throws {
        let tags = [
            GitRemoteTag(name: "1.2.0-beta.1", objectSHA: sha("1b")),
            GitRemoteTag(name: "1.2.0-rc.1", objectSHA: sha("1r")),
            GitRemoteTag(name: "1.2.0-rc.2", objectSHA: sha("2r")),
        ]

        let lowerBound = try #require(SemanticVersion("1.2.0-rc.1"))
        let resolution = try VersionResolver.resolve(
            requirement: .from(lowerBound),
            tags: tags,
            url: "https://github.com/owner/repo.git",
        )

        #expect(resolution.version?.description == "1.2.0-rc.2")
    }

    @Test("prefers the non-v tag when both spellings of a version exist")
    func vPrefixDuplicate() throws {
        let tags = [
            GitRemoteTag(name: "v1.2.3", objectSHA: sha("aa")),
            GitRemoteTag(name: "1.2.3", objectSHA: sha("bb")),
        ]

        let resolution = try VersionResolver.resolve(
            requirement: .exact(SemanticVersion(major: 1, minor: 2, patch: 3)),
            tags: tags,
            url: "https://github.com/owner/repo.git",
        )

        #expect(resolution.tag == "1.2.3")
        #expect(resolution.revision == sha("bb"))
    }

    @Test("exact matches v-prefixed tags by parsed-version equality")
    func exactMatchesVPrefix() throws {
        let tags = [GitRemoteTag(name: "v1.2.0", objectSHA: sha("cc"))]

        let resolution = try VersionResolver.resolve(
            requirement: .exact(SemanticVersion(major: 1, minor: 2, patch: 0)),
            tags: tags,
            url: "https://github.com/owner/repo.git",
        )

        #expect(resolution.tag == "v1.2.0")
    }

    // MARK: - Errors

    @Test("noMatchingVersion names the highest available semver tag")
    func noMatchingVersion() {
        let tags = [
            GitRemoteTag(name: "1.0.0", objectSHA: sha("10")),
            GitRemoteTag(name: "1.1.0", objectSHA: sha("11")),
            GitRemoteTag(name: "2.0.0-beta.1", objectSHA: sha("2b")),
        ]

        #expect {
            try VersionResolver.resolve(
                requirement: .from(SemanticVersion(major: 2, minor: 0, patch: 0)),
                tags: tags,
                url: "https://github.com/owner/repo.git",
            )
        } throws: { error in
            guard case let ResolutionError.noMatchingVersion(url, requirement, highest) = error else {
                return false
            }
            return url == "https://github.com/owner/repo.git"
                && requirement == "from: 2.0.0"
                && highest == "2.0.0-beta.1"
        }
    }

    @Test("noMatchingVersion reports when the remote has no semver tags at all")
    func noSemverTags() {
        #expect {
            try VersionResolver.resolve(
                requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
                tags: [GitRemoteTag(name: "nightly", objectSHA: sha("ff"))],
                url: "https://github.com/owner/repo.git",
            )
        } throws: { error in
            guard case let ResolutionError.noMatchingVersion(_, _, highest) = error else {
                return false
            }
            return highest == nil
        }
    }

    @Test("error descriptions match the documented format")
    func errorDescriptions() {
        #expect(
            ResolutionError.noMatchingVersion(
                url: "https://github.com/owner/repo.git",
                requirement: "from: 2.0.0",
                highestAvailable: "2.0.0-beta.1",
            ).errorDescription
                == "no version satisfying 'from: 2.0.0' for https://github.com/owner/repo.git (highest available: 2.0.0-beta.1)",
        )
        #expect(
            ResolutionError.branchNotFound(url: "git@github.com:owner/repo.git", branch: "develop").errorDescription
                == "branch 'develop' not found in git@github.com:owner/repo.git",
        )
    }

    // MARK: - Helpers

    private func sha(_ seed: String) -> String {
        String(repeating: seed, count: 20)
    }
}
