import Foundation

/// Model representing template configuration
package struct Config: Codable, Equatable {
    /// Template display name
    package let name: String
    
    /// Template description
    package let description: String
    
    /// Template version (optional)
    package let version: String?
    
    /// Macro definitions (user input)
    package let macros: [Macro]?
    
    /// Lifecycle hooks before template expansion
    package let preHatch: [LifecycleStep]?
    
    /// Template expansion configuration
    package let hatch: HatchConfig?
    
    /// Lifecycle hooks after template expansion
    package let postHatch: [LifecycleStep]?
    
    package init(
        name: String,
        description: String,
        version: String? = nil,
        macros: [Macro]? = nil,
        preHatch: [LifecycleStep]? = nil,
        hatch: HatchConfig? = nil,
        postHatch: [LifecycleStep]? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.macros = macros
        self.preHatch = preHatch
        self.hatch = hatch
        self.postHatch = postHatch
    }
    
    package enum CodingKeys: String, CodingKey {
        case name
        case description
        case version
        case macros
        case preHatch = "pre_hatch"
        case hatch
        case postHatch = "post_hatch"
    }
}

// MARK: - Macro

/// Macro definition (user input)
package struct Macro: Codable, Equatable {
    /// Macro name (e.g., `___MODULE_NAME___`)
    package let name: String
    
    /// Macro description
    package let description: String
    
    /// Macro type (default: `.string`)
    package let type: MacroType
    
    /// Default value (optional)
    package let `default`: String?
    
    /// Regular expression for validation (optional)
    package let validate: String?
    
    /// Choices (used for choice or array type)
    package let choices: [String]?
    
    package init(
        name: String,
        description: String,
        type: MacroType = .string,
        default: String? = nil,
        validate: String? = nil,
        choices: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.default = `default`
        self.validate = validate
        self.choices = choices
    }
}

/// Macro type
package enum MacroType: String, Codable {
    case string
    case boolean
    case choice
    case array
    case path
}

// MARK: - LifecycleStep

/// Lifecycle hook step (used in pre_hatch/post_hatch)
package struct LifecycleStep: Codable, Equatable {
    /// Step ID (optional, used for step outputs)
    package let id: String?
    
    /// Conditional expression (optional, evaluated as JavaScript expression)
    package let `if`: String?
    
    /// Shell command to execute (optional)
    package let run: String?
    
    package init(
        id: String? = nil,
        if: String? = nil,
        run: String? = nil
    ) {
        self.id = id
        self.if = `if`
        self.run = run
    }
}

// MARK: - HatchConfig

/// Template expansion configuration
package struct HatchConfig: Codable, Equatable {
    /// Output directory (supports macros and step outputs)
    package let output: String
    
    /// Exclusion rules (optional)
    package let exclude: [ExcludeRule]?
    
    package init(
        output: String,
        exclude: [ExcludeRule]? = nil
    ) {
        self.output = output
        self.exclude = exclude
    }
}

/// Exclusion rule (string or conditional object)
package enum ExcludeRule: Codable, Equatable {
    /// Unconditionally exclude path (glob pattern)
    case path(String)
    
    /// Conditionally exclude paths
    case conditional(ConditionalExclude)
    
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as string
        if let path = try? container.decode(String.self) {
            self = .path(path)
            return
        }
        
        // Try to decode as object
        if let conditional = try? container.decode(ConditionalExclude.self) {
            self = .conditional(conditional)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "ExcludeRule must be either a String or a ConditionalExclude object"
        )
    }
    
    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .path(let path):
            try container.encode(path)
        case .conditional(let conditional):
            try container.encode(conditional)
        }
    }
}

/// Conditional exclusion rule
package struct ConditionalExclude: Codable, Equatable {
    /// Conditional expression (evaluated as JavaScript expression)
    package let `if`: String
    
    /// List of paths to exclude (glob patterns)
    package let paths: [String]
    
    package init(if: String, paths: [String]) {
        self.if = `if`
        self.paths = paths
    }
    
    package enum CodingKeys: String, CodingKey {
        case `if`
        case paths
    }
}
