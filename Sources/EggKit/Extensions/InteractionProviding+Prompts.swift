import Interaction

package extension InteractionProviding {
    /// Reads text using EggKit's legacy prompt parameter names.
    func textPrompt(
        title: StyledText? = nil,
        prompt: String,
        description: StyledText? = nil,
        collapseOnAnswer: Bool = true,
        validationRules: [any Interaction.ValidationRule] = [],
    ) -> String {
        textPrompt(
            title: title,
            prompt: StyledText(prompt),
            description: description,
            collapseOnAnswer: collapseOnAnswer,
            validationRules: validationRules,
        )
    }

    /// Reads text using EggKit's legacy prompt parameter names.
    func textPrompt(
        title: StyledText? = nil,
        prompt: StyledText,
        description: StyledText? = nil,
        collapseOnAnswer: Bool = true,
        validationRules: [any Interaction.ValidationRule] = [],
    ) -> String {
        readText(
            TextPrompt(
                title: title,
                message: prompt,
                description: description,
                collapseOnAnswer: collapseOnAnswer,
                validationRules: validationRules,
            ),
        )
    }

    /// Reads a yes/no answer using EggKit's legacy prompt parameter names.
    func yesOrNoChoicePrompt(
        title: StyledText? = nil,
        question: StyledText,
        defaultAnswer: Bool = true,
        description: StyledText? = nil,
        collapseOnAnswer: Bool = true,
    ) -> Bool {
        confirm(
            ConfirmationPrompt(
                title: title,
                question: question,
                defaultAnswer: defaultAnswer,
                description: description,
                collapseOnAnswer: collapseOnAnswer,
            ),
        )
    }

    /// Reads one option using EggKit's legacy prompt parameter names.
    func singleChoicePrompt<Option>(
        title: StyledText? = nil,
        question: StyledText,
        options: [Option],
        description: StyledText? = nil,
        allowsFiltering: Bool = true,
        collapseOnSelection: Bool = true,
        autoselectSingleOption: Bool = true,
    ) -> Option where Option: Equatable & CustomStringConvertible & Sendable {
        choose(
            ChoicePrompt(
                title: title,
                question: question,
                options: options,
                description: description,
                allowsFiltering: allowsFiltering,
                collapseOnSelection: collapseOnSelection,
                autoselectSingleOption: autoselectSingleOption,
            ),
        )
    }

    /// Reads multiple options using EggKit's legacy prompt parameter names.
    func multipleChoicePrompt<Option>(
        title: StyledText? = nil,
        question: StyledText,
        options: [Option],
        description: StyledText? = nil,
        allowsFiltering: Bool = true,
        collapseOnSelection: Bool = true,
        minimumSelectionCount: Int = 0,
        maximumSelectionCount: Int? = nil,
    ) -> [Option] where Option: Equatable & CustomStringConvertible & Sendable {
        chooseMany(
            MultipleChoicePrompt(
                title: title,
                question: question,
                options: options,
                description: description,
                allowsFiltering: allowsFiltering,
                collapseOnSelection: collapseOnSelection,
                minimumSelectionCount: minimumSelectionCount,
                maximumSelectionCount: maximumSelectionCount,
            ),
        )
    }
}
