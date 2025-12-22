---
description: Update an existing egg template by adding/modifying macros, template files, or lifecycle hooks
argument-hint: "<template-name-or-dir> <description of changes>"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "Grep", "AskUserQuestion", "Skill"]
---

# Update egg Template

Guide the user through updating an existing egg template. This command handles modifications to macros, template files, and lifecycle hooks.

## Initial Setup

1. Parse the user's input to extract:
   - **Template identifier**: Either a template name OR a directory path containing the template
   - **Change description**: What modifications the user wants to make

2. Determine if the input is a directory path or template name:
   - If it looks like a path (contains `/` or `.`), treat as directory path
   - Otherwise, treat as template name

3. Locate the template:

   **If directory path:**
   - Verify `config.yml` exists at the specified path
   - Use the directory directly as the template location

   **If template name:**
   - Run `egg template detail <template-name>` to verify it exists
   - Run `egg template open <template-name> --reveal` to find the template directory

   If template not found, inform the user and suggest using `/create-template` instead.

4. Read the current `config.yml` from the template directory.

## Change Types

Based on the user's description, identify which type(s) of changes are needed:

### 1. Macro Changes

| Change Type | Description |
|-------------|-------------|
| Add macro | Add a new `___MACRO_NAME___` with type and options |
| Modify macro | Change type, default, validation, or choices of existing macro |
| Remove macro | Delete a macro (warn about template files using it) |
| Rename macro | Change macro name (update all template files using it) |

### 2. Template File Changes

| Change Type | Description |
|-------------|-------------|
| Add file | Add a new template file with macro placeholders |
| Modify file | Update content or placeholders in existing file |
| Remove file | Delete a template file |
| Rename file | Change filename (may include macro placeholders) |
| Add directory | Create new directory structure |

### 3. Lifecycle Hook Changes

| Change Type | Description |
|-------------|-------------|
| Add pre_hatch step | Add a step before template expansion |
| Add post_hatch step | Add a step after template expansion |
| Modify step | Change command, condition, or ID of existing step |
| Remove step | Delete a lifecycle step |

### 4. Hatch Configuration Changes

| Change Type | Description |
|-------------|-------------|
| Change output | Modify the output directory expression |
| Add exclude | Add new exclusion patterns |
| Modify exclude | Change existing exclusion rules |

## Workflow

### Step 0: Load Configuration Specification (MANDATORY)

**BEFORE reading or editing config.yml, you MUST load the egg-config-spec skill:**

```
Use Skill tool: egg-template-creator:egg-config-spec
```

This is **non-negotiable** - always load this skill first to understand the correct syntax for:
- Macro types and their required/optional fields
- Lifecycle hook syntax (pre_hatch/post_hatch)
- Hatch configuration (output, exclude with conditional rules)
- Step output references (`${{ section.step-id.outputs.key }}`)

### Step 1: Analyze Current Template

1. Read and display the current `config.yml` structure
2. List existing template files
3. Summarize current macros, lifecycle hooks, and hatch config

### Step 2: Understand the Request

Parse the user's change description and categorize into:
- What to add
- What to modify
- What to remove

If unclear, use AskUserQuestion to clarify:
- Which specific macro/file/hook to modify?
- What should the new value/content be?
- Are there dependencies to consider?

### Step 3: Check Dependencies

Before making changes, verify:

**For macro removal/rename:**
- Search template files for `___MACRO_NAME___` usage
- Check lifecycle hooks for macro references
- Check hatch output expression

**For file removal:**
- Check if any lifecycle hooks reference the file

**For step removal:**
- Check if other steps or hatch output reference `${{ section.step-id.outputs.* }}`

### Step 4: Apply Changes

#### Adding a Macro

1. Ask for macro details (if not provided):
   - Name (must follow `___UPPERCASE___` format)
   - Type (string, boolean, choice, choices, array, path)
   - Type-specific options (default, validate, choices, format)
   - Description

2. Add to `config.yml` macros section

3. Ask if user wants to add placeholders to template files

#### Modifying a Macro

1. Show current macro definition
2. Apply requested changes
3. Validate changes don't break existing template files

#### Renaming a Macro

1. Update `config.yml` with new name
2. Update all template files:
   - File contents: replace `___OLD_NAME___` with `___NEW_NAME___`
   - Filenames: rename files containing the macro
   - Directory names: rename directories containing the macro
3. Update lifecycle hooks if they reference the macro
4. Update hatch output if it references the macro

#### Adding Template Files

