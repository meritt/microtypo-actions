# MicroTypo macOS Quick Actions

[![Build status][github-actions-image]][github-actions-url]

macOS Quick Actions that apply [`microtypo`](https://github.com/meritt/microtypo) typography to selected text, files, and folders.

## Requirements

- macOS 26 or later
- Node.js 26.13 or later, with npm

## Install

Latest release:

```bash
curl -fsSL https://github.com/meritt/microtypo-actions/releases/latest/download/install.sh | bash
```

Pinned release:

```bash
curl -fsSL https://github.com/meritt/microtypo-actions/releases/download/v0.3.0/install.sh | bash
```

From source:

```bash
./install.sh
```

Selection format, here `text`:

```bash
curl -fsSL https://github.com/meritt/microtypo-actions/releases/latest/download/install.sh | bash -s -- --selection-input text
```

`--selection-input`: `text`, `plain`, `html`, `markdown` (default), `mdx`, `json`, `xml`, `yaml`, `toml`, `frontmatter`.
`./install.sh` takes the same option.

The installer resolves Node.js from `MICROTYPO_NODE_BIN`, then `PATH`, then Homebrew, and installs the
microtypo version pinned in `runtime/package-lock.json` with `npm ci --ignore-scripts`.

## Verify

Checksum:

```bash
shasum -a 256 -c microtypo-actions-v0.3.0.tar.gz.sha256
```

Build provenance (GitHub CLI):

```bash
gh attestation verify microtypo-actions-v0.3.0.tar.gz --repo meritt/microtypo-actions
```

## Actions

| Action | Input | Result |
|---|---|---|
| `Microtypo Text` | text selection | replaced in place |
| `Microtypo File` | Finder files and folders | rewritten in place |

Shortcuts: System Settings -> Keyboard -> Keyboard Shortcuts -> Services. One shortcut can serve both actions.

## Files

| Extension | `--input` |
|---|---|
| `.md`, `.markdown`, `.mdown`, `.mkd` | `frontmatter` |
| `.mdx` | `mdx` |
| `.html`, `.htm` | `html` |
| `.json` | `json` |
| `.yaml`, `.yml` | `yaml` |
| `.toml` | `toml` |
| `.xml` | `xml` |
| `.txt`, `.text`, none | `text` |

- Skipped: unknown extensions, symlinks, hidden files, macOS packages (`.app`, `.bundle`, `.pages`, ...).
  A file without an extension is taken only when selected directly.
- Backup: `<file>.orig` (`cp -p`) before the first rewrite; never overwritten, removed again if the run
  left the file unchanged. A symlinked `<file>.orig` fails the file.
- Batches: one CLI run per format and folder. A failed batch leaves its files untouched unless it failed
  mid-write.

## Configuration

The CLI searches `.microtyporc.json` upwards from its working directory and reads `.microtypoignore` next
to that config, or from the working directory without one:

| Action | Working directory |
|---|---|
| `Microtypo Text` | `$HOME` |
| `Microtypo File` | the selected folder, or the selected file's folder |

```text
~/.microtyporc.json            # selection and everything without a project config
~/notes/.microtyporc.json      # files under ~/notes
~/notes/.microtypoignore       # files under ~/notes left as is
```

The action passes `--input` by extension; it takes precedence over `input` in the config. Other options:
[microtypo configuration](https://github.com/meritt/microtypo/blob/main/api/configuration.md),
[CLI](https://github.com/meritt/microtypo/blob/main/api/cli.md).

## Runtime

```text
~/Library/Application Support/Microtypo-QuickAction/env.sh   # node, CLI, selection format
~/Library/Application Support/Microtypo-QuickAction/npm      # private npm runtime
~/Library/Logs/microtypo.log                                 # file action log
```

| Variable | Default | Bounds |
|---|---|---|
| `MICROTYPO_MAX_FILES` | 2000 | files per run |
| `MICROTYPO_MAX_SECONDS` | 300 | wall clock per run |
| `MICROTYPO_CHUNK_FILES` | 50 | files per CLI run |
| `MICROTYPO_CHUNK_BYTES` | 8388608 | bytes per CLI run |
| `MICROTYPO_TIMEOUT` | 60 | seconds per CLI run |
| `MICROTYPO_PROGRESS_SECONDS` | 5 | gap between progress notifications |
| `MICROTYPO_LOG_MAX_BYTES` | 1048576 | log size before rotation to `.log.1` |

A ceiling that stops a run is logged and reported in the final notification.

Messages follow the system language (Russian or English); override with `MICROTYPO_LANG=ru|en`.

## Uninstall

```bash
"$HOME/Library/Application Support/Microtypo-QuickAction/uninstall.sh"
```

`*.orig` backups are kept. `--keep-logs` keeps `~/Library/Logs/microtypo.log` too.

## Develop

```bash
make check        # bash -n, shellcheck
make test         # unit tests under /bin/bash
make integration  # real package from npm, both actions; needs network
```

`VERSION` holds the project version. A release bumps it, then tags; the build refuses a tag that disagrees.

Release:

```bash
git tag -a v0.3.0 -m v0.3.0 && git push origin v0.3.0
```

Local build:

```bash
scripts/build-release.sh v0.3.0 dist meritt/microtypo-actions
```

## Author

- [Alexey Simonenko](https://simonenko.xyz)

## License

MIT. See `LICENSE`.

[github-actions-image]: https://github.com/meritt/microtypo-actions/actions/workflows/ci.yml/badge.svg
[github-actions-url]: https://github.com/meritt/microtypo-actions/actions/workflows/ci.yml
