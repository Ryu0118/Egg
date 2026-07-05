# Create Template

## Initial Setup Questions

Ask **all three questions at once** using AskUserQuestion:

**Question 1: Template Name**
- Suggest based on description (e.g., "TCAFeature" for TCA feature template)
- User can accept or provide different name

**Question 2: Location**
| Location | Path | Use Case |
|----------|------|----------|
| Project | `./.eggs/` | Template for this project only |
| Global | `~/.eggs/` | Shared across all projects |
| Repository | Git repo | Distributable via `egg template install` |

**Question 3: Mode**
| Mode | What's Created |
|------|----------------|
| config.yml only | Just config.yml with macro definitions |
| Full scaffolding | config.yml + directory structure + sample files |

## Scaffolding (Full Mode)

1. **Plan structure:**
   - What directories?
   - What files?
   - Which need placeholders?
   - Which need conditionals/loops? (use Stencil)

2. **Create directory structure**

3. **Add placeholders to files** → See [template-files.md](template-files.md)

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

**Key rules:**
- Each template = top-level directory
- Directory name = template name
- Each must contain `config.yml`

**Installation:**
```bash
egg template install https://github.com/user/templates.git --global
egg template install https://github.com/user/templates.git --template TemplateA
egg template install https://github.com/user/templates.git --tag v1.0.0
```

## Example Interaction

```
User: Create iOS app template with SwiftUI and Core Data

Claude: [Uses AskUserQuestion with 3 questions:]
1. Template name: "SwiftUIAppTemplate" (Recommended) / Other
2. Location: Project / Global / Repository
3. Mode: config.yml only / Full scaffolding

[User answers]

Suggested macros:
- ___APP_NAME___ (string): The app display name
- ___BUNDLE_ID___ (string): Bundle identifier
- ___USE_CORE_DATA___ (boolean): Include Core Data stack

[Continues with workflow]
```

## Common Macro Patterns

| Template Type | Common Macros |
|---------------|---------------|
| iOS app | `___APP_NAME___`, `___BUNDLE_ID___`, `___DEPLOYMENT_TARGET___` |
| Swift package | `___PACKAGE_NAME___`, `___SWIFT_VERSION___`, `___PLATFORMS___` |
| TCA feature | `___FEATURE_NAME___`, `___INCLUDE_TESTS___` |