1. Determine file location within template directory
2. Create file with appropriate macro placeholders
3. Consider adding to exclude list if conditional

#### Modifying Lifecycle Hooks

1. For new steps, collect:
   - Step ID (optional, required for output references)
   - Condition (optional JavaScript expression)
   - Shell command

2. Validate step references if using outputs

### Step 5: Validate Changes

After all modifications, run:

```bash
egg template validate <template-path>
```

If validation fails:
1. Show the error
2. Fix the issue
3. Re-validate

### Step 6: Test (Optional)

Ask if user wants to test the updated template:

```bash
egg hatch <template-name> --help
```

Show the updated macro arguments and usage.

## Reference

> **CRITICAL**: The egg-config-spec skill MUST be loaded at Step 0 before any config.yml work.
> If you skipped Step 0, go back and load it now with: `Skill tool: egg-template-creator:egg-config-spec`

The egg-config-spec skill provides:
- Macro type definitions and required fields
- Lifecycle hook syntax (pre_hatch/post_hatch)
- Hatch configuration options (output, exclude with conditional rules using `paths` array)
- Step output references and validation error reference

## Example Interactions

### Example 1: Add a new macro (by template name)

```
User: /update-template TCAFeature Add a boolean macro for including tests

Claude: I'll help update the TCAFeature template to add a boolean macro for tests.

[Reads current config.yml]

Current macros:
- ___FEATURE_NAME___ (string): Feature name

I'll add the following macro:
- ___INCLUDE_TESTS___ (boolean): Whether to include test files

[Updates config.yml]
[Asks if user wants to add conditional test files]
[Validates template]

Done! The template now supports --include-tests flag.
```

### Example 2: Update template by directory path

```
User: /update-template ./templates/my-package Add a LICENSE file

Claude: I'll update the template at ./templates/my-package to add a LICENSE file.

[Verifies config.yml exists at ./templates/my-package]
[Reads current config.yml and template structure]

I'll create a LICENSE template file. Should it use a macro for the author name?

[User confirms]

[Creates LICENSE file with ___AUTHOR___ placeholder]
[Validates template]

Done! The template now includes a LICENSE file.
```

### Example 3: Rename a macro

```
User: /update-template SwiftPackage Rename ___PACKAGE_NAME___ to ___MODULE_NAME___

Claude: I'll rename the macro from ___PACKAGE_NAME___ to ___MODULE_NAME___.

[Reads current config.yml]
[Searches for ___PACKAGE_NAME___ in template files]

Found 5 occurrences:
- config.yml (definition)
- Package.swift (3 occurrences)
- README.md (1 occurrence)

[Updates config.yml]
[Updates all template files]
[Validates template]

Renamed successfully. Use --module-name instead of --package-name.
```

### Example 4: Add a post_hatch step

```
User: /update-template iOSApp Add git init after template expansion

Claude: I'll add a post_hatch step to initialize git.

[Reads current config.yml]

Current post_hatch steps: none

Adding:
- id: init-git
- run: git init "${{ hatch.output }}"

Should this be conditional? (e.g., only when user wants git?)

[User confirms conditional]

I'll add a boolean macro ___INIT_GIT___ and make the step conditional.

[Updates config.yml with macro and hook]
[Validates template]
```

### Example 5: Add template files

```
User: /update-template TCAFeature Add a Preview file for SwiftUI previews

Claude: I'll add a Preview file to the TCAFeature template.

[Reads current template structure]

Current files:
- ___FEATURE_NAME___Feature.swift
- ___FEATURE_NAME___View.swift

I'll create:
- ___FEATURE_NAME___Preview.swift

[Creates new template file with appropriate placeholders]
[Validates template]
```

## Tips

- Always validate after changes
- When renaming macros, use Grep to find all occurrences first
- For complex changes, break into smaller steps
- Consider backwards compatibility if template is shared
- Use `egg template detail` to verify changes from user perspective

## Error Handling

| Error | Solution |
|-------|----------|
| Template not found | Verify name, check location (global vs project) |
| Macro name conflict | Choose a different name |
| Invalid macro format | Use `___UPPERCASE___` format |
| Orphaned macro in files | Update template files or add macro to config |
| Broken step reference | Ensure referenced step ID exists |

## Commands Reference

```bash
# For registered templates (by name)
egg template detail <name>           # Show template info and macros
egg template open <name>             # Open template in Finder
egg hatch <name> --help              # Preview CLI usage after update

# For directory-based templates
egg template validate <path>         # Validate after changes
egg hatch <path> --help              # Preview CLI usage (works with directory path too)
```
