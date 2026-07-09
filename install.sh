#!/bin/bash
set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MICROTYPO_DEFAULT_NPM_SPEC="microtypo@0.1.0"

# Minimum Node.js the microtypo CLI needs (microtypo engines: node >=26.4.0).
# readme.md documents the same floor; keep both in sync.
MICROTYPO_NODE_MIN_MAJOR=26
MICROTYPO_NODE_MIN_MINOR=4

install_step() { printf '==> %s\n' "$1" >&2; }
install_detail() { printf '    %s\n' "$1" >&2; }

# Pick the UI language once, from the user's environment, falling back to English.
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

service_name() {
  case "$1" in
    text) printf 'Microtypo Text\n' ;;
    file) printf 'Microtypo File\n' ;;
    *)    return 1 ;;
  esac
}

validate_input_format() {
  case "$1" in
    text|html|markdown|json|xml|yaml|toml|frontmatter) return 0 ;;
    *) return 1 ;;
  esac
}

print_usage() {
  printf '%s\n' \
    'Usage: ./install.sh [options]' \
    '' \
    'Options:' \
    '  --selection-input <format>  Selected-text input format: text, html, markdown, json, xml, yaml, toml, frontmatter.' \
    '                              Default: markdown. File mode still detects input from file extension.' \
    '  -h, --help                  Show this help.' \
    '' \
    'Environment:' \
    '  MICROTYPO_SELECTION_INPUT   Same as --selection-input.' \
    '  MICROTYPO_NPM_SPEC          npm package spec, for example microtypo@0.1.0.' \
    '  MICROTYPO_CLI_OVERRIDE      Explicit CLI path.'
}

INSTALL_SELECTION_INPUT=""
parse_install_args() {
  INSTALL_SELECTION_INPUT="${MICROTYPO_SELECTION_INPUT:-markdown}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --selection-input)
        [ "$#" -ge 2 ] || { echo "error: --selection-input requires a value" >&2; return 2; }
        INSTALL_SELECTION_INPUT="$2"; shift 2 ;;
      --selection-input=*)
        INSTALL_SELECTION_INPUT="${1#*=}"; shift ;;
      -h|--help)
        print_usage; return 64 ;;
      *)
        echo "error: unknown option: $1" >&2; return 2 ;;
    esac
  done
  if ! validate_input_format "$INSTALL_SELECTION_INPUT"; then
    echo "error: unsupported --selection-input: $INSTALL_SELECTION_INPUT" >&2
    return 2
  fi
  return 0
}

l10n_en() {
  local key="$1" arg="$2"
  case "$key" in
    installing_package) printf 'Installing %s\n' "$arg" ;;
    installed_package)  printf 'Installed %s\n' "$arg" ;;
    runtime)            printf 'Runtime: %s\n' "$arg" ;;
    stage)              printf 'Temporary directory: %s\n' "$arg" ;;
    npm_failed)         printf 'Failed to install package with npm\n' ;;
    cli_missing)        printf 'Package CLI not found: node_modules/microtypo/src/cli/index.js\n' ;;
    cli_path)           printf 'CLI: %s\n' "$arg" ;;
    check_node)         printf 'Checking Node.js >= %s\n' "$arg" ;;
    node_path)          printf 'Node: %s\n' "$arg" ;;
    using_override)     printf 'Using MICROTYPO_CLI_OVERRIDE\n' ;;
    check_npm)          printf 'Checking npm\n' ;;
    npm_path)           printf 'npm: %s\n' "$arg" ;;
    write_env)          printf 'Writing Quick Actions environment\n' ;;
    copy_scripts)       printf 'Copying shell scripts\n' ;;
    copy_workflows)     printf 'Copying Quick Actions\n' ;;
    refresh_services)   printf 'Refreshing Services registry\n' ;;
    complete)           printf 'Done. %s\n' "$arg" ;;
    hotkey)             printf 'Shortcut: assign the same shortcut to Microtypo Text under Text and Microtypo File under Files and Folders.\n' ;;
    registry_ready)     printf 'Services registry refreshed; reopen the Quick Actions menu if it was already open.\n' ;;
    err_node)           printf 'error: Node.js >= %s not found (set MICROTYPO_NODE_BIN)\n' "$arg" ;;
    err_npm)            printf 'error: npm not found (set MICROTYPO_NPM_BIN)\n' ;;
    err_cli_override)   printf 'error: MICROTYPO_CLI_OVERRIDE does not point to a file\n' ;;
    err_install)        printf 'error: failed to install %s from npm\n' "$arg" ;;
    *)                  return 1 ;;
  esac
}

