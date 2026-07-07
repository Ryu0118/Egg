# Built-in Macros

Use automatically-resolved values without declaring them in `config.yml`.

## Overview

Every template gets four macros for free, without listing them under
`macros:`. They resolve the same way in native templates and `.stencil`
files, in file contents, file names, and directory names — anywhere a
`___MACRO___` placeholder is legal.

| Macro | Resolves to | Example |
| --- | --- | --- |
| `___DATE___` | Today's date, localized medium format by default | `Dec 12, 2025` |
| `___DATE(<format>)___` | Today's date in a custom `DateFormatter` pattern | `___DATE(yyyy-MM-dd)___` → `2025-12-12` |
| `___YEAR___` | Current year | `2025` |
| `___SYSTEM_USER___` | `$USER`, falling back to the system account name | `ryu` |
| `___UUID___` | A freshly generated UUID, unique per occurrence | `550e8400-e29b-41d4-a716-446655440000` |

`___UUID___` generates a new value at every occurrence — two `___UUID___`
placeholders in the same file resolve to two different UUIDs, not one value
reused.

## Custom date formats

`___DATE(<format>)___` takes any `DateFormatter` pattern between the
parentheses:

```text
___DATE(yyyyMMdd)___        -> 20251212
___DATE(MMM d, yyyy)___     -> Dec 12, 2025
```

Without an argument, `___DATE___` falls back to a localized medium-length
format derived from the current locale.

## Reserved names

Built-in macro names are reserved: a template's own `macros:` list cannot
declare `___DATE___`, `___YEAR___`, `___SYSTEM_USER___`, or `___UUID___`.
`egg template validate` rejects the config if it tries to.

Reserved names are still safe to reference anywhere a user-defined macro
would be — in `hatch.output`, lifecycle `run`/`if` expressions, or
`hatch.exclude` conditions — since validation treats them as always defined.

## Where resolution happens

Built-in macros resolve after user-defined macros are substituted, during
template expansion — the same pass that handles file names, directory
names, and file contents for both the native engine and Stencil. There is no
separate step to opt into; every hatch resolves them automatically.
