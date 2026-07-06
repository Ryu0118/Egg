@testable import EggKit
import Testing
import Yams

/// The formatter must name the failing key path — Foundation's raw
/// DecodingError messages ("The data couldn't be read because it is
/// missing.") give a template author nothing to act on.
@Suite("ConfigDecodingErrorFormatter")
struct ConfigDecodingErrorFormatterTests {
    private func decodeFailureMessage(_ yaml: String) -> String {
        do {
            _ = try YAMLDecoder().decode(Config.self, from: yaml)
            Issue.record("expected decode to fail")
            return ""
        } catch {
            return ConfigDecodingErrorFormatter.message(for: error)
        }
    }

    @Test("a missing required key is reported by its key path")
    func missingKeyNamesThePath() {
        let message = decodeFailureMessage("name: T\ndescription: d\nhatch: {}")
        #expect(message.contains("hatch.output"))
        #expect(message.contains("missing required key"))
    }

    @Test("a missing top-level key is reported by name")
    func missingTopLevelKeyNamesIt() {
        let message = decodeFailureMessage("name: T\ndescription: d")
        #expect(message.contains("hatch"))
        #expect(message.contains("missing required key"))
    }

    @Test("a wrong-typed nested value is reported with its indexed key path")
    func typeMismatchNamesIndexedPath() {
        let yaml = """
        name: T
        description: d
        macros:
          - name: ___A___
            description: a
            type: choice
            choices: notAnArray
        hatch:
          output: .
        """
        let message = decodeFailureMessage(yaml)
        #expect(message.contains("macros[0].choices"))
    }

    @Test("unparseable YAML is reported as invalid YAML, not a generic read failure")
    func syntaxErrorSaysInvalidYAML() {
        let message = decodeFailureMessage("name: [unclosed")
        #expect(message.contains("invalid YAML"))
        #expect(!message.contains("couldn't be read"))
    }
}