l10n_ru() {
  local key="$1" arg="$2"
  case "$key" in
    installing_package) printf 'Устанавливаю %s\n' "$arg" ;;
    installed_package)  printf 'Установлено: %s\n' "$arg" ;;
    runtime)            printf 'Среда выполнения: %s\n' "$arg" ;;
    stage)              printf 'Временный каталог: %s\n' "$arg" ;;
    npm_failed)         printf 'Не удалось установить пакет через npm\n' ;;
    cli_missing)        printf 'CLI пакета не найден: node_modules/microtypo/src/cli/index.js\n' ;;
    cli_path)           printf 'CLI: %s\n' "$arg" ;;
    check_node)         printf 'Проверяю Node.js >= %s\n' "$arg" ;;
    node_path)          printf 'Node: %s\n' "$arg" ;;
    using_override)     printf 'Использую MICROTYPO_CLI_OVERRIDE\n' ;;
    check_npm)          printf 'Проверяю npm\n' ;;
    npm_path)           printf 'npm: %s\n' "$arg" ;;
    write_env)          printf 'Записываю окружение Quick Actions\n' ;;
    copy_scripts)       printf 'Копирую shell-скрипты\n' ;;
    copy_workflows)     printf 'Копирую Quick Actions\n' ;;
    refresh_services)   printf 'Обновляю реестр Services\n' ;;
    complete)           printf 'Готово. %s\n' "$arg" ;;
    hotkey)             printf 'Горячая клавиша: назначьте одинаковый шорткат для «Microtypo Text» (раздел Text) и «Microtypo File» (раздел Files and Folders).\n' ;;
    registry_ready)     printf 'Реестр Services обновлён; переоткройте меню Quick Actions, если оно было открыто.\n' ;;
    err_node)           printf 'ошибка: Node.js >= %s не найден (задайте MICROTYPO_NODE_BIN)\n' "$arg" ;;
    err_npm)            printf 'ошибка: npm не найден (задайте MICROTYPO_NPM_BIN)\n' ;;
    err_cli_override)   printf 'ошибка: MICROTYPO_CLI_OVERRIDE не указывает на файл\n' ;;
    err_install)        printf 'ошибка: не удалось установить %s через npm\n' "$arg" ;;
    *)                  return 1 ;;
  esac
}

l10n() {
  case "${MT_LANG:-en}" in
    ru) l10n_ru "$1" "$2" || l10n_en "$1" "$2" ;;
    *)  l10n_en "$1" "$2" ;;
  esac
}

node_meets_floor() {
  local ver="$1" major rest minor
  major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
  [ -n "$major" ] && [ -n "$minor" ] || return 1
  if [ "$major" -gt "$MICROTYPO_NODE_MIN_MAJOR" ] 2>/dev/null; then return 0; fi
  [ "$major" -eq "$MICROTYPO_NODE_MIN_MAJOR" ] 2>/dev/null && [ "$minor" -ge "$MICROTYPO_NODE_MIN_MINOR" ] 2>/dev/null
}

