/// Style for selecting a template in interactive mode.
public enum TemplatePickerStyle: String, CaseIterable, Sendable {
    /// Interactive list selection with arrow keys
    case list
    /// Text input for template name
    case text
}
