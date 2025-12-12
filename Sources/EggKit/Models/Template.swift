import Foundation

package struct Template: Equatable {
    let path: URL
    let config: Config
    let isValid: Bool
}

struct Templates {
    let global: [Template]
    let project: [Template]
}
