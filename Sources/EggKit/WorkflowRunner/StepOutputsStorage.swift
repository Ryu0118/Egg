import Foundation

/// In-memory storage for lifecycle step outputs.
///
/// Stores key-value outputs from shell script execution, keyed by phase and step ID.
/// Supports cross-phase access (e.g., post_hatch can access pre_hatch outputs).
///
/// Storage format: `[phase.stepId: [key: value]]`
///
/// Example:
/// ```
/// {
///   "pre_hatch.setup": {
///     "version": "1.0.0",
///     "src-dir": "/tmp/src"
///   }
/// }
/// ```
actor StepOutputsStorage {
    private var storage: [String: [String: String]] = [:]

    init() {}

    /// Stores outputs for a specific step in a phase.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase
    ///   - stepId: The step identifier
    ///   - outputs: Dictionary of key-value pairs to store
    func store(phase: LifecyclePhase, stepId: String, outputs: [String: String]) {
        let key = makeKey(phase: phase, stepId: stepId)
        storage[key] = outputs
    }

    /// Retrieves a specific output value.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase
    ///   - stepId: The step identifier
    ///   - key: The output key
    /// - Returns: The output value if it exists, nil otherwise
    func get(phase: LifecyclePhase, stepId: String, key: String) -> String? {
        let storageKey = makeKey(phase: phase, stepId: stepId)
        return storage[storageKey]?[key]
    }

    /// Checks if a specific output exists.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase
    ///   - stepId: The step identifier
    ///   - key: The output key
    /// - Returns: true if the output exists, false otherwise
    func has(phase: LifecyclePhase, stepId: String, key: String) -> Bool {
        get(phase: phase, stepId: stepId, key: key) != nil
    }

    /// Returns all stored outputs as a nested dictionary for Stencil context.
    ///
    /// Returns:
    /// ```
    /// {
    ///   "pre_hatch": {
    ///     "setup": {
    ///       "outputs": {
    ///         "version": "1.0.0"
    ///       }
    ///     }
    ///   }
    /// }
    /// ```
    func allOutputsForStencil() -> [String: [String: [String: [String: String]]]] {
        var result: [String: [String: [String: [String: String]]]] = [:]

        for (key, outputs) in storage {
            let components = key.split(separator: ".", maxSplits: 1)
            guard components.count == 2 else { continue }

            let phase = String(components[0])
            let stepId = String(components[1])

            if result[phase] == nil {
                result[phase] = [:]
            }
            result[phase]![stepId] = ["outputs": outputs]
        }

        return result
    }

    private func makeKey(phase: LifecyclePhase, stepId: String) -> String {
        "\(phase.rawValue).\(stepId)"
    }
}
