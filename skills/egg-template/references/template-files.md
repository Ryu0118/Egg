# Template Files

## Two Template Engines

| Extension | Engine | When to Use |
|-----------|--------|-------------|
| `*.swift`, `*.md`, etc. | Native | Simple placeholder substitution |
| `*.stencil` | Stencil | Conditionals, loops, complex logic |

## Native Templates

Use `___MACRO_NAME___` placeholders in:
- File content
- Filenames
- Directory names

```swift
// ___PROJECT_NAME___.swift
struct ___PROJECT_NAME___App {
    let version = "1.0.0"
}
```

**Filename example:** `___MODULE_NAME___Tests.swift`

## Stencil Templates

Use `.stencil` extension (removed after rendering).

### Variable Output
```swift
// App.swift.stencil → App.swift
import {{ ___FRAMEWORK___ }}
```

### Conditionals
```swift
{% if ___USE_ASYNC___ %}
@main struct App {
    static func main() async {}
}
{% else %}
@main struct App {
    static func main() {}
}
{% endif %}
```

### Loops
```swift
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}
```

### Combined
```swift
struct ___FEATURE_NAME___View: View {
    {% if ___INCLUDE_VIEW_MODEL___ %}
    @StateObject var viewModel = ___FEATURE_NAME___ViewModel()
    {% endif %}

    var body: some View {
        {% for section in ___SECTIONS___ %}
        {{ section }}Section()
        {% endfor %}
    }
}
```

### Raw Blocks (`{% raw %}`)

Anything between `{% raw %}` and `{% endraw %}` is emitted verbatim: Stencil tags,
egg macros and built-ins alike are all left alone.

Use it whenever the generated file's own format also spells interpolation with
`{{ … }}` — GitHub Actions, Helm/Go templates, Jinja2, Handlebars, Mustache.
Without it, `${{ github.workflow }}` renders as a bare `$`, because Stencil resolves
`{{ github.workflow }}` as an undefined variable and drops it.

```yaml
# .github/workflows/ci.yml.stencil -> .github/workflows/ci.yml
name: {{ ___PROJECT_NAME___ }}
jobs:
  build:
    steps:
      - id: build
        run: swift build
{% raw %}
      - run: echo "built ${{ steps.build.outputs.sha }} in ${{ github.workflow }}"
{% endraw %}
```

Rules:

- Blocks cannot nest; a `{% raw %}` inside an open block is an error.
- An unclosed `{% raw %}` and a stray `{% endraw %}` are both errors, reported with a line number.
- A raw body cannot contain the literal text `{% endraw %}`.
- Raw tags are found before Stencil parses the file, so one inside a `{# ... #}`
  comment still opens a block.
- Whitespace is flexible: `{%raw%}`, `{% raw %}` and `{%- raw -%}` are all recognized,
  though the `-` whitespace-control markers have no effect on a raw block.
- A raw body is assumed to have balanced `{% ... %}` tags. A stray, unclosed `{%`
  inside one swallows the following `{% endraw %}`, which surfaces as an
  "unclosed {% raw %}" error.

**Native (non-`.stencil`) files need no raw blocks.** The native engine only claims
`${{ pre_hatch... }}` / `${{ post_hatch... }}` — egg's own lifecycle phases. A GitHub
Actions `${{ steps.build.outputs.sha }}` or `${{ needs.test.outputs.version }}` in a
plain `.yml` passes through untouched.

## When to Use Stencil

| Scenario | Use Stencil? |
|----------|--------------|
| Simple text replacement | No (Native) |
| Conditional code blocks | Yes |
| Repeated code from arrays | Yes |
| Multiple conditions | Yes |
| Optional imports/sections | Yes |

## Converting Native to Stencil

1. Rename: `File.swift` → `File.swift.stencil`
2. Convert placeholders: `___MACRO___` → `{{ ___MACRO___ }}`
3. Add `{% if %}` or `{% for %}` as needed

## Scaffolding (Create Mode)

When creating a full template:

1. **Plan structure:**
   - What directories?
   - What files?
   - Which need placeholders?
   - Which need conditionals/loops?

2. **Create files with placeholders:**
   ```
   ___PROJECT_NAME___/
   ├── Sources/
   │   └── ___MODULE_NAME___.swift
   ├── Tests/
   │   └── ___MODULE_NAME___Tests.swift
   └── Package.swift
   ```

## Template Repository Structure

For distributable templates (`egg template install`):

```
my-egg-templates/           # Git repository root
├── .gitignore
├── README.md
├── TemplateA/              # Each template = top-level directory
│   ├── config.yml          # Required
│   ├── ___MACRO_NAME___.swift
│   └── App.swift.stencil
└── TemplateB/
    └── ...
```

**Installation:**
```bash
egg template install https://github.com/user/templates.git --global
egg template install https://github.com/user/templates.git --template TemplateA
```
