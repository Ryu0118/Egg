@testable import EggKit
import Foundation
import Testing

struct GitRefTests {
    // MARK: - Equatable Tests

    @Test
    func equatable_sameBranch_areEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("main")
        #expect(ref1 == ref2)
    }

    @Test
    func equatable_differentBranches_areNotEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("develop")
        #expect(ref1 != ref2)
    }

    @Test
    func equatable_sameTag_areEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v1.0.0")
        #expect(ref1 == ref2)
    }

    @Test
    func equatable_differentTags_areNotEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v2.0.0")
        #expect(ref1 != ref2)
    }

    @Test
    func equatable_sameRevision_areEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("abc123")
        #expect(ref1 == ref2)
    }

    @Test
    func equatable_differentRevisions_areNotEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("def456")
        #expect(ref1 != ref2)
    }

    @Test
    func equatable_differentTypes_areNotEqual() {
        let branch = GitRef.branch("main")
        let tag = GitRef.tag("main")
        let revision = GitRef.revision("main")

        #expect(branch != tag)
        #expect(branch != revision)
        #expect(tag != revision)
    }

    // MARK: - Codable Tests

    @Test
    func codable_branch_roundTrip() throws {
        let original = GitRef.branch("main")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test
    func codable_tag_roundTrip() throws {
        let original = GitRef.tag("v1.0.0")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test
    func codable_revision_roundTrip() throws {
        let original = GitRef.revision("abc123def456")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    // MARK: - Value Property Tests

    @Test
    func value_branch_returnsName() {
        let ref = GitRef.branch("develop")
        #expect(ref.value == "develop")
    }

    @Test
    func value_tag_returnsName() {
        let ref = GitRef.tag("v2.0.0")
        #expect(ref.value == "v2.0.0")
    }

    @Test
    func value_revision_returnsSHA() {
        let ref = GitRef.revision("abc123")
        #expect(ref.value == "abc123")
    }
}
