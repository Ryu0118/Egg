import Foundation

public protocol InteractionProviding: Sendable {
    func write(_ text: StyledText)
    func writeStatus(_ status: Status, _ message: StyledText)
    func writeTable(_ table: Table)
    func readText(_ prompt: TextPrompt) -> String
    func confirm(_ prompt: ConfirmationPrompt) -> Bool
    func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option
    func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option]
}

public enum Status: Sendable {
    case success
    case failure
    case warning
    case info
}

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

    public func write(_ text: StyledText) {
        output.write(text.plainText)
    }

    public func writeStatus(_ status: Status, _ message: StyledText) {
        output.write("\(status.prefix) \(message.plainText)\n")
    }

    public func writeTable(_ table: Table) {
        output.write(tableRenderer.render(table) + "\n")
    }

    public func readText(_ prompt: TextPrompt) -> String {
        while true {
            renderTitle(prompt.title)
            output.write("\(prompt.message.plainText) ")

            let answer = input.readLine() ?? ""
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

    public func confirm(_ prompt: ConfirmationPrompt) -> Bool {
        renderTitle(prompt.title)
        let suffix = prompt.defaultAnswer ? "[Y/n]" : "[y/N]"
        output.write("\(prompt.question.plainText) \(suffix) ")

        let answer = (input.readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty {
            return prompt.defaultAnswer
        }
        return ["y", "yes"].contains(answer.lowercased())
    }

    public func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option {
        precondition(!prompt.options.isEmpty, "Choice prompts require at least one option.")
        if prompt.options.count == 1, prompt.autoselectSingleOption {
            return prompt.options[0]
        }

        renderTitle(prompt.title)
        output.write("\(prompt.question.plainText)\n")
        for (index, option) in prompt.options.enumerated() {
            output.write("  \(index + 1). \(option.description)\n")
        }

        while true {
            output.write("> ")
            guard let answer = input.readLine(),
                  let index = Int(answer.trimmingCharacters(in: .whitespacesAndNewlines)),
                  prompt.options.indices.contains(index - 1)
            else {
                writeStatus(.failure, "Enter a number from 1 to \(prompt.options.count).")
                continue
            }
            return prompt.options[index - 1]
        }
    }

    public func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option] {
        precondition(!prompt.options.isEmpty, "Multiple-choice prompts require at least one option.")
        renderTitle(prompt.title)
        output.write("\(prompt.question.plainText)\n")
        for (index, option) in prompt.options.enumerated() {
            output.write("  \(index + 1). \(option.description)\n")
        }

        while true {
            output.write("> ")
            let indexes = parseIndexes(input.readLine() ?? "", optionCount: prompt.options.count)
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

    private func renderTitle(_ title: StyledText?) {
        guard let title else { return }
        output.write("\(title.plainText)\n")
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

public protocol TextInput: Sendable {
    func readLine() -> String?
}

public protocol TextOutput: Sendable {
    func write(_ text: String)
}

public struct StandardInput: TextInput {
    public init() {}

    public func readLine() -> String? {
        Swift.readLine(strippingNewline: true)
    }
}

public struct StandardOutput: TextOutput {
    public init() {}

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
