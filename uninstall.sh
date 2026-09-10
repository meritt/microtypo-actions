#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Runs both from the repository and from the installed runtime, where common.sh sits beside it.
_mt_common="$SCRIPT_DIR/common.sh"
[ -f "$_mt_common" ] || _mt_common="$SCRIPT_DIR/src/common.sh"
# shellcheck source=src/common.sh
. "$_mt_common" || exit 1

APPSUP="${MICROTYPO_APPSUP:-$HOME/Library/Application Support/Microtypo-QuickAction}"
SERVICES="${MICROTYPO_SERVICES:-$HOME/Library/Services}"
LOG="${MICROTYPO_LOG:-$HOME/Library/Logs/microtypo.log}"
TEXT_SERVICE="Microtypo Text"
FILE_SERVICE="Microtypo File"

uninstall_step() { printf '==> %s\n' "$1" >&2; }
uninstall_detail() { printf '    %s\n' "$1" >&2; }

l10n() {
  local key="$1" arg="$2"
  case "${MT_LANG:-en}:$key" in
    ru:remove_services)  printf 'Удаляю Quick Actions\n' ;;
    ru:remove_runtime)   printf 'Удаляю среду выполнения\n' ;;
    ru:remove_log)       printf 'Удаляю журнал\n' ;;
    ru:keep_log)         printf 'Журнал сохранён: %s\n' "$arg" ;;
    ru:refresh_services) printf 'Обновляю реестр Services\n' ;;
    ru:backups_note)     printf 'Резервные копии *.orig не трогаю. Найти их: find <каталог> -name "*.orig"\n' ;;
    ru:complete)         printf 'Готово. MicroTypo Quick Actions удалены.\n' ;;
    *:remove_services)   printf 'Removing Quick Actions\n' ;;
    *:remove_runtime)    printf 'Removing runtime\n' ;;
    *:remove_log)        printf 'Removing log\n' ;;
    *:keep_log)          printf 'Log kept: %s\n' "$arg" ;;
    *:refresh_services)  printf 'Refreshing Services registry\n' ;;
    *:backups_note)      printf 'Left *.orig backups untouched. Find them with: find <dir> -name "*.orig"\n' ;;
    *:complete)          printf 'Done. MicroTypo Quick Actions removed.\n' ;;
    *)                   return 1 ;;
  esac
}

print_usage() {
  printf '%s\n' \
    'Usage: ./uninstall.sh [options]' \
    '' \
    'Removes the MicroTypo Quick Actions, their private runtime, and env.sh.' \
    '' \
    'Options:' \
    '  --keep-logs   Keep ~/Library/Logs/microtypo.log.' \
    '  -h, --help    Show this help.' \
    '' \
    'Backups: files renamed to <file>.orig are left in place on purpose.'
}

remove_path() {
  local p="$1"
  [ -e "$p" ] || [ -L "$p" ] || return 0
  rm -rf "$p"
}

main() {
  local keep_logs=0
  MT_LANG="$(detect_lang)"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --keep-logs) keep_logs=1; shift ;;
      -h|--help)   print_usage; return 0 ;;
      *)           printf 'error: unknown option: %s\n' "$1" >&2; return 2 ;;
    esac
  done

  uninstall_step "$(l10n remove_services)"
  remove_path "$SERVICES/$TEXT_SERVICE.workflow"
  remove_path "$SERVICES/$FILE_SERVICE.workflow"

  uninstall_step "$(l10n remove_runtime)"
  remove_path "$APPSUP"

  if [ "$keep_logs" -eq 1 ]; then
    uninstall_detail "$(l10n keep_log "$LOG")"
  else
    uninstall_step "$(l10n remove_log)"
    remove_path "$LOG"
    remove_path "$LOG.1"
  fi

  if [ -z "${MICROTYPO_SKIP_PBS:-}" ]; then
    uninstall_step "$(l10n refresh_services)"
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    /System/Library/CoreServices/pbs -flush  2>/dev/null || true
  fi

  uninstall_detail "$(l10n backups_note)"
  uninstall_step "$(l10n complete)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
