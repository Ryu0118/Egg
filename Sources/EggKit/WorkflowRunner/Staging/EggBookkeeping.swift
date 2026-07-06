import Foundation

/// The name of egg's own bookkeeping directory (`.egg/transactions`,
/// `.egg/rollback`), excluded from every staging clone the way git excludes
/// `.git` from its own operations.
///
/// The exclusion is checked against several different shapes — a top-level
/// entry name, a git-relative path string, an enumerator `URL`, a gitignore
/// glob line — so this is a single named constant, not a shared predicate:
/// each call site matches it in whatever form that site already works in.
enum EggBookkeeping {
    static let directoryName = ".egg"
}
