# MicroTypo macOS Quick Actions

[![Build status][github-actions-image]][github-actions-url]

macOS Quick Actions for applying [`microtypo`](https://github.com/meritt/microtypo) typography to selected text, files, and folders.

## Requirements

- macOS 26 or later
- Node.js 26.4 or later
- npm

## Install

```bash
curl -fsSL https://github.com/meritt/microtypo-actions/releases/latest/download/install.sh | bash
```

Pinned version:

```bash
curl -fsSL https://github.com/meritt/microtypo-actions/releases/download/v0.1.0/install.sh | bash
```

Local source:

```bash
./install.sh
```

Selected text uses `--input markdown` by default:

```bash
./install.sh --selection-input text
```

Supported values: `text`, `html`, `markdown`, `json`, `xml`, `yaml`, `toml`, `frontmatter`.

## Actions

- `Microtypo Text`: transforms the current text selection and replaces it in place.
- `Microtypo File`: transforms selected Finder files or folders in place.

Assign shortcuts in System Settings -> Keyboard -> Keyboard Shortcuts -> Services. The same shortcut can be assigned to both actions because they run in different contexts.

## Files

Before the first file edit, `<file>.orig` is created with `cp -p`. Existing `.orig` files are never overwritten.

Supported file formats:

| Extension | Input |
|---|---|
| `.md`, `.markdown`, `.mdown`, `.mkd` | `frontmatter` |
| `.html`, `.htm` | `html` |
| `.json` | `json` |
| `.yaml`, `.yml` | `yaml` |
| `.toml` | `toml` |
| `.xml` | `xml` |
| `.txt`, `.text`, no extension | `text` |

Unknown extensions, symlinks, hidden files, and macOS package directories are skipped.

## Runtime

The installer writes absolute paths to:

```
~/Library/Application Support/Microtypo-QuickAction/env.sh
```

The private npm runtime is installed under:

```text
~/Library/Application Support/Microtypo-QuickAction/npm
```

Logs:

```bash
tail -n 20 ~/Library/Logs/microtypo.log
```

## Test

```bash
bash tests/test.sh
```

## Release

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Local artifact build:

```bash
scripts/build-release.sh v0.1.0 dist meritt/microtypo-actions
```

## Uninstall

```bash
rm -rf "$HOME/Library/Services/Microtypo Text.workflow"
rm -rf "$HOME/Library/Services/Microtypo File.workflow"
rm -rf "$HOME/Library/Application Support/Microtypo-QuickAction"
```

## Author

- [Alexey Simonenko](https://github.com/meritt)

## License

MIT. See `LICENSE`.

[github-actions-image]: https://github.com/meritt/microtypo-actions/actions/workflows/ci.yml/badge.svg
[github-actions-url]: https://github.com/meritt/microtypo-actions/actions/workflows/ci.yml
