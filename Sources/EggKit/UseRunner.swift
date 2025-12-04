import Foundation

package actor UseRunner {
    private let macros: [EggMacro]

    package init(macros: [EggMacro]) {
        self.macros = macros
    }

    package func run() async throws {
    }
}
