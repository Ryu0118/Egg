@testable import EggMCP
import Testing

@Suite("EggMCP module builds and exposes its public entry points")
struct EggMCPTests {
    @Test("EggMCP module can be imported and its public API compiles without linking errors")
    func eggMCPModuleIsImportable() {
        #expect(Bool(true))
    }
}
