---
description: Interactively create a new egg template with config.yml and optional scaffolding
argument-hint: "<description of what template to create>"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "Skill"]
---

# Create egg Template

Guide the user through creating a new egg template. This command supports two modes based on user preference.

## Initial Setup

1. Read the user's description of what template they want to create (provided as argument)
2. Based on the description, suggest an appropriate template name and confirm with user
3. Ask the user to choose the creation mode:

**Location Selection Question:**
- **Project** (`./.eggs/`): Template for this project only
- **Global** (`~/.eggs/`): Template shared across all projects
- **Repository**: Create a distributable template repository for `egg template install`

**Mode Selection Question:**
- **config.yml only**: Create just the config.yml file with macro definitions and lifecycle hooks
- **Full template scaffolding**: Create config.yml plus directory structure and sample template files

## Workflow

### Step 1: Gather Template Metadata

Ask for:
- Template name (display name for the template)
- Template description
- Template version (optional)

### Step 2: Define Macros

For each macro, collect:
- Macro name (must follow `___UPPERCASE___` format)
- Description
- Type (string, boolean, choice, choices, array, path)
- Type-specific fields:
  - `string`: optional default, optional validate (regex)
  - `boolean`: optional default (true/false)
  - `choice`: required choices list, optional default
  - `choices`: required choices list, optional default (array format)
  - `array`: optional default, optional validate, optional format expression
  - `path`: optional default

Ask if user wants to add more macros. Repeat until done.

### Step 3: Configure Lifecycle Hooks (Optional)

Ask if user needs:
- **pre_hatch**: Scripts to run before template expansion (e.g., create directories, validate environment)
- **post_hatch**: Scripts to run after expansion (e.g., git init, install dependencies)

For each step, collect:
- Step ID (optional, needed if referencing outputs)
- Condition (optional, JavaScript expression)
- Shell command

### Step 4: Configure Hatch Section

Collect:
- Output directory path (can use macros or step outputs)
- Exclude patterns (optional)
- Conditional excludes (optional)

### Step 5: Generate config.yml

Create the `config.yml` file at the specified location.

Use the `egg-config-spec` skill as reference for correct syntax.

### Step 6: Scaffolding (Full Mode Only)

If user selected full scaffolding:

1. Ask about the template structure:
   - What directories should be created?
   - What files should be included?
   - Which files should contain macro placeholders?

2. Create the directory structure with placeholder files

3. Add macro placeholders (`___MACRO_NAME___`) to:
   - Filenames that should be renamed
   - Directory names that should be renamed
   - File contents where values should be substituted

### Step 7: Validation

After generating, run `egg template validate` to check for errors:

```bash
egg template validate ./.eggs/{template-name}
```

This validates:
- YAML syntax
- Macro name formats
- Lifecycle hook configurations
- Hatch section structure

If validation fails, fix the errors and re-run validation.

## Reference

Load the `egg-config-spec` skill for detailed config.yml specification when needed.

## Output Location

Based on user's location choice:
- **Project**: `./.eggs/{template-name}/`
- **Global**: `~/.eggs/{template-name}/`
- **Repository**: `./{repo-name}/{template-name}/` (see Repository Structure below)

## Template Repository Structure

When creating a distributable template repository for `egg template install`:

```
my-egg-templates/           # Git repository root
├── .gitignore
├── README.md               # Document available templates
├── TemplateA/              # Each template is a top-level directory
│   ├── config.yml          # Required: template configuration
│   ├── ___MACRO_NAME___.swift
│   └── ...                 # Template files with ___MACRO___ placeholders
├── TemplateB/
│   ├── config.yml
│   └── ...
└── TemplateC/
    ├── config.yml
    └── ...
```

**Key rules:**
- Each template is a **top-level directory** in the repository
- Directory name = template name (used by `--template` filter)
- Each template directory MUST contain `config.yml`
- Template files use `___MACRO_NAME___` placeholders in filenames and content

**Installation examples:**
```bash
# Install all templates from repository
egg template install https://github.com/user/my-egg-templates.git --global

# Install specific template only
egg template install https://github.com/user/my-egg-templates.git --template TemplateA --global

# Install specific version
egg template install https://github.com/user/my-egg-templates.git --tag v1.0.0 --global
```

## Example Interaction

```
User: /egg-template-creator:create-template iOS app with SwiftUI, Core Data, and unit tests

Claude: I'll help you create a template for an iOS app with SwiftUI, Core Data, and unit tests.

Based on your description, I suggest the template name: "SwiftUIAppTemplate"
Does this work, or would you prefer a different name?

[User confirms or suggests alternative]

Where should this template be created?
1. Project (./.eggs/) - For this project only
2. Global (~/.eggs/) - Shared across all projects
3. Repository - Create a distributable template repository

[User selects location]

Which mode would you like?
1. config.yml only - Just create the configuration file
2. Full scaffolding - Create config.yml plus template directory structure

[User selects mode]

Great! Based on your requirements, I'll suggest these macros:
- ___APP_NAME___ (string): The app display name
- ___BUNDLE_ID___ (string): Bundle identifier
- ___DEPLOYMENT_TARGET___ (choice): iOS version target
- ___USE_CORE_DATA___ (boolean): Include Core Data stack
...

[Continues with workflow]
```

## Tips

- Suggest common macro patterns based on template type (iOS app, CLI tool, library, etc.)
- For iOS templates, recommend: `___APP_NAME___`, `___BUNDLE_ID___`, `___DEPLOYMENT_TARGET___`
- For Swift packages, recommend: `___PACKAGE_NAME___`, `___SWIFT_VERSION___`, `___PLATFORMS___`
- Always validate macro names follow the `___UPPERCASE___` format before generating

## Next Steps

After template creation, inform the user:

1. **Edit template files**: `egg template open {template-name}` to open in Finder
2. **Validate after changes**: `egg template validate ./.eggs/{template-name}`
3. **Test the template**: `egg hatch {template-name}` to generate from the template
