import Foundation

/// Interface for terminal interaction used by command runners.
public protocol InteractionProviding: Sendable {
    /// Writes styled text without adding a status prefix.
    func write(_ text: StyledText)
    /// Writes a status-prefixed message.
    func writeStatus(_ status: Status, _ message: StyledText)
    /// Writes a rendered table.
    func writeTable(_ table: Table)
    /// Reads a text answer from the user.
    func readText(_ prompt: TextPrompt) -> String
    /// Reads a yes/no answer from the user.
    func confirm(_ prompt: ConfirmationPrompt) -> Bool
    /// Reads one choice from the user.
    func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option
    /// Reads multiple choices from the user.
    func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option]
}

/// Status categories for terminal messages.
public enum Status: Sendable {
    case success
    case failure
    case warning
    case info
}

/// Default terminal interaction implementation.
public struct Terminal: InteractionProviding {
    private let input: any TextInput
    private let output: any TextOutput
    private let tableRenderer: TableRenderer

    public init(
        input: some TextInput = StandardInput(),
        output: some TextOutput = StandardOutput(),
        tableRenderer: TableRenderer = TableRenderer(),
    ) {
        self.input = input
        self.output = output
        self.tableRenderer = tableRenderer
    }

    /// Writes styled text as plain terminal output.
    public func write(_ text: StyledText) {
        output.write(text.plainText)
    }

    /// Writes a status-prefixed message.
    public func writeStatus(_ status: Status, _ message: StyledText) {
        output.write("\(status.prefix) \(message.plainText)\n")
    }

    /// Writes a rendered table followed by a newline.
    public func writeTable(_ table: Table) {
        output.write(tableRenderer.render(table) + "\n")
    }

    /// Prompts until the user enters text that passes validation.
    public func readText(_ prompt: TextPrompt) -> String {
        while true {
            renderTitle(prompt.title)
            output.write("\(prompt.message.plainText) ")

            let answer = readLineOrAbort()
            let errors = prompt.validationRules.validate(answer)
            guard errors.isEmpty else {
                for error in errors {
                    writeStatus(.failure, "\(error.message)")
                }
                continue
            }
            return answer
        }
    }

    /// Prompts for a yes/no answer.
    public func confirm(_ prompt: ConfirmationPrompt) -> Bool {
        renderTitle(prompt.title)
        let suffix = prompt.defaultAnswer ? "[Y/n]" : "[y/N]"
        output.write("\(prompt.question.plainText) \(suffix) ")

        let answer = readLineOrAbort().trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty {
            return prompt.defaultAnswer
        }
        return ["y", "yes"].contains(answer.lowercased())
    }

    /// Prompts for one option by number.
    public func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option {
        precondition(!prompt.options.isEmpty, "Choice prompts require at least one option.")
        if prompt.options.count == 1, prompt.autoselectSingleOption {
            return prompt.options[0]
        }

        renderOptionList(title: prompt.title, question: prompt.question, options: prompt.options)

        while true {
            output.write("> ")
            guard let index = Int(readLineOrAbort().trimmingCharacters(in: .whitespacesAndNewlines)),
                  prompt.options.indices.contains(index - 1)
            else {
                writeStatus(.failure, "Enter a number from 1 to \(prompt.options.count).")
                continue
            }
            return prompt.options[index - 1]
        }
    }

    /// Prompts for multiple options by number.
    public func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option] {
        precondition(!prompt.options.isEmpty, "Multiple-choice prompts require at least one option.")
        renderOptionList(title: prompt.title, question: prompt.question, options: prompt.options)

        while true {
            output.write("> ")
            let indexes = parseIndexes(readLineOrAbort(), optionCount: prompt.options.count)
            if indexes.count < prompt.minimumSelectionCount {
                writeStatus(.failure, "Select at least \(prompt.minimumSelectionCount) option(s).")
                continue
            }
            if let maximumSelectionCount = prompt.maximumSelectionCount, indexes.count > maximumSelectionCount {
                writeStatus(.failure, "Select at most \(maximumSelectionCount) option(s).")
                continue
            }
            return indexes.map { prompt.options[$0] }
        }
    }

    private func readLineOrAbort() -> String {
        guard let line = input.readLine() else {
            // Standard input is exhausted: answering with a default here would
            // silently approve security-sensitive confirmations, so fail closed.
            FileHandle.standardError.write(Data("[error] Standard input closed before the prompt was answered.\n".utf8))
            exit(EXIT_FAILURE)
        }
        return line
    }

    private func renderTitle(_ title: StyledText?) {
        guard let title else { return }
        output.write("\(title.plainText)\n")
    }

    private func renderOptionList(title: StyledText?, question: StyledText, options: [some CustomStringConvertible]) {
        var text = title.map { "\($0.plainText)\n" } ?? ""
        text += "\(question.plainText)\n"
        for (index, option) in options.enumerated() {
            text += "  \(index + 1). \(option.description)\n"
        }
        output.write(text)
    }

    private func parseIndexes(_ input: String, optionCount: Int) -> [Int] {
        let seen = Set(
            input
                .split { $0 == "," || $0 == " " }
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { $0 - 1 }
                .filter { 0 ..< optionCount ~= $0 },
        )
        return seen.sorted()
    }
}

/// Reads text from an input source.
public protocol TextInput: Sendable {
    /// Reads one line of text.
    func readLine() -> String?
}

/// Writes text to an output sink.
public protocol TextOutput: Sendable {
    /// Writes text without adding extra formatting.
    func write(_ text: String)
}

/// Standard input backed by `Swift.readLine`.
public struct StandardInput: TextInput {
    public init() {}

    /// Reads one line from standard input.
    public func readLine() -> String? {
        Swift.readLine(strippingNewline: true)
    }
}

/// Standard output backed by `FileHandle.standardOutput`.
public struct StandardOutput: TextOutput {
    public init() {}

    /// Writes text to standard output.
    public func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

private extension Status {
    var prefix: String {
        switch self {
        case .success:
            "[success]"
        case .failure:
            "[error]"
        case .warning:
            "[warning]"
        case .info:
            "[info]"
        }
    }
}
