@testable import EggKit
import FileManagerProtocol
import Foundation
import Interaction
import ProcessRunning
import Synchronization
import Testing

/// What lifecycle scripts print has to reach whoever is hatching: a human
/// through the terminal, an agent through `AgentHatchPreviewResult`.
///
/// Both halves used to be governed by one `isInteractive` flag, which meant
/// `egg hatch direct` silently swallowed script output and the agent
/// transaction flow had nowhere to put it at all. These tests pin the split
/// and the capture.
@Suite("Lifecycle script stdout reaches both humans and agents")
struct LifecycleScriptOutputTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    // MARK: - Capture in the agent transaction flow

    @Test("Preview surfaces what pre_hatch and post_hatch steps printed, tagged by phase, index and id")
    func previewSurfacesScriptOutputFromBothPhases() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let result = try await makeRunner(
            workspace: workspace,
            preHatch: [Config.LifecycleStep(id: "greet", run: "echo hello-from-pre")],
            postHatch: [Config.LifecycleStep(run: "echo hello-from-post")],
        ).preview()

        let pre = try #require(result.scriptOutput.first { $0.phase == "pre_hatch" })
        #expect(pre.index == 0)
        #expect(pre.id == "greet")
        #expect(pre.stdout.contains("hello-from-pre"))
        #expect(!pre.skipped)
        #expect(!pre.truncated)

        let post = try #require(result.scriptOutput.first { $0.phase == "post_hatch" })
        #expect(post.index == 0)
        #expect(post.id == nil)
        #expect(post.stdout.contains("hello-from-post"))
    }

    /// The `hatch` phase is pure template expansion — `LifecyclePhase` has no
    /// case for it — so a template with no script steps yields no entries,
    /// rather than empty placeholders an agent would have to filter out.
    @Test("A template with no lifecycle steps yields an empty scriptOutput rather than placeholder entries")
    func templateWithoutStepsYieldsNoEntries() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let result = try await makeRunner(workspace: workspace).preview()

        #expect(result.scriptOutput.isEmpty)
    }

    @Test("A step skipped by its if: condition is reported as skipped, so silence is distinguishable from not running")
    func skippedStepIsReportedAsSkipped() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let result = try await makeRunner(
            workspace: workspace,
            postHatch: [
                Config.LifecycleStep(id: "never", if: "false", run: "echo unreachable"),
                Config.LifecycleStep(id: "silent", run: "true"),
            ],
        ).preview()

        let skipped = try #require(result.scriptOutput.first { $0.id == "never" })
        #expect(skipped.skipped)
        #expect(skipped.stdout.isEmpty)

        // A step that ran but printed nothing is *not* skipped: an agent can
        // tell "this did nothing" from "this never happened".
        let silent = try #require(result.scriptOutput.first { $0.id == "silent" })
        #expect(!silent.skipped)
        #expect(silent.stdout.isEmpty)
    }

    @Test("Output beyond the per-step byte limit is cut and flagged, keeping the leading bytes")
    func oversizedOutputIsTruncated() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        // Comfortably past the 64 KB cap. The marker is printed first so the
        // assertion also proves the *beginning* is what survives — where a
        // template author's message lives, ahead of any build noise.
        let result = try await makeRunner(
            workspace: workspace,
            postHatch: [Config.LifecycleStep(
                id: "noisy",
                run: "echo LEADING-MARKER; head -c 70000 /dev/zero | tr '\\0' x",
            )],
        ).preview()

        let entry = try #require(result.scriptOutput.first { $0.id == "noisy" })
        #expect(entry.truncated)
        #expect(entry.stdout.utf8.count == LifecycleScriptOutput.byteLimit)
        #expect(entry.stdout.hasPrefix("LEADING-MARKER"))
    }

    // MARK: - Progress flag split

    @Test("A non-interactive run that does not own stdout still prints script output")
    func nonInteractiveRunStillPrintsScriptOutput() async throws {
        let interaction = RecordingInteraction()
        let workingDirectory = try fileManager.makeTemporaryDirectory(prefix: "LifecycleScriptOutputTests")
        defer { try? fileManager.removeItem(at: workingDirectory) }

        // This is `egg hatch direct`'s configuration: it cannot prompt, but
        // nothing else is claiming stdout.
        try await makePhaseRunner(
            interaction: interaction,
            isInteractive: false,
            suppressHumanProgress: false,
        ).executePostHatch(
            steps: [Config.LifecycleStep(run: "echo visible-to-humans")],
            macros: [],
            outputs: StepOutputsStorage(),
            workingDirectory: workingDirectory,
        )

        #expect(interaction.lines.contains { $0.contains("visible-to-humans") })
    }

    @Test("Suppressing human progress hides script output from stdout while the collector still receives it")
    func suppressedRunKeepsOutputOutOfStdoutButNotOutOfTheCollector() async throws {
        let interaction = RecordingInteraction()
        let workingDirectory = try fileManager.makeTemporaryDirectory(prefix: "LifecycleScriptOutputTests")
        defer { try? fileManager.removeItem(at: workingDirectory) }
        let collector = LifecycleScriptOutputCollector()

        // This is the agent transaction flow's configuration.
        try await makePhaseRunner(
            interaction: interaction,
            isInteractive: false,
            suppressHumanProgress: true,
        ).executePostHatch(
            steps: [Config.LifecycleStep(run: "echo reserved-for-json")],
            macros: [],
            outputs: StepOutputsStorage(),
            workingDirectory: workingDirectory,
            outputCollector: collector,
        )

        #expect(!interaction.lines.contains { $0.contains("reserved-for-json") })
        let collected = await collector.drain()
        #expect(collected.contains { $0.stdout.contains("reserved-for-json") })
    }

    // MARK: - Failure

    /// The failure path is where script output matters most, and it is also
    /// the one path with no result object to attach it to — a throwing
    /// `runWorkflow` never reaches the collector's drain. The error itself
    /// has to carry it, and the CLI renders errors by `localizedDescription`
    /// alone, so that description is the payload.
    @Test("A preview whose step exits non-zero reports what that step printed in the error itself")
    func failingPreviewReportsScriptOutputInTheError() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let error = await #expect(throws: LifecycleStepError.self) {
            try await makeRunner(
                workspace: workspace,
                postHatch: [Config.LifecycleStep(
                    id: "doomed",
                    run: "echo IMPORTANT-DIAGNOSTIC; exit 3",
                )],
            ).preview()
        }

        let description = try #require(error?.localizedDescription)
        #expect(description.contains("IMPORTANT-DIAGNOSTIC"))
    }

    @Test("A step that exits non-zero still hands back what it printed before failing")
    func failingStepRetainsItsPartialOutput() async throws {
        let workingDirectory = try fileManager.makeTemporaryDirectory(prefix: "LifecycleScriptOutputTests")
        defer { try? fileManager.removeItem(at: workingDirectory) }
        let collector = LifecycleScriptOutputCollector()

        await #expect(throws: LifecycleStepError.self) {
            try await makePhaseRunner(
                interaction: RecordingInteraction(),
                isInteractive: false,
                suppressHumanProgress: true,
            ).executePostHatch(
                steps: [Config.LifecycleStep(id: "doomed", run: "echo printed-before-failing; exit 3")],
                macros: [],
                outputs: StepOutputsStorage(),
                workingDirectory: workingDirectory,
                outputCollector: collector,
            )
        }

        let collected = await collector.drain()
        let entry = try #require(collected.first { $0.id == "doomed" })
        #expect(entry.stdout.contains("printed-before-failing"))
    }

    // MARK: - Helpers

    private func makePhaseRunner(
        interaction: RecordingInteraction,
        isInteractive: Bool,
        suppressHumanProgress: Bool,
    ) -> PhaseRunner {
        PhaseRunner(
            processRunner: ProcessRunner(),
            fileManager: fileManager,
            homeDirectory: URL(filePath: NSTemporaryDirectory()),
            interaction: interaction,
            isInteractive: isInteractive,
            suppressHumanProgress: suppressHumanProgress,
            override: true,
        )
    }

    private func makeWorkspace() throws -> Workspace {
        let root = try fileManager.makeTemporaryDirectory(prefix: "LifecycleScriptOutputTests")
        let workingDirectory = root.appending(path: "work")
        let homeDirectory = root.appending(path: "home")
        let templateDirectory = root.appending(path: "template")
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateDirectory, withIntermediateDirectories: true)
        try initializeGitRepository(at: workingDirectory)
        try fileManager.writeText("generated\n", at: templateDirectory.appending(path: "Generated.txt"))
        return Workspace(
            root: root,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            templateDirectory: templateDirectory,
        )
    }

    private func makeRunner(
        workspace: Workspace,
        preHatch: [Config.LifecycleStep]? = nil,
        postHatch: [Config.LifecycleStep]? = nil,
    ) -> AgentHatchTransactionRunner {
        AgentHatchTransactionRunner(
            processRunner: ProcessRunner(),
            fileManager: fileManager,
            workingDirectory: workspace.workingDirectory,
            homeDirectory: workspace.homeDirectory,
            templateDirectory: workspace.templateDirectory,
            config: Config(
                name: "ScriptOutputTemplate",
                description: "Script output template",
                preHatch: preHatch,
                hatch: .init(output: "."),
                postHatch: postHatch,
            ),
            parsedMacros: [],
            // The sandbox is irrelevant to what these tests assert, and
            // disabling it keeps them off the consent path.
            sandboxDisabled: true,
        )
    }

    private func initializeGitRepository(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "--quiet"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitInitializationError.failed(status: process.terminationStatus)
        }
    }

    private struct Workspace {
        let root: URL
        let workingDirectory: URL
        let homeDirectory: URL
        let templateDirectory: URL
    }

    private enum GitInitializationError: Error {
        case failed(status: Int32)
    }
}

/// Captures what a runner writes, so tests can assert on stdout-bound text
/// without a terminal. Prompts are still a setup bug, as in `TestInteraction`.
private final class RecordingInteraction: InteractionProviding {
    private let recorded = Mutex<[String]>([])

    var lines: [String] {
        recorded.withLock(\.self)
    }

    func write(_ text: StyledText) {
        recorded.withLock { $0.append(text.plainText) }
    }

    func writeStatus(_: Status, _ message: StyledText) {
        recorded.withLock { $0.append(message.plainText) }
    }

    func writeTable(_: Table) {}

    func readText(_: TextPrompt) async -> String {
        preconditionFailure("RecordingInteraction.readText was called without a configured answer.")
    }

    func confirm(_: ConfirmationPrompt) -> Bool {
        preconditionFailure("RecordingInteraction.confirm was called without a configured answer.")
    }

    func choose<Option>(_: ChoicePrompt<Option>) -> Option {
        preconditionFailure("RecordingInteraction.choose was called without a configured answer.")
    }

    func chooseMany<Option>(_: MultipleChoicePrompt<Option>) -> [Option] {
        preconditionFailure("RecordingInteraction.chooseMany was called without a configured answer.")
    }
}
