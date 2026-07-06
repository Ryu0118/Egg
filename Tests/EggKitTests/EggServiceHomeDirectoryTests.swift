@testable import EggKit
import Foundation
import Testing

/// `EggService.init` falls back to `Self.resolveHomeDirectory()` when no
/// `homeDirectory` is given — every MCP handler constructs `EggService` this
/// way. If this fell back to `FileManager.default.homeDirectoryForCurrentUser`
/// instead, an overridden `HOME` (tests, CI, sandboxes) would make the CLI
/// (which always passes `CLIEnvironment.resolveHomeDirectory()`) and MCP
/// resolve different `~/.eggs` directories for global templates.
///
/// `.serialized`: both tests mutate the process-wide `HOME` environment
/// variable, which would race under swift-testing's default parallel
/// execution.
@Suite("EggService home directory resolution honors HOME", .serialized)
struct EggServiceHomeDirectoryTests {
    @Test("resolveHomeDirectory reads HOME when set")
    func resolvesFromEnvironment() {
        // setenv/unsetenv directly, since ProcessInfo.environment is a live
        // snapshot of the process environment on Darwin/Linux.
        let original = ProcessInfo.processInfo.environment["HOME"]
        defer {
            if let original {
                setenv("HOME", original, 1)
            } else {
                unsetenv("HOME")
            }
        }
        setenv("HOME", "/tmp/fake-home-for-test", 1)

        #expect(EggService.resolveHomeDirectory().path(percentEncoded: false) == "/tmp/fake-home-for-test")
    }

    @Test("a service constructed with no explicit homeDirectory still honors HOME")
    func serviceDefaultHonorsHOME() {
        let original = ProcessInfo.processInfo.environment["HOME"]
        defer {
            if let original {
                setenv("HOME", original, 1)
            } else {
                unsetenv("HOME")
            }
        }
        setenv("HOME", "/tmp/fake-home-for-service-test", 1)

        // Mirrors how every MCP handler constructs EggService: no
        // homeDirectory argument at all.
        let service = EggService(workingDirectory: URL(filePath: "/tmp"))
        let mirror = Mirror(reflecting: service)
        let resolvedHome = mirror.children.first { $0.label == "homeDirectory" }?.value as? URL

        #expect(resolvedHome?.path(percentEncoded: false) == "/tmp/fake-home-for-service-test")
    }
}
