import Foundation

/// Represents a lifecycle phase in the egg template workflow.
///
/// Lifecycle phases determine when steps are executed:
/// - `preHatch`: Before template expansion
/// - `postHatch`: After template expansion
enum LifecyclePhase: String, Sendable, CaseIterable {
    case preHatch = "pre_hatch"
    case postHatch = "post_hatch"
}
