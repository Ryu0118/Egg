@testable import EggKit
import Foundation
import Testing

struct MacroResolverTests {
    private func makeResolver(macro: Config.Macro) -> MacroResolver {
        let config = Config(
            name: "Test",
            description: "Test template",
            macros: [macro],
            hatch: Config.HatchConfig(output: "."),
        )
        return MacroResolver(
            config: config,
            workingDirectory: URL(filePath: "/Users/test/projects"),
            homeDirectory: URL(filePath: "/Users/test"),
            interaction: TestInteraction(),
        )
    }

    /// A `choice` macro with no `choices` list used to crash the whole process
    /// via `fatalError`. It must now surface a recoverable thrown error before
    /// any prompt is attempted.
    @Test
    func choiceMacroWithoutChoicesThrows() async throws {
        let resolver = makeResolver(
            macro: Config.Macro(name: "___MODE___", description: "Mode", type: .choice),
        )

        await #expect(throws: MacroResolver.Error.choiceTypeRequiresChoices(macro: "___MODE___")) {
            try await resolver.resolve()
        }
    }

    @Test
    func choicesMacroWithoutChoicesThrows() async throws {
        let resolver = makeResolver(
            macro: Config.Macro(name: "___FEATURES___", description: "Features", type: .choices),
        )

        await #expect(throws: MacroResolver.Error.choiceTypeRequiresChoices(macro: "___FEATURES___")) {
            try await resolver.resolve()
        }
    }

    @Test
    func choiceMacroWithEmptyChoicesThrows() async throws {
        let resolver = makeResolver(
            macro: Config.Macro(name: "___MODE___", description: "Mode", type: .choice, choices: []),
        )

        await #expect(throws: MacroResolver.Error.choiceTypeRequiresChoices(macro: "___MODE___")) {
            try await resolver.resolve()
        }
    }
}
