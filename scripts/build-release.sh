#!/bin/bash
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/build-release.sh <version-tag> [out-dir] [github-repo]

Example:
  scripts/build-release.sh v0.1.0 dist meritt/microtypo-actions
EOF
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

infer_github_repo() {
  local remote repo
  remote="$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || true)"
  case "$remote" in
    https://github.com/*/*.git)
      repo="${remote#https://github.com/}"
      printf '%s\n' "${repo%.git}"
      return 0
      ;;
    https://github.com/*/*)
      printf '%s\n' "${remote#https://github.com/}"
      return 0
      ;;
    git@github.com:*.git)
      repo="${remote#git@github.com:}"
      printf '%s\n' "${repo%.git}"
      return 0
      ;;
    git@github.com:*)
      printf '%s\n' "${remote#git@github.com:}"
      return 0
      ;;
  esac
  return 1
}

validate_tag() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*)
      printf 'error: version tag must contain only letters, digits, dot, underscore, or dash\n' >&2
      return 1
      ;;
  esac
}

validate_repo() {
  case "$1" in
    */*) return 0 ;;
    *)
      printf 'error: GitHub repo must look like owner/repo\n' >&2
      return 1
      ;;
  esac
}

copy_release_tree() {
  local dst="$1"

  mkdir -p "$dst/src" \
           "$dst/services/Microtypo Text.workflow/Contents" \
           "$dst/services/Microtypo File.workflow/Contents" || return 1

  install -m 0755 "$ROOT/install.sh" "$dst/install.sh" || return 1
  install -m 0755 "$ROOT/uninstall.sh" "$dst/uninstall.sh" || return 1
  install -m 0644 "$ROOT/readme.md" "$dst/readme.md" || return 1
  install -m 0755 "$ROOT/src/typograph-selection.sh" "$dst/src/typograph-selection.sh" || return 1
  install -m 0755 "$ROOT/src/typograph-file.sh" "$dst/src/typograph-file.sh" || return 1

  install -m 0644 "$ROOT/services/Microtypo Text.workflow/Contents/Info.plist" \
    "$dst/services/Microtypo Text.workflow/Contents/Info.plist" || return 1
  install -m 0644 "$ROOT/services/Microtypo Text.workflow/Contents/document.wflow" \
    "$dst/services/Microtypo Text.workflow/Contents/document.wflow" || return 1
  install -m 0644 "$ROOT/services/Microtypo File.workflow/Contents/Info.plist" \
    "$dst/services/Microtypo File.workflow/Contents/Info.plist" || return 1
  install -m 0644 "$ROOT/services/Microtypo File.workflow/Contents/document.wflow" \
    "$dst/services/Microtypo File.workflow/Contents/document.wflow" || return 1
}

write_sha256() {
  local file="$1" dst="$2" dir base
  dir="$(dirname "$file")"
  base="$(basename "$file")"

  if command -v shasum >/dev/null 2>&1; then
    (cd "$dir" && shasum -a 256 "$base" > "$dst")
    return $?
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum "$base" > "$dst")
    return $?
  fi
  printf 'error: shasum or sha256sum is required to write archive checksum\n' >&2
  return 1
}

write_bootstrap_installer() {
  local dst="$1" version="$2" repo="$3" archive="$4"

  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -o pipefail'
    printf '\n'
    printf 'DEFAULT_REPO=%s\n' "$(shell_quote "$repo")"
    printf 'DEFAULT_VERSION=%s\n' "$(shell_quote "$version")"
    printf 'DEFAULT_ARCHIVE=%s\n' "$(shell_quote "$archive")"
    cat <<'EOF'

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

verify_sha256() {
  local file="$1" checksum="$2"
  if command -v shasum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && shasum -a 256 -c "$(basename "$checksum")" >/dev/null)
    return $?
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$checksum")" >/dev/null)
    return $?
  fi
  return 0
}

REPO="${MICROTYPO_ACTIONS_REPO:-$DEFAULT_REPO}"
VERSION="${MICROTYPO_ACTIONS_VERSION:-$DEFAULT_VERSION}"
ARCHIVE="${MICROTYPO_ACTIONS_ARCHIVE:-$DEFAULT_ARCHIVE}"
BUNDLE_DIR="microtypo-actions-$VERSION"

case "$REPO" in
  OWNER/*|*/REPO|OWNER/REPO)
    printf 'error: set MICROTYPO_ACTIONS_REPO=owner/repo\n' >&2
    exit 1
    ;;
esac

need_cmd curl
need_cmd tar

TMP_ROOT="${TMPDIR:-/tmp}"
TMP="$(mktemp -d "$TMP_ROOT/microtypo-actions-install.XXXXXX")" || exit 1
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
ARCHIVE_PATH="$TMP/$ARCHIVE"
CHECKSUM_PATH="$TMP/$ARCHIVE.sha256"

if ! curl -fsSL --retry 3 --connect-timeout 15 "$BASE_URL/$ARCHIVE" -o "$ARCHIVE_PATH"; then
  printf 'error: failed to download release archive\n' >&2
  exit 1
fi

if curl -fsSL --retry 3 --connect-timeout 15 "$BASE_URL/$ARCHIVE.sha256" -o "$CHECKSUM_PATH"; then
  verify_sha256 "$ARCHIVE_PATH" "$CHECKSUM_PATH" || exit 1
else
  printf 'warning: checksum not found\n' >&2
fi

tar -xzf "$ARCHIVE_PATH" -C "$TMP" || exit 1
if [ ! -x "$TMP/$BUNDLE_DIR/install.sh" ]; then
  printf 'error: installer not found in archive: %s/install.sh\n' "$BUNDLE_DIR" >&2
  exit 1
fi

"$TMP/$BUNDLE_DIR/install.sh" "$@"
EOF
  } > "$dst"
  chmod +x "$dst"
}

main() {
  local version="$1" out_dir="${2:-$ROOT/dist}" repo="${3:-${GITHUB_REPOSITORY:-${MICROTYPO_ACTIONS_REPO:-}}}"
  local bundle archive stage

  if [ -z "$version" ]; then
    usage >&2
    exit 2
  fi

  validate_tag "$version" || exit 2
  if [ -z "$repo" ]; then
    repo="$(infer_github_repo || true)"
  fi
  if [ -z "$repo" ]; then
    repo="meritt/microtypo-actions"
  fi
  validate_repo "$repo" || exit 2

  bundle="microtypo-actions-$version"
  archive="$bundle.tar.gz"
  stage="${TMPDIR:-/tmp}/microtypo-actions-release.$$"

  rm -rf "$out_dir" "$stage" || exit 1
  mkdir -p "$out_dir" "$stage/$bundle" || exit 1
  out_dir="$(cd "$out_dir" && pwd)" || exit 1
  trap 'rm -rf "$stage"' EXIT INT TERM

  copy_release_tree "$stage/$bundle" || exit 1
  printf '%s\n' "$version" > "$stage/$bundle/VERSION" || exit 1

  (cd "$stage" && tar -czf "$out_dir/$archive" "$bundle") || exit 1
  write_sha256 "$out_dir/$archive" "$out_dir/$archive.sha256" || exit 1
  write_bootstrap_installer "$out_dir/install.sh" "$version" "$repo" "$archive" || exit 1

  printf 'done: %s\n' "$out_dir"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
