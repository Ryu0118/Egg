import Foundation

/// Lifts `{% raw %}…{% endraw %}` bodies out of a Stencil template before rendering,
/// and puts them back verbatim afterwards.
///
/// Stencil owns `{{ … }}` and `{% … %}`, which collides with every other format that
/// spells interpolation the same way — GitHub Actions (`${{ github.workflow }}`), Helm
/// and Go templates, Jinja2, Handlebars, Mustache. Rendering such a file through Stencil
/// resolves the foreign expression as an undefined Stencil variable and silently drops it.
///
/// `{% raw %}` is the escape hatch Django, Jinja2, Liquid and Twig all provide for this,
/// so egg spells it the same way. It is opt-in: a template that does not use the tag
/// renders exactly as it did before.
///
/// Upstream Stencil has no `raw` tag of its own (`Extension.registerDefaultTags()` does not
/// register one), so it is implemented here as a pre/post pass rather than as a Stencil tag.
///
/// ## Processing
///
/// `extract(from:)` replaces each block — tags included — with a per-render sentinel that
/// contains no Stencil-significant characters, so Stencil treats it as ordinary text. The
/// sentinel carries the body's newline count as trailing blank lines, so the line numbers in
/// any Stencil syntax error still point at the right line of the original template.
/// `restore(in:blocks:)` then substitutes every occurrence back — *every* occurrence, because
/// a sentinel that sat inside `{% for %}` has been duplicated, and one inside a false
/// `{% if %}` has been dropped.
///
/// ## Known limits
///
/// Because this pass runs before Stencil parses anything, it cannot know which `{% raw %}`
/// Stencil would itself have ignored:
/// - `{% raw %}` inside a Stencil comment (`{# … #}`) still opens a block.
/// - `{% raw %}` produced by a Stencil expression (`{{ "{% raw %}" }}`) is not seen at all.
/// - A raw body cannot contain the literal text `{% endraw %}`, since that closes the block.
/// - A raw body is assumed to have balanced `{% … %}` tags: a stray, unclosed `{%` inside one
///   pairs with the closing `%}` of the following `{% endraw %}` and hides it, which then
///   surfaces as `unclosedRawTag`.
/// - Stencil's whitespace-control markers (`{%- raw -%}`) are accepted but have no effect on
///   the block, which is reproduced byte for byte.
enum StencilRawBlockExtractor {
    /// A raw block that was lifted out of the template.
    struct Block: Equatable {
        /// The sentinel standing in for the block in the text handed to Stencil.
        let placeholder: String
        /// The block's body, exactly as it was written between the tags.
        let body: String
    }

    /// The result of lifting every raw block out of a template.
    struct Extraction: Equatable {
        /// The template with each raw block replaced by its sentinel.
        let text: String
        /// The lifted blocks, in the order they appeared.
        let blocks: [Block]
    }

    /// Errors raised while scanning `{% raw %}` / `{% endraw %}` tags.
    enum Error: LocalizedError, Equatable {
        /// A `{% raw %}` tag opened inside an already-open raw block.
        case nestedRawTag(line: Int, openedAtLine: Int)
        /// A `{% raw %}` tag was never closed.
        case unclosedRawTag(line: Int)
        /// An `{% endraw %}` tag appeared with no `{% raw %}` open.
        case unmatchedEndRawTag(line: Int)

        var errorDescription: String? {
            switch self {
            case let .nestedRawTag(line, openedAtLine):
                "Nested {% raw %} tag on line \(line): a raw block is already open from line \(openedAtLine). Raw blocks cannot be nested."
            case let .unclosedRawTag(line):
                "Unclosed {% raw %} tag opened on line \(line): add a matching {% endraw %}."
            case let .unmatchedEndRawTag(line):
                "Unexpected {% endraw %} on line \(line): no {% raw %} block is open."
            }
        }
    }

