/// Configuration for a free-form text prompt.
public struct TextPrompt: Sendable {
    /// Optional title rendered before the prompt message.
    public let title: StyledText?
    /// The main message asking for input.
    public let message: StyledText
    /// Optional supporting text for the prompt.
    public let description: StyledText?
    /// Whether the prompt should collapse after an answer is accepted.
    public let collapseOnAnswer: Bool
    /// Validation rules applied to the entered answer.
    public let validationRules: [any ValidationRule]

    public init(
        title: StyledText? = nil,
        message: StyledText,
        description: StyledText? = nil,
        collapseOnAnswer: Bool = true,
        validationRules: [any ValidationRule] = [],
    ) {
        self.title = title
        self.message = message
        self.description = description
        self.collapseOnAnswer = collapseOnAnswer
        self.validationRules = validationRules
    }
}

/// Configuration for a yes/no confirmation prompt.
public struct ConfirmationPrompt: Sendable {
    /// Optional title rendered before the prompt question.
    public let title: StyledText?
    /// The confirmation question.
    public let question: StyledText
    /// The answer used when the user submits an empty response.
    public let defaultAnswer: Bool
    /// Optional supporting text for the prompt.
    public let description: StyledText?
    /// Whether the prompt should collapse after an answer is accepted.
    public let collapseOnAnswer: Bool

    public init(
        title: StyledText? = nil,
        question: StyledText,
        defaultAnswer: Bool = true,
        description: StyledText? = nil,
        collapseOnAnswer: Bool = true,
    ) {
        self.title = title
        self.question = question
        self.defaultAnswer = defaultAnswer
        self.description = description
        self.collapseOnAnswer = collapseOnAnswer
    }
}

/// Configuration for a single-choice prompt.
public struct ChoicePrompt<Option: Equatable & CustomStringConvertible & Sendable>: Sendable {
    /// Optional title rendered before the prompt question.
    public let title: StyledText?
    /// The question shown before the options.
    public let question: StyledText
    /// Options the user may choose from.
    public let options: [Option]
    /// Optional supporting text for the prompt.
    public let description: StyledText?
    /// Whether the prompt supports filtering options.
    public let allowsFiltering: Bool
    /// Whether the prompt should collapse after an option is selected.
    public let collapseOnSelection: Bool
    /// Whether a single available option should be selected automatically.
    public let autoselectSingleOption: Bool

    public init(
        title: StyledText? = nil,
        question: StyledText,
        options: [Option],
        description: StyledText? = nil,
        allowsFiltering: Bool = true,
        collapseOnSelection: Bool = true,
        autoselectSingleOption: Bool = true,
    ) {
        self.title = title
        self.question = question
        self.options = options
        self.description = description
        self.allowsFiltering = allowsFiltering
        self.collapseOnSelection = collapseOnSelection
        self.autoselectSingleOption = autoselectSingleOption
    }
}

/// Configuration for a multiple-choice prompt.
public struct MultipleChoicePrompt<Option: Equatable & CustomStringConvertible & Sendable>: Sendable {
    /// Optional title rendered before the prompt question.
    public let title: StyledText?
    /// The question shown before the options.
    public let question: StyledText
    /// Options the user may choose from.
    public let options: [Option]
    /// Optional supporting text for the prompt.
    public let description: StyledText?
    /// Whether the prompt supports filtering options.
    public let allowsFiltering: Bool
    /// Whether the prompt should collapse after selection is accepted.
    public let collapseOnSelection: Bool
    /// The minimum number of options required.
    public let minimumSelectionCount: Int
    /// The maximum number of options allowed.
    public let maximumSelectionCount: Int?

    public init(
        title: StyledText? = nil,
        question: StyledText,
        options: [Option],
        description: StyledText? = nil,
        allowsFiltering: Bool = true,
        collapseOnSelection: Bool = true,
        minimumSelectionCount: Int = 0,
        maximumSelectionCount: Int? = nil,
    ) {
        self.title = title
        self.question = question
        self.options = options
        self.description = description
        self.allowsFiltering = allowsFiltering
        self.collapseOnSelection = collapseOnSelection
        self.minimumSelectionCount = minimumSelectionCount
        self.maximumSelectionCount = maximumSelectionCount
    }
}
