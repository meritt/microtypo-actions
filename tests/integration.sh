#!/bin/bash
# End-to-end run against the real microtypo package from npm. Needs network access.
set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$REPO_DIR/tests/harness.sh" || exit 1
# shellcheck source=install.sh
. "$REPO_DIR/install.sh" || exit 1

SANDBOX="${TMPDIR:-/tmp}/microtypo-actions-integration.$$"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX"
SANDBOX="$(cd "$SANDBOX" && pwd)"

APP="$SANDBOX/Library/Application Support/Microtypo-QuickAction"
LOG="$SANDBOX/microtypo.log"
INSTALL_LOG="$SANDBOX/install.log"
RC_JSON='{"rules":{"dash.em_double_hyphen":false}}'

selection() {
  printf '%s' "$1" | env HOME="$SANDBOX" bash "$APP/typograph-selection.sh"
}

files() {
  env HOME="$SANDBOX" MICROTYPO_LOG="$LOG" bash "$APP/typograph-file.sh" "$@" >/dev/null 2>&1
}

echo "== install =="
if env HOME="$SANDBOX" MICROTYPO_SKIP_PBS=1 bash "$REPO_DIR/install.sh" > "$INSTALL_LOG" 2>&1; then
  ok "install.sh installs $MICROTYPO_DEFAULT_NPM_SPEC"
else
  bad "install.sh failed"
  cat "$INSTALL_LOG" >&2
  summary
  exit 1
fi

# shellcheck source=/dev/null
. "$APP/env.sh"
# shellcheck disable=SC2153  # NODE_BIN and MICROTYPO_CLI come from the generated env.sh
eq "installed CLI reports the pinned version" \
  "$("$NODE_BIN" "$MICROTYPO_CLI" --version 2>/dev/null)" "${MICROTYPO_DEFAULT_NPM_SPEC#*@}"

echo "== CLI contract =="
printf '"x" -- y\n' > "$SANDBOX/-dash.txt"
if (cd "$SANDBOX" && "$NODE_BIN" "$MICROTYPO_CLI" --input text --write "-dash.txt") >/dev/null 2>&1; then
  bad "CLI reads a leading-dash name as a file"
else
  ok "CLI reads a leading-dash name as an option"
fi
if (cd "$SANDBOX" && "$NODE_BIN" "$MICROTYPO_CLI" --input text --write -- "-dash.txt") >/dev/null 2>&1; then
  ok "CLI takes a leading-dash name after the option terminator"
else
  bad "CLI rejects a leading-dash name after the option terminator"
fi

echo "== selection =="
out="$(selection '"Амбер" -- вечен')"
has "selection sets guillemets" "$out" "«Амбер»"
has "selection sets the dash" "$out" "—"
hasnt "selection leaves no straight quote" "$out" '"'

printf '%s\n' "$RC_JSON" > "$SANDBOX/.microtyporc.json"
out="$(selection '"Амбер" -- вечен')"
has "user config keeps the double hyphen" "$out" "--"
has "user config still sets guillemets" "$out" "«Амбер»"
rm -f "$SANDBOX/.microtyporc.json"

echo "== files =="
WORK="$SANDBOX/work"
mkdir -p "$WORK"
for n in a b c; do printf '"Амбер" -- вечен\n' > "$WORK/$n.txt"; done
printf -- '---\ntitle: "Тест"\n---\n\n"Амбер" -- вечен\n' > "$WORK/post.md"
printf '{"t":"\\"Амбер\\" -- вечен"}\n' > "$WORK/data.json"
printf '"x" -- y\n' > "$WORK/-lead.txt"
cp "$REPO_DIR/tests/fixtures/pic.png" "$WORK/pic.png"
printf '"z" -- w\n' > "$SANDBOX/outside.txt"
ln -s "$SANDBOX/outside.txt" "$WORK/link.txt"

files "$WORK"

for n in a b c; do
  has "batch typesets $n.txt" "$(cat "$WORK/$n.txt")" "«Амбер»"
done
has "batch typesets markdown" "$(cat "$WORK/post.md")" "«Амбер»"
has "batch keeps frontmatter" "$(cat "$WORK/post.md")" 'title: "Тест"'
has "batch typesets json values" "$(cat "$WORK/data.json")" "«Амбер»"
if "$NODE_BIN" -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "$WORK/data.json" 2>/dev/null; then
  ok "typeset json still parses"
else
  bad "typeset json no longer parses"
fi
has "batch typesets a leading-dash name" "$(cat "$WORK/-lead.txt")" "«x»"
if [ -f "$WORK/a.txt.orig" ]; then ok "backup written before the rewrite"; else bad "no backup"; fi
if [ ! -e "$WORK/pic.png.orig" ]; then ok "png skipped"; else bad "png processed"; fi
eq "symlink target untouched" "$(cat "$SANDBOX/outside.txt")" '"z" -- w'
has "log names the processed file" "$(cat "$LOG")" "ok a.txt (text)"

PROJ="$SANDBOX/project"
mkdir -p "$PROJ"
printf '%s\n' "$RC_JSON" > "$PROJ/.microtyporc.json"
printf '"Амбер" -- вечен\n' > "$PROJ/note.txt"
files "$PROJ"
has "project config keeps the double hyphen" "$(cat "$PROJ/note.txt")" "--"
has "project config still sets guillemets" "$(cat "$PROJ/note.txt")" "«Амбер»"

echo "== uninstall =="
env HOME="$SANDBOX" MICROTYPO_SKIP_PBS=1 bash "$APP/uninstall.sh" >/dev/null 2>&1
if [ ! -e "$APP" ]; then ok "uninstall removes the runtime"; else bad "runtime left behind"; fi
if [ -f "$WORK/a.txt.orig" ]; then ok "uninstall keeps backups"; else bad "uninstall removed backups"; fi

summary
