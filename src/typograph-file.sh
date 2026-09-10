#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh" || exit 1
# shellcheck source=/dev/null
_mt_env="${MICROTYPO_ENV:-$SCRIPT_DIR/env.sh}"; [ -f "$_mt_env" ] && . "$_mt_env"

LOG="${MICROTYPO_LOG:-$HOME/Library/Logs/microtypo.log}"

MAX_FILES="$(number "${MICROTYPO_MAX_FILES:-}" 2000)"
MAX_SECONDS="$(number "${MICROTYPO_MAX_SECONDS:-}" 300)"
CHUNK_FILES="$(number "${MICROTYPO_CHUNK_FILES:-}" 50)"
CHUNK_BYTES="$(number "${MICROTYPO_CHUNK_BYTES:-}" 8388608)"
TIMEOUT="$(number "${MICROTYPO_TIMEOUT:-}" 60)"
PROGRESS_SECONDS="$(number "${MICROTYPO_PROGRESS_SECONDS:-}" 5)"

MAX_INPUT=5000000
MAX_MS=30000

EXTENSION_MAP=(
  md:frontmatter markdown:frontmatter mdown:frontmatter mkd:frontmatter
  html:html htm:html
  json:json
  yaml:yaml yml:yaml
  toml:toml
  xml:xml
  txt:text text:text
)

detect_format() {
  local name="$1" ext pair
  case "$name" in
    *.*) ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')" ;;
    *)   printf 'text\n'; return 0 ;;
  esac
  for pair in "${EXTENSION_MAP[@]}"; do
    case "$pair" in
      "$ext":*) printf '%s\n' "${pair#*:}"; return 0 ;;
    esac
  done
  return 1
}

FORMATS=()
build_formats() {
  local pair fmt
  FORMATS=()
  for pair in "${EXTENSION_MAP[@]}"; do
    fmt="${pair#*:}"
    case " ${FORMATS[*]} " in
      *" $fmt "*) ;;
      *) FORMATS+=("$fmt") ;;
    esac
  done
}

FIND_NAMES=()
build_find_names() {
  local pair
  FIND_NAMES=()
  for pair in "${EXTENSION_MAP[@]}"; do
    [ "${#FIND_NAMES[@]}" -eq 0 ] || FIND_NAMES+=(-o)
    FIND_NAMES+=(-iname "*.${pair%%:*}")
  done
}

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true; }

rotate_log() {
  local max size
  max="$(number "${MICROTYPO_LOG_MAX_BYTES:-}" 1048576)"
  [ -f "$LOG" ] || return 0
  size="$(wc -c < "$LOG" 2>/dev/null | tr -d '[:space:]')" || return 0
  [ -n "$size" ] && [ "$size" -gt "$max" ] 2>/dev/null && mv -f "$LOG" "$LOG.1" 2>/dev/null
  return 0
}

# A newline in a name would forge log lines, so it never reaches the log.
log_path() {
  local p="$1"
  case "${MICROTYPO_LOG_PATHS:-basename}" in
    full) ;;
    *)    p="${p##*/}" ;;
  esac
  printf '%s\n' "${p//[$'\n\r']/ }"
}

notification_message() {
  local done="$1" skipped="$2" failed="$3" stopped="$4"
  local msg="MicroTypo: $done"
  case "${MT_LANG:-en}" in
    ru)
      [ "$skipped" -gt 0 ] && msg="$msg, пропущено: $skipped"
      [ "$failed"  -gt 0 ] && msg="$msg, ошибок: $failed"
      [ -n "$stopped" ]    && msg="$msg, остановлено по лимиту"
      ;;
    *)
      [ "$skipped" -gt 0 ] && msg="$msg, skipped: $skipped"
      [ "$failed"  -gt 0 ] && msg="$msg, errors: $failed"
      [ -n "$stopped" ]    && msg="$msg, stopped at limit"
      ;;
  esac
  printf '%s\n' "$msg"
}

progress_message() {
  case "${MT_LANG:-en}" in
    ru) printf 'MicroTypo: %s из %s\n' "$1" "$2" ;;
    *)  printf 'MicroTypo: %s of %s\n' "$1" "$2" ;;
  esac
}

missing_dependency_message() {
  case "${MT_LANG:-en}" in
    ru) printf 'node или microtypo не найдены — запустите install.sh\n' ;;
    *)  printf 'node or microtypo not found - run install.sh\n' ;;
  esac
}

notify_text() {
  osascript -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title "MicroTypo"' \
    -e 'end run' -- "$1" >/dev/null 2>&1 || true
}

notify() {
  notify_text "$(notification_message "$1" "$2" "$3" "$4")"
}

paths=()
formats_of=()
roots=()
collected=0
stopped=""

collect_file() {
  if [ "$collected" -ge "$MAX_FILES" ]; then
    stopped="files"
    log "stop: file limit $MAX_FILES reached"
    return 1
  fi
  paths+=("$1"); formats_of+=("$2"); roots+=("$3")
  collected=$((collected+1))
}

