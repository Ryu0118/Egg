public struct TextPrompt: Sendable {
    public let title: StyledText?
    public let message: StyledText
    public let description: StyledText?
    public let collapseOnAnswer: Bool
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

public struct ConfirmationPrompt: Sendable {
    public let title: StyledText?
    public let question: StyledText
    public let defaultAnswer: Bool
    public let description: StyledText?
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

public struct ChoicePrompt<Option: Equatable & CustomStringConvertible & Sendable>: Sendable {
    public let title: StyledText?
    public let question: StyledText
    public let options: [Option]
    public let description: StyledText?
    public let allowsFiltering: Bool
    public let collapseOnSelection: Bool
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

public struct MultipleChoicePrompt<Option: Equatable & CustomStringConvertible & Sendable>: Sendable {
    public let title: StyledText?
    public let question: StyledText
    public let options: [Option]
    public let description: StyledText?
    public let allowsFiltering: Bool
    public let collapseOnSelection: Bool
    public let minimumSelectionCount: Int
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
