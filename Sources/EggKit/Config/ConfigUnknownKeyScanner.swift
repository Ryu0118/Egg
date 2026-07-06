import Foundation
import Yams

/// Finds config.yml keys the decoder would silently ignore.
///
/// `YAMLDecoder` skips unknown keys by design, so a typo like wrapping hooks
/// in a bogus `lifecycle:` section or misspelling `default` simply switches
/// the feature off with no signal. The scanner re-reads the raw YAML and
/// reports every key that no part of the schema understands, so `template
/// validate` can surface them as warnings.
///
/// The set of "known" keys at each level is derived from `Config`'s own
/// `CodingKeys` (`CaseIterable`, so this can't drift from the actual
/// `Decodable` implementation the way a hand-maintained key list would):
/// add a field to `Config` and its `CodingKeys` case, and the scanner picks
/// it up automatically with no change here.
package struct ConfigUnknownKeyScanner {
    package init() {}

    /// Warning strings for every unknown key in the YAML text, empty when
    /// the file is clean. Unparseable YAML yields no warnings — the decoder
    /// already fails loudly for that.
    package func unknownKeyWarnings(inYAML text: String) -> [String] {
        guard let root = (try? Yams.load(yaml: text)) as? [String: Any] else { return [] }
        var warnings: [String] = []

        reportUnknownKeys(in: root, knownKeys: Config.CodingKeys.self, context: "top-level", to: &warnings)

        appendUnknownKeysInEntries(root["macros"], knownKeys: Config.Macro.CodingKeys.self, context: "macros", to: &warnings)
        appendUnknownKeysInEntries(root["pre_hatch"], knownKeys: Config.LifecycleStep.CodingKeys.self, context: "pre_hatch", to: &warnings)
        appendUnknownKeysInEntries(root["post_hatch"], knownKeys: Config.LifecycleStep.CodingKeys.self, context: "post_hatch", to: &warnings)

        if let hatch = root["hatch"] as? [String: Any] {
            reportUnknownKeys(in: hatch, knownKeys: Config.HatchConfig.CodingKeys.self, context: "hatch", to: &warnings)
            if let excludes = hatch["exclude"] as? [Any] {
                for (index, rule) in excludes.enumerated() {
                    // A plain-string exclude rule (Config.ExcludeRule.path) has no
                    // keys to check; only the conditional-object form does.
                    guard let object = rule as? [String: Any] else { continue }
                    reportUnknownKeys(in: object, knownKeys: Config.ConditionalExclude.CodingKeys.self, context: "hatch.exclude[\(index)]", to: &warnings)
                }
            }
        }

        if let sandbox = root["sandbox"] as? [String: Any] {
            reportUnknownKeys(in: sandbox, knownKeys: Config.SandboxConfig.CodingKeys.self, context: "sandbox", to: &warnings)
        }

        return warnings
    }

    /// Warnings for `if` conditions the decoder silently swallowed.
    ///
    /// An unquoted leading `!` is a YAML *tag*, so `if: !___X___` decodes the
    /// condition as empty/absent — and since `LifecycleStep.if` is optional,
    /// the step silently runs unconditionally instead of failing validation.
    package func swallowedConditionWarnings(inYAML text: String) -> [String] {
        guard let root = (try? Yams.load(yaml: text)) as? [String: Any] else { return [] }
        var warnings: [String] = []

        for section in ["pre_hatch", "post_hatch"] {
            guard let entries = root[section] as? [Any] else { continue }
            for (index, entry) in entries.enumerated() {
                guard let object = entry as? [String: Any] else { continue }
                appendSwallowedConditionWarning(for: object, context: "\(section)[\(index)]", to: &warnings)
            }
        }

        if let hatch = root["hatch"] as? [String: Any], let excludes = hatch["exclude"] as? [Any] {
            for (index, rule) in excludes.enumerated() {
                guard let object = rule as? [String: Any] else { continue }
                appendSwallowedConditionWarning(for: object, context: "hatch.exclude[\(index)]", to: &warnings)
            }
        }

        return warnings
    }

    /// Flags an `if` key whose value didn't survive YAML parsing as a
    /// non-empty string — the condition is gone with no signal.
    private func appendSwallowedConditionWarning(for object: [String: Any], context: String, to warnings: inout [String]) {
        guard object.keys.contains("if") else { return }
        if (object["if"] as? String)?.isEmpty != false {
            warnings.append(
                "'if' in \(context) decodes as empty, so the condition is silently dropped. If the expression starts with '!', quote it (if: \"!___X___\") — unquoted, YAML reads '!' as a tag.",
            )
        }
    }

    private func appendUnknownKeysInEntries(
        _ section: Any?,
        knownKeys: (some CodingKey & CaseIterable).Type,
        context: String,
        to warnings: inout [String],
    ) {
        guard let entries = section as? [Any] else { return }
        for (index, entry) in entries.enumerated() {
            guard let object = entry as? [String: Any] else { continue }
            let label = (object["name"] as? String).map { "\(context)[\(index)] ('\($0)')" } ?? "\(context)[\(index)]"
            reportUnknownKeys(in: object, knownKeys: knownKeys, context: label, to: &warnings)
        }
    }

    private func reportUnknownKeys(
        in object: [String: Any],
        knownKeys: (some CodingKey & CaseIterable).Type,
        context: String,
        to warnings: inout [String],
    ) {
        let known = Set(knownKeys.allCases.map(\.stringValue))
        for key in object.keys.sorted() where !known.contains(key) {
            warnings.append("Unknown key '\(key)' in \(context) is ignored — egg only reads: \(known.sorted().joined(separator: ", ")).")
        }
    }
}