collect_dir() {
  local dir="$1" f fmt
  while IFS= read -r -d '' f; do
    fmt="$(detect_format "${f##*/}")" || continue
    collect_file "$f" "$fmt" "$dir" || break
  done < <(find "$dir" \
    \( -name '.*' -o -iname '*.app' -o -iname '*.pages' -o -iname '*.key' \
       -o -iname '*.numbers' -o -iname '*.rtfd' -o -iname '*.photoslibrary' -o -iname '*.bundle' \) -prune \
    -o -type f \( "${FIND_NAMES[@]}" \) -print0)
}

chunk=()
chunk_fmt=""
chunk_root=""
chunk_bytes=0
done=0
skipped=0
failed=0
processed=0
total=0
started=0
progressed=0

out_of_time() {
  [ $((SECONDS - started)) -ge "$MAX_SECONDS" ]
}

progress() {
  [ "$processed" -lt "$total" ] || return 0
  [ $((SECONDS - progressed)) -ge "$PROGRESS_SECONDS" ] || return 0
  progressed=$SECONDS
  notify_text "$(progress_message "$processed" "$total")"
}

chunk_run() {
  local count="${#chunk[@]}" rc f
  [ "$count" -gt 0 ] || return 0

  if out_of_time; then
    stopped="time"
    log "stop: time limit ${MAX_SECONDS}s reached ($chunk_fmt, $count)"
    skipped=$((skipped+count))
  else
    (cd "$chunk_root" && run_with_deadline "$TIMEOUT" \
      "$NODE_BIN" "$MICROTYPO_CLI" --input "$chunk_fmt" \
      --max-input "$MAX_INPUT" --max-ms "$MAX_MS" --write -- "${chunk[@]}") 2>>"$LOG"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      for f in "${chunk[@]}"; do log "ok $(log_path "$f") ($chunk_fmt)"; done
      done=$((done+count))
    elif [ "$rc" -eq "$MICROTYPO_TIMEOUT_STATUS" ]; then
      log "timeout chunk ($chunk_fmt, $count)"
      failed=$((failed+count))
    else
      log "err chunk ($chunk_fmt, $count)"
      failed=$((failed+count))
    fi
  fi

  processed=$((processed+count))
  chunk=()
  chunk_bytes=0
  progress
}

chunk_add() {
  local f="$1" fmt="$2" root="$3" size
  size="$(wc -c < "$f" 2>/dev/null)" || size=0
  size="$(number "${size//[!0-9]/}" 0)"

  if [ "${#chunk[@]}" -gt 0 ] && { [ "$fmt" != "$chunk_fmt" ] || [ "$root" != "$chunk_root" ] \
      || [ "${#chunk[@]}" -ge "$CHUNK_FILES" ] || [ $((chunk_bytes + size)) -gt "$CHUNK_BYTES" ]; }; then
    chunk_run
  fi

  if [ ! -e "$f.orig" ] && ! cp -p "$f" "$f.orig"; then
    log "backup-fail $(log_path "$f")"
    failed=$((failed+1))
    processed=$((processed+1))
    return 1
  fi

  chunk_fmt="$fmt"
  chunk_root="$root"
  chunk+=("$f")
  chunk_bytes=$((chunk_bytes + size))
}

main() {
  local target fmt dir i missing
  MT_LANG="$(detect_lang)"
  started=$SECONDS
  progressed=$SECONDS
  rotate_log
  if [ -z "${NODE_BIN:-}" ] || [ ! -x "$NODE_BIN" ] || [ -z "${MICROTYPO_CLI:-}" ] || [ ! -f "$MICROTYPO_CLI" ]; then
    missing=node
    [ -n "${NODE_BIN:-}" ] && [ -x "$NODE_BIN" ] && missing=cli
    log "abort: $missing unavailable"
    notify_text "$(missing_dependency_message)"
    return 1
  fi

  build_formats
  build_find_names

  for target in "$@"; do
    [ -z "$stopped" ] || break
    if [ -L "$target" ]; then
      log "skip $(log_path "$target") (symlink)"
      skipped=$((skipped+1))
    elif [ -d "$target" ]; then
      dir="$(cd "$target" && pwd)" || continue
      collect_dir "$dir"
    elif [ -e "$target" ]; then
      if ! fmt="$(detect_format "${target##*/}")"; then
        log "skip $(log_path "$target") (unknown)"
        skipped=$((skipped+1))
        continue
      fi
      dir="$(cd "$(dirname "$target")" && pwd)" || continue
      collect_file "$target" "$fmt" "$dir"
    fi
  done

  total=$collected
  for fmt in "${FORMATS[@]}"; do
    i=0
    while [ "$i" -lt "$collected" ]; do
      [ "${formats_of[$i]}" = "$fmt" ] && chunk_add "${paths[$i]}" "$fmt" "${roots[$i]}"
      i=$((i+1))
    done
    chunk_run
  done

  notify "$done" "$skipped" "$failed" "$stopped"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
