import Foundation

/// A strict Semantic Versioning 2.0.0 version (https://semver.org).
///
/// Used to resolve `from:`/`exact:` requirements in eggs.yml against Git tags.
/// Build metadata is preserved for display but ignored for precedence,
/// equality, and hashing (SemVer 2.0 §10).
package struct SemanticVersion: Hashable, CustomStringConvertible {
    package let major: Int
    package let minor: Int
    package let patch: Int
    package let prereleaseIdentifiers: [String]
    package let buildMetadataIdentifiers: [String]

    package init(
        major: Int,
        minor: Int,
        patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifiers: [String] = [],
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }

    /// Parses a strict SemVer 2.0 string. No `v` prefix is accepted here;
    /// use ``parse(tag:)`` for Git tag strings.
    package init?(_ string: String) {
        var remainder = Substring(string)

        var buildMetadataIdentifiers: [String] = []
        if let plusIndex = remainder.firstIndex(of: "+") {
            let metadata = remainder[remainder.index(after: plusIndex)...]
            remainder = remainder[..<plusIndex]
            buildMetadataIdentifiers = metadata.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard buildMetadataIdentifiers.allSatisfy(Self.isValidBuildIdentifier) else {
                return nil
            }
        }

        var prereleaseIdentifiers: [String] = []
        if let hyphenIndex = remainder.firstIndex(of: "-") {
            let prerelease = remainder[remainder.index(after: hyphenIndex)...]
            remainder = remainder[..<hyphenIndex]
            prereleaseIdentifiers = prerelease.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard prereleaseIdentifiers.allSatisfy(Self.isValidPrereleaseIdentifier) else {
                return nil
            }
        }

        let coreComponents = remainder.split(separator: ".", omittingEmptySubsequences: false)
        guard coreComponents.count == 3 else {
            return nil
        }

        let numbers = coreComponents.compactMap(Self.parseNumericComponent)
        guard numbers.count == 3 else {
            return nil
        }

        self.init(
            major: numbers[0],
            minor: numbers[1],
            patch: numbers[2],
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildMetadataIdentifiers: buildMetadataIdentifiers,
        )
    }

    /// Parses a Git tag string, tolerating a single leading `v` (e.g. `v1.2.3`).
    ///
    /// - Returns: The parsed version and whether the tag carried a `v` prefix,
    ///   or `nil` for tags that are not strict SemVer (those are silently
    ///   ignored by range resolution).
    package static func parse(tag: String) -> (version: SemanticVersion, hadVPrefix: Bool)? {
        if tag.hasPrefix("v") {
            guard let version = SemanticVersion(String(tag.dropFirst())) else {
                return nil
            }
            return (version, true)
        }
        guard let version = SemanticVersion(tag) else {
            return nil
        }
        return (version, false)
    }

    package var isPrerelease: Bool {
        !prereleaseIdentifiers.isEmpty
    }

    /// The canonical representation without a `v` prefix.
    package var description: String {
        var result = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            result += "-\(prereleaseIdentifiers.joined(separator: "."))"
        }
        if !buildMetadataIdentifiers.isEmpty {
            result += "+\(buildMetadataIdentifiers.joined(separator: "."))"
        }
        return result
    }

    // MARK: - Range membership

    /// Whether this version satisfies `from: lowerBound` (SwiftPM
    /// `.upToNextMajor` semantics): `lowerBound ..< (lowerBound.major + 1).0.0`,
    /// excluding prereleases unless the lower bound itself is a prerelease.
    package func satisfies(upToNextMajorFrom lowerBound: SemanticVersion) -> Bool {
        if isPrerelease, !lowerBound.isPrerelease {
            return false
        }
        let upperBound = SemanticVersion(major: lowerBound.major + 1, minor: 0, patch: 0)
        return self >= lowerBound && self < upperBound
    }

    // MARK: - Component validation

    private static func parseNumericComponent(_ component: Substring) -> Int? {
        guard !component.isEmpty, component.allSatisfy(\.isASCIIDigit) else {
            return nil
        }
        // SemVer forbids leading zeros in numeric identifiers ("01" is invalid, "0" is fine).
        guard component.count == 1 || component.first != "0" else {
            return nil
        }
        return Int(component)
    }

    private static func isValidPrereleaseIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.allSatisfy(\.isSemVerIdentifierCharacter) else {
            return false
        }
        if identifier.allSatisfy(\.isASCIIDigit) {
            return identifier.count == 1 || identifier.first != "0"
        }
        return true
    }

    private static func isValidBuildIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy(\.isSemVerIdentifierCharacter)
    }
}

// MARK: - Equatable / Hashable (build metadata ignored, SemVer 2.0 §10)

package extension SemanticVersion {
    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prereleaseIdentifiers)
    }
}

// MARK: - Comparable (SemVer 2.0 §11 precedence)

extension SemanticVersion: Comparable {
    package static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A prerelease has lower precedence than the associated release.
        return switch (lhs.isPrerelease, rhs.isPrerelease) {
        case (false, _): false
        case (true, false): true
        case (true, true): comparePrereleaseIdentifiers(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers)
        }
    }

    private static func comparePrereleaseIdentifiers(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) {
            if left == right {
                continue
            }
            let leftNumber = numericIdentifierValue(left)
            let rightNumber = numericIdentifierValue(right)
            return switch (leftNumber, rightNumber) {
            case let (.some(leftValue), .some(rightValue)): leftValue < rightValue
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): left < right
            }
        }
        // All shared identifiers equal: the shorter set has lower precedence.
        return lhs.count < rhs.count
    }

    private static func numericIdentifierValue(_ identifier: String) -> Int? {
        guard identifier.allSatisfy(\.isASCIIDigit) else {
            return nil
        }
        return Int(identifier)
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }

    var isSemVerIdentifierCharacter: Bool {
        isASCIIDigit || (isASCII && isLetter) || self == "-"
    }
}