    /// Replaces every `{% raw %}…{% endraw %}` block with a sentinel.
    ///
    /// - Parameter text: The template source.
    /// - Returns: The rewritten template and the blocks that were lifted out of it.
    /// - Throws: `Error` when the tags are nested, unclosed, or unmatched.
    static func extract(from text: String) throws -> Extraction {
        // Cheap bail-out: the overwhelming majority of templates use no raw tag at all.
        guard text.contains("{%") else {
            return Extraction(text: text, blocks: [])
        }

        let token = UUID().uuidString
        var output = ""
        var blocks: [Block] = []

        var index = text.startIndex
        var searchStart = text.startIndex
        // Start of the body of the currently open block, or nil when no block is open.
        var openBodyStart: String.Index?
        var openTagLine = 0

        while let tag = nextTag(in: text, from: searchStart) {
            let line = lineNumber(of: tag.range.lowerBound, in: text)

            switch tag.kind {
            case .raw:
                if let openLine = openBodyStart.map({ _ in openTagLine }) {
                    throw Error.nestedRawTag(line: line, openedAtLine: openLine)
                }
                output += text[index ..< tag.range.lowerBound]
                openBodyStart = tag.range.upperBound
                openTagLine = line

            case .endRaw:
                guard let bodyStart = openBodyStart else {
                    throw Error.unmatchedEndRawTag(line: line)
                }
                let body = String(text[bodyStart ..< tag.range.lowerBound])
                let placeholder = makePlaceholder(token: token, index: blocks.count, body: body)
                blocks.append(Block(placeholder: placeholder, body: body))
                output += placeholder
                openBodyStart = nil
                index = tag.range.upperBound
            }

            searchStart = tag.range.upperBound
        }

        if openBodyStart != nil {
            throw Error.unclosedRawTag(line: openTagLine)
        }

        output += text[index...]
        return Extraction(text: output, blocks: blocks)
    }

    /// Puts every lifted raw body back in place of its sentinel.
    ///
    /// Every occurrence is replaced, not just the first: Stencil may have duplicated a
    /// sentinel by rendering it inside `{% for %}`.
    ///
    /// - Parameters:
    ///   - text: The rendered template, still containing sentinels.
    ///   - blocks: The blocks returned by `extract(from:)`.
    /// - Returns: The rendered template with the raw bodies restored.
    static func restore(in text: String, blocks: [Block]) -> String {
        blocks.reduce(text) { result, block in
            result.replacingOccurrences(of: block.placeholder, with: block.body)
        }
    }

    // MARK: - Private

    /// Builds a sentinel that Stencil passes through untouched.
    ///
    /// The sentinel contains no `{`, `}` or `%`, so Stencil's lexer sees plain text. The body's
    /// newlines are reproduced after it so that a Stencil syntax error further down the template
    /// still reports the line number the author would count in their own file. Stencil's default
    /// `Environment()` uses `TrimBehaviour.nothing`, so those newlines survive to the output —
    /// and are then replaced along with the rest of the sentinel by `restore(in:blocks:)`.
    private static func makePlaceholder(token: String, index: Int, body: String) -> String {
        let newlines = String(repeating: "\n", count: body.filter(\.isNewline).count)
        return "\u{1}EGG_RAW_\(token)_\(index)\u{2}\(newlines)"
    }

    /// A `{% raw %}` or `{% endraw %}` tag found in the source.
    private struct Tag {
        enum Kind {
            case raw
            case endRaw
        }

        let kind: Kind
        let range: Range<String.Index>
    }

    /// Finds the next raw-family tag at or after `start`.
    ///
    /// Whitespace inside the tag is optional and unconstrained, so `{%raw%}`, `{% raw %}` and
    /// `{%  raw  %}` are all accepted, as are Stencil's whitespace-control markers
    /// (`{%- raw -%}`). Any other `{% … %}` tag is skipped.
    private static func nextTag(in text: String, from start: String.Index) -> Tag? {
        var cursor = start

        while let open = text.range(of: "{%", range: cursor ..< text.endIndex) {
            guard let close = text.range(of: "%}", range: open.upperBound ..< text.endIndex) else {
                return nil
            }

            let body = text[open.upperBound ..< close.lowerBound]
            let name = body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-+"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let range = open.lowerBound ..< close.upperBound

            switch name {
            case "raw":
                return Tag(kind: .raw, range: range)
            case "endraw":
                return Tag(kind: .endRaw, range: range)
            default:
                cursor = close.upperBound
            }
        }

        return nil
    }

    /// The 1-based line number of `index` within `text`.
    private static func lineNumber(of index: String.Index, in text: String) -> Int {
        text[text.startIndex ..< index].filter(\.isNewline).count + 1
    }
}
