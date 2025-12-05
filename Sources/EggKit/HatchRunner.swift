import Foundation

package actor HatchRunner {
    private let macros: [EggMacro]

    package init(macros: [EggMacro]) {
        self.macros = macros
    }

    package func run() async throws {
    }
}
