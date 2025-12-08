import Path

package struct Template: Equatable {
    let path: AbsolutePath
    let config: Config
    let isValid: Bool
}

struct Templates {
    let global: [Template]
    let project: [Template]
}