resolve_node() {
  local c ver abs
  # Respect the user's environment first: the node on PATH (fnm, nvm, volta, asdf,
  # mise, Nix, Bun, manual installs) wins over well-known Homebrew locations, which
  # remain only as a last resort.
  for c in "${MICROTYPO_NODE_BIN:-}" "$(command -v node 2>/dev/null || true)" /opt/homebrew/bin/node /usr/local/bin/node; do
    if [ -z "$c" ] || [ ! -x "$c" ]; then
      continue
    fi
    ver="$("$c" -p 'process.versions.node' 2>/dev/null)" || continue
    node_meets_floor "$ver" || continue
    # Bake the canonical binary so the path survives in the minimal GUI environment
    # of a Quick Action: process.execPath resolves version-manager shims and session
    # symlinks (fnm multishells, Volta shims) to the real install.
    abs="$("$c" -p 'process.execPath' 2>/dev/null)"
    if [ -z "$abs" ] || [ ! -x "$abs" ]; then
      abs="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"
    fi
    printf '%s\n' "$abs"; return 0
  done
  return 1
}

resolve_npm() {
  local node_bin="${1:-}" node_dir="" c abs
  [ -n "$node_bin" ] && node_dir="$(cd "$(dirname "$node_bin")" 2>/dev/null && pwd)"
  # Prefer the npm that ships next to the chosen node so the pair always matches.
  for c in "${MICROTYPO_NPM_BIN:-}" "${node_dir:+$node_dir/npm}" "$(command -v npm 2>/dev/null || true)" /opt/homebrew/bin/npm /usr/local/bin/npm; do
    if [ -z "$c" ] || [ ! -x "$c" ]; then
      continue
    fi
    abs="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"
    printf '%s\n' "$abs"; return 0
  done
  return 1
}

resolve_cli() {
  local candidate global_root
  if [ -n "${MICROTYPO_CLI_OVERRIDE:-}" ] && [ -f "$MICROTYPO_CLI_OVERRIDE" ]; then
    printf '%s\n' "$(cd "$(dirname "$MICROTYPO_CLI_OVERRIDE")" && pwd)/$(basename "$MICROTYPO_CLI_OVERRIDE")"; return 0
  fi

  for global_root in "${MICROTYPO_NPM_ROOT:-}" "$(npm root -g 2>/dev/null || true)"; do
    [ -n "$global_root" ] || continue
    candidate="$global_root/microtypo/src/cli/index.js"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"; return 0
    fi
  done

  candidate="$(command -v microtypo 2>/dev/null || true)"
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    printf '%s\n' "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"; return 0
  fi
  return 1
}

