#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
_mt_env="${MICROTYPO_ENV:-$SCRIPT_DIR/env.sh}"; [ -f "$_mt_env" ] && . "$_mt_env"

detect_format() {
  local name="$1" ext
  case "$name" in
    *.*) ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')" ;;
    *)   printf 'text\n'; return 0 ;;
  esac
  case "$ext" in
    md|markdown|mdown|mkd) printf 'frontmatter\n' ;;
    html|htm)              printf 'html\n' ;;
    json)                  printf 'json\n' ;;
    yaml|yml)              printf 'yaml\n' ;;
    toml)                  printf 'toml\n' ;;
    xml)                   printf 'xml\n' ;;
    txt|text)              printf 'text\n' ;;
    *)                     return 1 ;;
  esac
}

LOG="${MICROTYPO_LOG:-$HOME/Library/Logs/microtypo.log}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true; }

log_path() {
  case "${MICROTYPO_LOG_PATHS:-basename}" in
    full) printf '%s\n' "$1" ;;
    *)    basename "$1" ;;
  esac
}

notification_message() {
  local done="$1" skipped="$2" failed="$3"
  local msg="MicroTypo: $done"
  [ "$skipped" -gt 0 ] && msg="$msg, skipped: $skipped"
  [ "$failed"  -gt 0 ] && msg="$msg, errors: $failed"
  printf '%s\n' "$msg"
}

missing_dependency_message() {
  printf 'node or microtypo not found - run install.sh\n'
}

notify() {
  local done="$1" skipped="$2" failed="$3" msg
  msg="$(notification_message "$done" "$skipped" "$failed")"
  osascript -e "display notification \"$msg\" with title \"MicroTypo\"" >/dev/null 2>&1 || true
}

tally() { case "$1" in 0) done=$((done+1)) ;; 2) skipped=$((skipped+1)) ;; *) failed=$((failed+1)) ;; esac; }

process_file() {
  local f="$1" fmt
  if [ -L "$f" ]; then log "skip $(log_path "$f") (symlink)"; return 2; fi
  fmt="$(detect_format "$(basename "$f")")" || { log "skip $(log_path "$f") (unknown)"; return 2; }
  if [ ! -e "$f.orig" ]; then cp -p "$f" "$f.orig" || { log "backup-fail $(log_path "$f")"; return 1; }; fi
  if "$NODE_BIN" "$MICROTYPO_CLI" --input "$fmt" --max-input 5000000 --max-ms 30000 --write "$f" 2>>"$LOG"; then
    log "ok $(log_path "$f") ($fmt)"; return 0
  fi
  log "err $(log_path "$f") ($fmt)"; return 1
}

main() {
  local target rc done=0 skipped=0 failed=0
  if [ -z "${NODE_BIN:-}" ] || [ ! -x "$NODE_BIN" ] || [ -z "${MICROTYPO_CLI:-}" ] || [ ! -f "$MICROTYPO_CLI" ]; then
    log "abort: node/CLI unavailable (NODE_BIN=$NODE_BIN MICROTYPO_CLI=$MICROTYPO_CLI)"
    osascript -e "display notification \"$(missing_dependency_message)\" with title \"MicroTypo\"" >/dev/null 2>&1 || true
    return 1
  fi
  for target in "$@"; do
    if [ -L "$target" ]; then
      log "skip $(log_path "$target") (symlink)"
      tally 2
    elif [ -d "$target" ]; then
      while IFS= read -r -d '' f; do
        process_file "$f"; rc=$?
        tally "$rc"
      done < <(find "$target" \
        \( -name '.*' -o -iname '*.app' -o -iname '*.pages' -o -iname '*.key' \
           -o -iname '*.numbers' -o -iname '*.rtfd' -o -iname '*.photoslibrary' -o -iname '*.bundle' \) -prune \
        -o -type f \( -iname '*.md' -o -iname '*.markdown' -o -iname '*.mdown' -o -iname '*.mkd' \
           -o -iname '*.html' -o -iname '*.htm' -o -iname '*.json' -o -iname '*.yaml' -o -iname '*.yml' \
           -o -iname '*.toml' -o -iname '*.xml' -o -iname '*.txt' -o -iname '*.text' \) -print0)
    elif [ -e "$target" ]; then
      process_file "$target"; rc=$?
      tally "$rc"
    fi
  done
  notify "$done" "$skipped" "$failed"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
