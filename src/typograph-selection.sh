#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh" || exit 1
# shellcheck source=/dev/null
_mt_env="${MICROTYPO_ENV:-$SCRIPT_DIR/env.sh}"; [ -f "$_mt_env" ] && . "$_mt_env"

# The CLI reads .microtyporc.json upwards from its working directory, and a Quick
# Action inherits whatever Automator had, so the selection is typeset under $HOME.
typeset_selection() {
  cd "${HOME:-/}" 2>/dev/null || cd / || return 1
  run_with_deadline "$(number "${MICROTYPO_TIMEOUT:-}" 60)" \
    "$NODE_BIN" "$MICROTYPO_CLI" --input "${MICROTYPO_SELECTION_INPUT:-markdown}" \
    --max-input 5000000 --max-ms 30000
}

input="$(cat; printf x)"; input="${input%x}"
[ -z "$input" ] && exit 0

if [ -z "${NODE_BIN:-}" ] || [ ! -x "$NODE_BIN" ] || [ -z "${MICROTYPO_CLI:-}" ]; then
  printf '%s' "$input"; exit 0
fi

out="$(printf '%s' "$input" | typeset_selection 2>/dev/null)"; status=$?
if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  printf '%s' "$input"; exit 0
fi
printf '%s' "$out"
