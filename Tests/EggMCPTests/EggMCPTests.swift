@testable import EggMCP
import Testing

@Suite("EggMCP module builds and exposes its public entry points")
struct EggMCPTests {
    @Test("EggMCP module can be imported and its public API compiles without linking errors")
    func eggMCPModuleIsImportable() {
        #expect(Bool(true))
    }

    @Test("Every declared tool has a registered handler, and vice versa")
    func everyDeclaredToolHasARegisteredHandler() async {
        let declared = Set(EggMCPServer.tools.map(\.name))
        let registered = await Set(ToolHandlerRegistry.shared.registeredToolNames)
        #expect(declared == registered)
        #expect(declared.contains("egg_hatch_transactions"))
    }
}
