import Foundation

struct Config: Codable {
    let postUseHook: String?

    enum CodingKeys: String, CodingKey {
        case postUseHook = "post_use_hook"
    }
}

