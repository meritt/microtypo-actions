#!/bin/bash
# Shared by install.sh, uninstall.sh and the Quick Action scripts.

# shellcheck disable=SC2034  # read by the sourcing script
MICROTYPO_TIMEOUT_STATUS=143

# Pick the UI language once, from the user's environment, falling back to English.
# A Quick Action usually runs without LANG set, so AppleLocale is the real signal.
detect_lang() {
  local l="${MICROTYPO_LANG:-}"
  [ -n "$l" ] || l="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  if [ -z "$l" ] && command -v defaults >/dev/null 2>&1; then
    l="$(defaults read -g AppleLocale 2>/dev/null || true)"
  fi
  case "$l" in
    ru*) printf 'ru\n' ;;
    *)   printf 'en\n' ;;
  esac
}

# A ceiling that is not a plain number is no ceiling at all, so anything else falls
# back to the default rather than disabling the check it guards.
number() {
  case "$1" in
    ''|*[!0-9]*) printf '%s\n' "$2" ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

# Run a command under a wall-clock deadline; a killed command returns
# MICROTYPO_TIMEOUT_STATUS. Stdin is passed explicitly because bash redirects an
# asynchronous command from /dev/null without one. The watchdog leaves on its own
# once the command is gone: signalling it would print a job report into the log.
run_with_deadline() {
  local seconds="$1"; shift
  local pid status

  "$@" <&0 &
  pid=$!

  (
    waited=0
    while [ "$waited" -lt "$seconds" ]; do
      sleep 1
      kill -0 "$pid" 2>/dev/null || exit 0
      waited=$((waited+1))
    done
    kill -TERM "$pid" 2>/dev/null
  ) &

  wait "$pid"
  status=$?

  return "$status"
}
