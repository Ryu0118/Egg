@testable import EggKit
import Foundation
import Testing

struct GitRefTests {
    @Test
    func `equatable same branch are equal`() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("main")
        #expect(ref1 == ref2)
    }

    @Test
    func `equatable different branches are not equal`() {
        let ref1 = GitRef.branch("main")
        let ref2 = GitRef.branch("develop")
        #expect(ref1 != ref2)
    }

    @Test
    func `equatable same tag are equal`() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v1.0.0")
        #expect(ref1 == ref2)
    }

    @Test
    func `equatable different tags are not equal`() {
        let ref1 = GitRef.tag("v1.0.0")
        let ref2 = GitRef.tag("v2.0.0")
        #expect(ref1 != ref2)
    }

    @Test
    func `equatable same revision are equal`() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("abc123")
        #expect(ref1 == ref2)
    }

    @Test
    func `equatable different revisions are not equal`() {
        let ref1 = GitRef.revision("abc123")
        let ref2 = GitRef.revision("def456")
        #expect(ref1 != ref2)
    }

    @Test
    func `equatable different types are not equal`() {
        let branch = GitRef.branch("main")
        let tag = GitRef.tag("main")
        let revision = GitRef.revision("main")

        #expect(branch != tag)
        #expect(branch != revision)
        #expect(tag != revision)
    }

    @Test
    func `codable branch round trip`() throws {
        let original = GitRef.branch("main")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test
    func `codable tag round trip`() throws {
        let original = GitRef.tag("v1.0.0")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test
    func `codable revision round trip`() throws {
        let original = GitRef.revision("abc123def456")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitRef.self, from: encoded)
        #expect(original == decoded)
    }

    @Test
    func `value branch returns name`() {
        let ref = GitRef.branch("develop")
        #expect(ref.value == "develop")
    }

    @Test
    func `value tag returns name`() {
        let ref = GitRef.tag("v2.0.0")
        #expect(ref.value == "v2.0.0")
    }

    @Test
    func `value revision returns SHA`() {
        let ref = GitRef.revision("abc123")
        #expect(ref.value == "abc123")
    }
}
