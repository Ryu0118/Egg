@testable import EggKit
import Foundation
import Testing

struct GitRefTests {
    @Test("equatable same branch are equal")
    func equatableSameBranchAreEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("main")
        #expect(ref1 == ref2)
    }

    @Test("equatable different branches are not equal")
    func equatableDifferentBranchesAreNotEqual() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("develop")
        #expect(ref1 != ref2)
    }

    @Test("equatable same tag are equal")
    func equatableSameTagAreEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v1.0.0")
        #expect(ref1 == ref2)
    }

    @Test("equatable different tags are not equal")
    func equatableDifferentTagsAreNotEqual() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v2.0.0")
        #expect(ref1 != ref2)
    }

    @Test("equatable same revision are equal")
    func equatableSameRevisionAreEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("abc123")
        #expect(ref1 == ref2)
    }

    @Test("equatable different revisions are not equal")
    func equatableDifferentRevisionsAreNotEqual() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("def456")
        #expect(ref1 != ref2)
    }

    @Test("equatable different types are not equal")
    func equatableDifferentTypesAreNotEqual() {
        let branch = GitRef.branch("main")
        let tag = GitRef.tag("main")
        let revision = GitRef.revision("main")

        #expect(branch != tag)
        #expect(branch != revision)
        #expect(tag != revision)
    }

    @Test("codable branch round trip")
    func codableBranchRoundTrip() throws {
        let original = GitRef.branch("main")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("codable tag round trip")
    func codableTagRoundTrip() throws {
        let original = GitRef.tag("v1.0.0")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("codable revision round trip")
    func codableRevisionRoundTrip() throws {
        let original = GitRef.revision("abc123def456")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test("value branch returns name")
    func valueBranchReturnsName() {
        let ref = GitRef.branch("develop")
        #expect(ref.value == "develop")
    }

    @Test("value tag returns name")
    func valueTagReturnsName() {
        let ref = GitRef.tag("v2.0.0")
        #expect(ref.value == "v2.0.0")
    }

    @Test("value revision returns SHA")
    func valueRevisionReturnsSHA() {
        let ref = GitRef.revision("abc123")
        #expect(ref.value == "abc123")
    }
}
