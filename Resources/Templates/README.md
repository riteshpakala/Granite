# Granite Xcode Templates

`XCTemplates/` contains Xcode file templates for the core Granite building blocks:

- **GraniteComponent** — a component, its `+View`, and its `+Center`.
- **GraniteService** — a shared service and its center.
- **GraniteReducer** — a single reducer (prompts for the reducer name and its `Center` type).

## Install

From the repository root:

```bash
Scripts/install-templates.sh
```

The installer copies each `.xctemplate` bundle into
`~/Library/Developer/Xcode/Templates/Granite`. Restart Xcode, then use
**File ▸ New ▸ File…** and choose the **Granite** section.

### Options

| Flag          | Effect                                                          |
| ------------- | -------------------------------------------------------------- |
| `--symlink`   | Symlink instead of copy (edits in the repo take effect live).  |
| `--force`     | Overwrite an existing install without prompting.               |
| `--uninstall` | Remove the installed Granite templates.                        |
| `--help`      | Show usage.                                                    |
