extension StyledTextRenderer {
    /// Renders a prompt question with the active filter appended.
    func questionLine(prompt: StyledText, filter: String) -> String {
        var line = render(prompt)
        if !filter.isEmpty {
            line += " " + render("\(StyledText.Segment.muted("(filter: \(filter))"))")
        }
        return line
    }

    /// Renders one selectable option row.
    func optionLine(label: String, focused: Bool, marker: String? = nil) -> String {
        let pointer = focused ? render("\(StyledText.Segment.accent("❯"))") : " "
        let checkbox = marker.map { "\($0) " } ?? ""
        return "\(pointer) \(checkbox)\(label)"
    }

    /// Renders the single line a prompt collapses to after being answered.
    func collapsedLine(question: StyledText, answer: String) -> String {
        "\(render(question)) \(render("\(StyledText.Segment.info(answer))"))"
    }
}
