@testable import EggKit
import Testing

@Suite("HatchReservedFlags.collisionWarnings")
struct HatchReservedFlagsTests {
    @Test("___OUTPUT___ collides with preview's built-in --output")
    func outputMacroCollidesWithPreviewFlag() {
        let warnings = HatchReservedFlags.collisionWarnings(for: [
            Config.Macro(name: "___OUTPUT___", description: "d", type: .path),
        ])
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("'--output'"))
        #expect(warnings[0].contains("egg hatch preview"))
    }

    @Test("boolean ___STAGING___ collides via its --no-staging false form")
    func booleanMacroCollidesViaNegatedForm() {
        let warnings = HatchReservedFlags.collisionWarnings(for: [
            Config.Macro(name: "___STAGING___", description: "d", type: .boolean),
        ])
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("'--no-staging'"))
        #expect(warnings[0].contains("egg hatch direct"))
    }

    @Test("a flag both commands claim names both in the warning")
    func sharedFlagNamesBothCommands() {
        let warnings = HatchReservedFlags.collisionWarnings(for: [
            Config.Macro(name: "___PROJECT_DIRECTORY___", description: "d", type: .string),
        ])
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("egg hatch preview"))
        #expect(warnings[0].contains("egg hatch direct"))
    }

    @Test("the scaffold's default macros are collision-free")
    func scaffoldDefaultsAreClean() {
        let warnings = HatchReservedFlags.collisionWarnings(for: [
            Config.Macro(name: "___FILE_NAME___", description: "d", type: .string),
            Config.Macro(name: "___OUTPUT_DIR___", description: "d", type: .string),
        ])
        #expect(warnings.isEmpty)
    }
}
