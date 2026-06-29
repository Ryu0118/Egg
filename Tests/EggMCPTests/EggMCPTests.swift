@testable import EggMCP
import Testing

@Suite("EggMCP")
struct EggMCPTests {
    @Test
    func `EggMCP module is importable`() {
        #expect(Bool(true))
    }
}
