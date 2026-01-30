---
name: egg-cli-guide
description: CLI usage guide for egg scaffolding tool. Use when user wants to use egg commands, understand argument ordering, or troubleshoot CLI issues.
---

# egg CLI Guide

egg is a template scaffolding tool with macro substitution and lifecycle hooks.

## Commands Overview

| Command | Purpose |
|---------|---------|
| `egg hatch` | Generate files from a template |
| `egg template list` | List available templates |
| `egg template detail <name>` | Show template info and macros |
| `egg template validate <name>` | Validate template config |
| `egg template create` | Create new template |
| `egg template open <name>` | Open template in Finder |
| `egg template install` | Install from Git/local |
| `egg template delete <name>` | Delete a template |
| `egg template duplicate <name>` | Duplicate a template |
| `egg template move <name>` | Move between project/global |

## Template Locations

- **Global**: `~/.eggs/<TemplateName>/`
- **Project-local**: `./.egg/<TemplateName>/`

Project-local templates take precedence over global ones.

## egg hatch - Two Modes

### Interactive Mode

```bash
egg hatch
```

Prompts for:
1. Template name (picker UI)
2. Each macro value

### Direct Mode

```bash
egg hatch <TemplateName> --macro-name value --another-macro value
```

**IMPORTANT**: Macro arguments use `--` prefix with the macro name in kebab-case.

Example for a template with macros `ProjectName` and `UseSwiftUI`:
```bash
egg hatch MyTemplate --project-name "MyApp" --use-swift-ui true
```

## Key Options

| Option | Description |
|--------|-------------|
| `--project-directory <path>` | Where to look for project templates |
| `--staging-root <path>` | Where to output files (default: current dir) |
| `--no-staging` | Apply changes directly without preview |
| `--apply-changes` | Auto-apply without confirmation prompt |
| `--override-conflicts` | Overwrite existing files |
| `--no-sandbox` | Disable sandbox for lifecycle scripts |
| `--template-search-paths <path>` | Additional template search paths |
| `--picker list\|text` | Template picker style |

## Common Workflows

### Preview changes before applying
```bash
egg hatch MyTemplate --project-name "Test"
# Review staged changes, then confirm
```

### Apply directly without prompts
```bash
egg hatch MyTemplate --project-name "Test" --apply-changes
```

### Use template from specific location
```bash
egg hatch MyTemplate --template-search-paths /path/to/templates
```

### Output to different directory
```bash
egg hatch MyTemplate --staging-root /path/to/output
```

## Troubleshooting

### "Template not found"
1. Check template exists: `egg template list`
2. Verify location: `~/.eggs/` or `./.egg/`
3. Use `--template-search-paths` for custom locations

### "Macro X is required"
Provide all required macros in direct mode:
```bash
egg hatch Template --required-macro value
```

### Lifecycle script errors
- Check script permissions
- Use `--no-sandbox` if sandbox blocks legitimate operations
- Review script output for details
