import Foundation

package struct Template: Equatable {
    let path: URL
    let config: Config
    let isValid: Bool
}

struct Templates {
    let custom: [Template]
    let global: [Template]
    let project: [Template]

    init(custom: [Template] = [], global: [Template], project: [Template]) {
        self.custom = custom
        self.global = global
        self.project = project
    }

    var all: [Template] {
        custom + global + project
    }
}
