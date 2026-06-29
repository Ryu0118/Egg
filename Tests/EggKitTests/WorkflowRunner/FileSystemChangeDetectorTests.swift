@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct FileSystemChangeDetectorTests {
    @Test
    func `detects added modified and deleted files`() throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let root = try fileManager.makeTemporaryDirectory(prefix: "FileSystemChangeDetectorTests")
        defer { try? fileManager.removeItem(at: root) }

        let reference = root.appending(path: "reference")
        let changed = root.appending(path: "changed")
        try fileManager.createDirectory(at: reference, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: changed, withIntermediateDirectories: true)

        try write("same", to: reference.appending(path: "same.txt"), fileManager: fileManager)
        try write("same", to: changed.appending(path: "same.txt"), fileManager: fileManager)
        try write("old", to: reference.appending(path: "modified.txt"), fileManager: fileManager)
        try write("new", to: changed.appending(path: "modified.txt"), fileManager: fileManager)
        try write("delete", to: reference.appending(path: "deleted.txt"), fileManager: fileManager)
        try write("add", to: changed.appending(path: "added.txt"), fileManager: fileManager)

        let summary = try FileSystemChangeDetector(fileManager: fileManager)
            .computeChanges(referenceRoot: reference, changedRoot: changed)

        #expect(summary.added == ["added.txt"])
        #expect(summary.modified == ["modified.txt"])
        #expect(summary.deleted == ["deleted.txt"])
    }

    @Test
    func `ignores generated artifact directories`() throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let root = try fileManager.makeTemporaryDirectory(prefix: "FileSystemChangeDetectorTests")
        defer { try? fileManager.removeItem(at: root) }

        let reference = root.appending(path: "reference")
        let changed = root.appending(path: "changed")
        try fileManager.createDirectory(at: reference, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: changed, withIntermediateDirectories: true)
        try write("source", to: reference.appending(path: "Sources/App.swift"), fileManager: fileManager)
        try write("source", to: changed.appending(path: "Sources/App.swift"), fileManager: fileManager)
        try write("module", to: changed.appending(path: "node_modules/pkg/index.js"), fileManager: fileManager)
        try write("build", to: changed.appending(path: ".build/debug/app"), fileManager: fileManager)

        let summary = try FileSystemChangeDetector(fileManager: fileManager)
            .computeChanges(referenceRoot: reference, changedRoot: changed)

        #expect(summary.isEmpty)
    }

    private func write(_ text: String, to url: URL, fileManager: any FileManagerProtocol) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.exists(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fileManager.writeText(text, at: url)
    }
}
