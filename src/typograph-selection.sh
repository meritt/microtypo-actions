#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
_mt_env="${MICROTYPO_ENV:-$SCRIPT_DIR/env.sh}"; [ -f "$_mt_env" ] && . "$_mt_env"

input="$(cat; printf x)"; input="${input%x}"
[ -z "$input" ] && exit 0

if [ -z "${NODE_BIN:-}" ] || [ ! -x "$NODE_BIN" ] || [ -z "${MICROTYPO_CLI:-}" ]; then
  printf '%s' "$input"; exit 0
fi

out="$(printf '%s' "$input" | "$NODE_BIN" "$MICROTYPO_CLI" --input "${MICROTYPO_SELECTION_INPUT:-markdown}" --max-input 5000000 --max-ms 30000 2>/dev/null)"; status=$?
if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  printf '%s' "$input"; exit 0
fi
printf '%s' "$out"
