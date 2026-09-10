# MicroTypo macOS Quick Actions

[![Build status][github-actions-image]][github-actions-url]

macOS Quick Actions for applying [`microtypo`](https://github.com/meritt/microtypo) typography to selected text, files, and folders.

## Requirements

- macOS 26 or later
- Node.js 26.8 or later
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

## Verify

Release archives ship a SHA-256 checksum and a build provenance attestation.

Checksum:

```bash
shasum -a 256 -c microtypo-actions-v0.1.0.tar.gz.sha256
```

Provenance (requires the GitHub CLI):

```bash
gh attestation verify microtypo-actions-v0.1.0.tar.gz --repo meritt/microtypo-actions
```

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

Unknown extensions, symlinks, hidden files, and macOS package directories are skipped. Inside a
folder only the listed extensions are picked up; a file without an extension is transformed when it
is selected directly.

Files of the same input format are rewritten in batches. A batch that fails leaves its files
untouched unless the failure happened mid-write, so `<file>.orig` remains the way back.

## Configuration

The CLI reads `.microtyporc.json`, searching upwards from its working directory, which the actions
set explicitly:

| Action | Working directory | Effective config |
|---|---|---|
| `Microtypo Text` | `$HOME` | `~/.microtyporc.json` |
| `Microtypo File` | the selected folder, or the file's folder | the nearest `.microtyporc.json` from there up |

So a project keeps its own typography rules next to its text, and `~/.microtyporc.json` covers
everything else. Options are documented in the [microtypo configuration
reference](https://github.com/meritt/microtypo/blob/main/api/configuration.md).

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

The log rotates to `microtypo.log.1` once it passes 1 MiB (override with `MICROTYPO_LOG_MAX_BYTES`).

Every run is bounded. Reaching a ceiling stops the run, goes to the log, and is reported in the
final notification:

| Variable | Default | Bounds |
|---|---|---|
| `MICROTYPO_MAX_FILES` | 2000 | files taken per run |
| `MICROTYPO_MAX_SECONDS` | 300 | wall-clock budget for the whole run |
| `MICROTYPO_CHUNK_FILES` | 50 | files per CLI run |
| `MICROTYPO_CHUNK_BYTES` | 8388608 | total size of one batch |
| `MICROTYPO_TIMEOUT` | 60 | seconds one CLI run may take |
| `MICROTYPO_PROGRESS_SECONDS` | 5 | minimum gap between progress notifications |

## Language

Installer output and notifications follow the system language: Russian when the system is set to Russian, English otherwise. Override with `MICROTYPO_LANG=ru` or `MICROTYPO_LANG=en`.

## Develop

```bash
make check   # bash -n + shellcheck
make test    # run tests/test.sh
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
"$HOME/Library/Application Support/Microtypo-QuickAction/uninstall.sh"
```

Pass `--keep-logs` to preserve `~/Library/Logs/microtypo.log`. Backups named `<file>.orig` are left untouched; find them with `find <dir> -name '*.orig'`.

Manual fallback:

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