install_microtypo_package() {
  local prefix="$1" npm_bin="$2" spec stage cli
  [ -n "$prefix" ] && [ -n "$npm_bin" ] && [ -x "$npm_bin" ] || return 1
  spec="${MICROTYPO_NPM_SPEC:-$MICROTYPO_DEFAULT_NPM_SPEC}"
  stage="$prefix.stage.$$"

  install_step "$(l10n installing_package "$spec")"
  install_detail "$(l10n runtime "$prefix")"
  install_detail "$(l10n stage "$stage")"

  rm -rf "$stage" || return 1
  mkdir -p "$stage" || return 1
  if ! "$npm_bin" install --prefix "$stage" --omit=dev --ignore-scripts --no-audit --no-fund --progress=true "$spec" 1>&2; then
    install_detail "$(l10n npm_failed)"
    rm -rf "$stage"; return 1
  fi
  cli="$stage/node_modules/microtypo/src/cli/index.js"
  if [ ! -f "$cli" ]; then
    install_detail "$(l10n cli_missing)"
    rm -rf "$stage"; return 1
  fi
  rm -rf "$prefix" || { rm -rf "$stage"; return 1; }
  mv "$stage" "$prefix" || { rm -rf "$stage"; return 1; }
  install_step "$(l10n installed_package "$spec")"
  install_detail "$(l10n cli_path "$prefix/node_modules/microtypo/src/cli/index.js")"
  printf '%s\n' "$prefix/node_modules/microtypo/src/cli/index.js"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

write_env_file() {
  local dst="$1" node="$2" cli="$3" selection_input="$4"
  {
    printf 'NODE_BIN=%s\n' "$(shell_quote "$node")"
    printf 'MICROTYPO_CLI=%s\n' "$(shell_quote "$cli")"
    printf 'MICROTYPO_SELECTION_INPUT=%s\n' "$(shell_quote "$selection_input")"
  } > "$dst"
  chmod 0600 "$dst" 2>/dev/null || true
}

install_workflow_bundle() {
  local src="$1" dst="$2" menu_name="$3"
  rm -rf "$dst" || return 1
  cp -R "$src" "$dst" || return 1
  plutil -replace NSServices.0.NSMenuItem.default -string "$menu_name" "$dst/Contents/Info.plist" >/dev/null
}

main() {
  local node npm_bin cli appsup services env_out runtime text_service file_service selection_input parse_rc microtypo_version node_floor
  MT_LANG="$(detect_lang)"
  node_floor="$MICROTYPO_NODE_MIN_MAJOR.$MICROTYPO_NODE_MIN_MINOR"
  parse_install_args "$@"; parse_rc=$?
  if [ "$parse_rc" -eq 64 ]; then exit 0; fi
  [ "$parse_rc" -eq 0 ] || exit "$parse_rc"
  selection_input="$INSTALL_SELECTION_INPUT"
  text_service="$(service_name text)" || exit 1
  file_service="$(service_name file)" || exit 1

  install_step "$(l10n check_node "$node_floor")"
  node="$(resolve_node)" || { l10n err_node "$node_floor" >&2; exit 1; }
  install_detail "$(l10n node_path "$node ($("$node" -p 'process.versions.node' 2>/dev/null || printf unknown))")"

  appsup="$HOME/Library/Application Support/Microtypo-QuickAction"
  services="$HOME/Library/Services"
  mkdir -p "$appsup" "$services"

  if [ -n "${MICROTYPO_CLI_OVERRIDE:-}" ]; then
    install_step "$(l10n using_override)"
    cli="$(resolve_cli)" || { l10n err_cli_override >&2; exit 1; }
    install_detail "$(l10n cli_path "$cli")"
  else
    install_step "$(l10n check_npm)"
    npm_bin="$(resolve_npm "$node")" || { l10n err_npm >&2; exit 1; }
    install_detail "$(l10n npm_path "$npm_bin")"
    runtime="$appsup/npm"
    cli="$(install_microtypo_package "$runtime" "$npm_bin")" || {
      l10n err_install "${MICROTYPO_NPM_SPEC:-$MICROTYPO_DEFAULT_NPM_SPEC}" >&2; exit 1;
    }
  fi

  env_out="$appsup/env.sh"
  install_step "$(l10n write_env)"
  install_detail "$env_out"
  write_env_file "$env_out" "$node" "$cli" "$selection_input"

  install_step "$(l10n copy_scripts)"
  install -m 0755 "$REPO_DIR/src/typograph-selection.sh" "$appsup/typograph-selection.sh"
  install -m 0755 "$REPO_DIR/src/typograph-file.sh"      "$appsup/typograph-file.sh"
  [ -f "$REPO_DIR/uninstall.sh" ] && install -m 0755 "$REPO_DIR/uninstall.sh" "$appsup/uninstall.sh"

  install_step "$(l10n copy_workflows)"
  rm -rf "$services/$text_service.workflow" "$services/$file_service.workflow"
  install_workflow_bundle "$REPO_DIR/services/Microtypo Text.workflow" "$services/$text_service.workflow" "$text_service" || exit 1
  install_workflow_bundle "$REPO_DIR/services/Microtypo File.workflow" "$services/$file_service.workflow" "$file_service" || exit 1

  install_step "$(l10n refresh_services)"
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  /System/Library/CoreServices/pbs -flush  2>/dev/null || true
  microtypo_version="$("$node" "$cli" --version 2>/dev/null || printf unknown)"
  l10n complete "node=$node microtypo=$microtypo_version cli=$cli"
  l10n hotkey
  l10n registry_ready
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
