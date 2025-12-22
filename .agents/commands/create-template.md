---
description: Interactively create a new egg template with config.yml and optional scaffolding
argument-hint: "[template-name]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "Skill"]
---

# Create egg Template

Guide the user through creating a new egg template. This command supports two modes based on user preference.

## Initial Setup

1. If a template name is provided as argument, use it. Otherwise, ask for the template name.
2. Ask the user to choose the creation mode:

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

After generating:
1. Read back the created config.yml
2. Verify YAML syntax is valid
3. Check macro name formats
4. Confirm output with user

## Reference

Load the `egg-config-spec` skill for detailed config.yml specification when needed.

## Output Location

Default: Create template in `.eggs/{template-name}/` directory relative to current working directory.

Ask user if they want a different location.

## Example Interaction

```
User: /egg:create-template MyiOSApp

Claude: I'll help you create a new egg template called "MyiOSApp".

First, which mode would you like?
1. config.yml only - Just create the configuration file
2. Full scaffolding - Create config.yml plus template directory structure

[User selects mode]

Great! Let's define your template...
[Continues with workflow]
```

## Tips

- Suggest common macro patterns based on template type (iOS app, CLI tool, library, etc.)
- For iOS templates, recommend: `___APP_NAME___`, `___BUNDLE_ID___`, `___DEPLOYMENT_TARGET___`
- For Swift packages, recommend: `___PACKAGE_NAME___`, `___SWIFT_VERSION___`, `___PLATFORMS___`
- Always validate macro names follow the `___UPPERCASE___` format before generating
