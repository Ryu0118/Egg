@testable import EggMCP
import Testing

@Suite("EggMCP module builds and exposes its public entry points")
struct EggMCPTests {
    @Test("EggMCP module is importable")
    func eggMCPModuleIsImportable() {
        #expect(Bool(true))
    }
}
