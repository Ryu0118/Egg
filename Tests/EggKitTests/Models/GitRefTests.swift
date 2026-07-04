@testable import EggKit
import Foundation
import Testing

struct GitRefTests {
    @Test("two GitRef.branch values with the same branch name compare equal")
    func equatableSameBranchAreEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("main")
        #expect(ref1 == ref2)
    }

    @Test("two GitRef.branch values with different branch names compare unequal")
    func equatableDifferentBranchesAreNotEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("develop")
        #expect(ref1 != ref2)
    }

    @Test("two GitRef.tag values with the same tag name compare equal")
    func equatableSameTagAreEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v1.0.0")
        #expect(ref1 == ref2)
    }

    @Test("two GitRef.tag values with different tag names compare unequal")
    func equatableDifferentTagsAreNotEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v2.0.0")
        #expect(ref1 != ref2)
    }

    @Test("two GitRef.revision values with the same SHA compare equal")
    func equatableSameRevisionAreEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("abc123")
        #expect(ref1 == ref2)
    }

    @Test("two GitRef.revision values with different SHAs compare unequal")
    func equatableDifferentRevisionsAreNotEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("def456")
        #expect(ref1 != ref2)
    }

    @Test("branch, tag, and revision cases built from the identical underlying string never compare equal to each other")
    func equatableDifferentTypesAreNotEqual() {
        let branch = GitRef.branch("main")
        let tag = GitRef.tag("main")
        let revision = GitRef.revision("main")

        #expect(branch != tag)
        #expect(branch != revision)
        #expect(tag != revision)
    }

    @Test("a GitRef.branch value survives JSON encoding and decoding unchanged")
    func codableBranchRoundTrip() throws {
        let original = GitRef.branch("main")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("a GitRef.tag value survives JSON encoding and decoding unchanged")
    func codableTagRoundTrip() throws {
        let original = GitRef.tag("v1.0.0")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("a GitRef.revision value survives JSON encoding and decoding unchanged")
    func codableRevisionRoundTrip() throws {
        let original = GitRef.revision("abc123def456")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("value returns the branch name for a GitRef.branch")
    func valueBranchReturnsName() {
        let ref = GitRef.branch("develop")
        #expect(ref.value == "develop")
    }

    @Test("value returns the tag name for a GitRef.tag")
    func valueTagReturnsName() {
        let ref = GitRef.tag("v2.0.0")
        #expect(ref.value == "v2.0.0")
    }

    @Test("value returns the commit SHA for a GitRef.revision")
    func valueRevisionReturnsSHA() {
        let ref = GitRef.revision("abc123")
        #expect(ref.value == "abc123")
    }
}
