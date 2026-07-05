import Foundation
import Yams

/// Finds config.yml keys the decoder would silently ignore.
///
/// `YAMLDecoder` skips unknown keys by design, so a typo like wrapping hooks
/// in a bogus `lifecycle:` section or misspelling `default` simply switches
/// the feature off with no signal. The scanner re-reads the raw YAML and
/// reports every key that no part of the schema understands, so `template
/// validate` can surface them as warnings.
package struct ConfigUnknownKeyScanner {
    private static let topLevelKeys: Set<String> = [
        "name", "description", "version", "macros", "sandbox", "pre_hatch", "post_hatch", "hatch",
    ]
    private static let macroKeys: Set<String> = ["name", "description", "type", "default", "validate", "choices"]
    private static let stepKeys: Set<String> = ["id", "if", "run"]
    private static let hatchKeys: Set<String> = ["output", "exclude"]
    private static let sandboxKeys: Set<String> = ["allowed_paths"]
    private static let conditionalExcludeKeys: Set<String> = ["if", "paths"]

    package init() {}

    /// Warning strings for every unknown key in the YAML text, empty when
    /// the file is clean. Unparseable YAML yields no warnings — the decoder
    /// already fails loudly for that.
    package func unknownKeyWarnings(inYAML text: String) -> [String] {
        guard let root = (try? Yams.load(yaml: text)) as? [String: Any] else { return [] }
        var warnings: [String] = []

        for key in root.keys.sorted() where !Self.topLevelKeys.contains(key) {
            warnings.append("Unknown top-level key '\(key)' is ignored — egg only reads: \(Self.topLevelKeys.sorted().joined(separator: ", ")).")
        }

        appendUnknownKeys(in: root["macros"], known: Self.macroKeys, context: "macros", to: &warnings)
        appendUnknownKeys(in: root["pre_hatch"], known: Self.stepKeys, context: "pre_hatch", to: &warnings)
        appendUnknownKeys(in: root["post_hatch"], known: Self.stepKeys, context: "post_hatch", to: &warnings)

        if let hatch = root["hatch"] as? [String: Any] {
            for key in hatch.keys.sorted() where !Self.hatchKeys.contains(key) {
                warnings.append("Unknown key '\(key)' in hatch is ignored — egg only reads: \(Self.hatchKeys.sorted().joined(separator: ", ")).")
            }
            if let excludes = hatch["exclude"] as? [Any] {
                for (index, rule) in excludes.enumerated() {
                    guard let object = rule as? [String: Any] else { continue }
                    for key in object.keys.sorted() where !Self.conditionalExcludeKeys.contains(key) {
                        warnings.append("Unknown key '\(key)' in hatch.exclude[\(index)] is ignored — conditional rules only read: if, paths.")
                    }
                }
            }
        }

        if let sandbox = root["sandbox"] as? [String: Any] {
            for key in sandbox.keys.sorted() where !Self.sandboxKeys.contains(key) {
                warnings.append("Unknown key '\(key)' in sandbox is ignored — egg only reads: allowed_paths.")
            }
        }

        return warnings
    }

    private func appendUnknownKeys(in section: Any?, known: Set<String>, context: String, to warnings: inout [String]) {
        guard let entries = section as? [Any] else { return }
        for (index, entry) in entries.enumerated() {
            guard let object = entry as? [String: Any] else { continue }
            let label = (object["name"] as? String).map { "\(context)[\(index)] ('\($0)')" } ?? "\(context)[\(index)]"
            for key in object.keys.sorted() where !known.contains(key) {
                warnings.append("Unknown key '\(key)' in \(label) is ignored — egg only reads: \(known.sorted().joined(separator: ", ")).")
            }
        }
    }
}
