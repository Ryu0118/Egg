# Update Template

## Locating Templates

**By name:**
```bash
egg template detail <name>      # Verify exists, show info
egg template open <name>        # Open in Finder
```

**By path:**
- Verify `config.yml` exists at the path

If not found, suggest creating a new template instead.

## Change Types

| Category | Operations |
|----------|------------|
| Macro | Add, modify, remove, rename |
| File | Add, modify, remove, rename |
| Lifecycle | Add/modify/remove steps |
| Hatch | Change output, excludes |

## Dependency Checking

**Before macro removal/rename:**
1. Search template files for `___MACRO___` usage
2. Check lifecycle hooks for references
3. Check hatch output expression

**Before file removal:**
1. Check if lifecycle hooks reference the file

**Before step removal:**
1. Check if `${{ section.step-id.outputs.* }}` is referenced

## Rename Macro

1. Update config.yml with new name
2. Update all template files:
   - Content: `___OLD___` → `___NEW___`
   - Filenames containing macro
   - Directory names containing macro
3. Update lifecycle hooks
4. Update hatch output

**Example:**
```
User: Rename ___PACKAGE_NAME___ to ___MODULE_NAME___

1. Search for occurrences:
   - config.yml (definition)
   - Package.swift (3 occurrences)
   - README.md (1 occurrence)

2. Update all files

3. Validate: egg template validate <path>

Result: Use --module-name instead of --package-name
```

## Remove Macro

1. Check dependencies (see above)
2. Warn user about files using the macro
3. Remove from config.yml
4. Optionally remove placeholders from files

## Remove Lifecycle Step

1. Check if outputs are referenced
2. Warn user about dependencies
3. Remove from config.yml

## Error Handling

| Error | Solution |
|-------|----------|
| Template not found | Verify name with `egg template list` |
| Macro name conflict | Choose different name |
| Invalid macro format | Use `___UPPERCASE___` |
| Orphaned macro | Update files or add to config |
| Broken step reference | Ensure step ID exists |
