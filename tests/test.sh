#!/bin/bash
set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$REPO_DIR/tests/harness.sh" || exit 1

# shellcheck source=/dev/null
. "$REPO_DIR/install.sh"

TMP="${TMPDIR:-/tmp}/microtypo-actions-test.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"
TMP="$(cd "$TMP" && pwd)"

TEST_CLI="$TMP/microtypo-cli.js"
cat > "$TEST_CLI" <<'EOF'
const fs = require('fs');

const args = process.argv.slice(2);
if (args.includes('--version')) {
  process.stdout.write('0.2.0\n');
  process.exit(0);
}

let write = false;
const files = [];
for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === '--write' || arg === '-w') {
    write = true;
  } else if (arg === '--input' || arg === '--max-input' || arg === '--max-ms') {
    i += 1;
  } else if (!arg.startsWith('--')) {
    files.push(arg);
  }
}

function typo(input) {
  return input
    .replace(/"Амбер"/g, '«Амбер»')
    .replace(/"Амбер \?!"/g, '«Амбер?!»')
    .replace(/ -- /g, ' — ')
    .replace(/ : /g, ': ')
    .replace(/150000 руб\.?/g, '150 000 ₽')
    .replace(/из Амбера/g, 'из Амбера');
}

if (write) {
  for (const file of files) {
    fs.writeFileSync(file, typo(fs.readFileSync(file, 'utf8')));
  }
} else {
  const input = fs.readFileSync(0, 'utf8');
  if (input.length > 30000) process.exit(1);
  process.stdout.write(typo(input));
}
EOF

echo "== resolution =="
NODE="$(resolve_node)"; rc=$?
if [ "$rc" -eq 0 ] && [ -x "$NODE" ]; then ok "resolve_node -> $NODE"; else bad "resolve_node rc=$rc"; fi
eq "service text" "$(service_name text)" "Microtypo Text"
eq "service file" "$(service_name file)" "Microtypo File"
if validate_input_format markdown >/dev/null 2>&1; then ok "validate_input_format accepts markdown"; else bad "markdown rejected"; fi
if validate_input_format badformat >/dev/null 2>&1; then bad "bad input format accepted"; else ok "validate_input_format rejects bad format"; fi
parse_install_args --selection-input text >/dev/null 2>&1
eq "parse_install_args selection input flag" "$INSTALL_SELECTION_INPUT" "text"
parse_install_args --selection-input=html >/dev/null 2>&1
eq "parse_install_args selection input equals flag" "$INSTALL_SELECTION_INPUT" "html"
MICROTYPO_SELECTION_INPUT=yaml parse_install_args >/dev/null 2>&1
eq "parse_install_args selection input env" "$INSTALL_SELECTION_INPUT" "yaml"
if parse_install_args --selection-input badformat >/dev/null 2>&1; then bad "parse_install_args accepted bad input"; else ok "parse_install_args rejects bad input"; fi
CLI="$(MICROTYPO_CLI_OVERRIDE="$TEST_CLI" resolve_cli_override)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$CLI" ]; then ok "resolve_cli_override -> $CLI"; else bad "resolve_cli_override rc=$rc"; fi

# shellcheck disable=SC2016
mk_fakenode() {
  local p="$1" ver="$2" resolved
  resolved="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
  {
    printf '%s\n' '#!/bin/bash'
    printf 'case "$2" in\n'
    printf '  process.versions.node) printf "%%s\\n" "%s" ;;\n' "$ver"
    printf '  process.execPath) printf "%%s\\n" "%s" ;;\n' "$resolved"
    printf 'esac\n'
  } > "$p"
  chmod +x "$p"
}

mk_fakenode "$TMP/n279" "26.7.9"
out="$(MICROTYPO_NODE_BIN="$TMP/n279" resolve_node)"
if [ "$out" != "$TMP/n279" ]; then ok "resolve_node rejects 26.7.9 below floor"; else bad "resolve_node accepted 26.7.9 -> $out"; fi

mk_fakenode "$TMP/n268" "26.8.0"
out="$(MICROTYPO_NODE_BIN="$TMP/n268" resolve_node)"
expected_n268="$(cd "$(dirname "$TMP/n268")" && pwd)/n268"
eq "resolve_node accepts 26.8.0 override" "$out" "$expected_n268"

rc=0; run_with_deadline 5 true || rc=$?
eq "run_with_deadline returns the command status" "$rc" "0"
rc=0; run_with_deadline 1 sleep 9 || rc=$?
eq "run_with_deadline kills an overrunning command" "$rc" "$MICROTYPO_TIMEOUT_STATUS"

# resolve_npm derives npm from the chosen node's directory, not fixed locations
NPMDIR="$TMP/nodedir"; mkdir -p "$NPMDIR"
: > "$NPMDIR/node"; chmod +x "$NPMDIR/node"
: > "$NPMDIR/npm";  chmod +x "$NPMDIR/npm"
expected_colocated_npm="$(cd "$NPMDIR" && pwd)/npm"
eq "resolve_npm prefers npm beside node" "$(resolve_npm "$NPMDIR/node")" "$expected_colocated_npm"
eq "resolve_npm honors MICROTYPO_NPM_BIN override" "$(MICROTYPO_NPM_BIN="$NPMDIR/npm" resolve_npm /nonexistent/node)" "$expected_colocated_npm"

out="$(MICROTYPO_CLI_OVERRIDE="$REPO_DIR/install.sh" resolve_cli_override)"
eq "resolve_cli_override returns an absolute path" "$out" "$REPO_DIR/install.sh"

# shellcheck disable=SC2016
mk_fakenpm() {
  local p="$1"
  printf '%s\n' \
    '#!/bin/bash' \
    'all_args="$*"' \
    'prefix=""; spec=""' \
    'while [ "$#" -gt 0 ]; do' \
    '  case "$1" in' \
    '    --prefix) prefix="$2"; shift 2 ;;' \
    '    --*) shift ;;' \
    '    *) spec="$1"; shift ;;' \
    '  esac' \
    'done' \
    '[ -n "$prefix" ] || exit 2' \
    'printf "fake npm: fetching %s\n" "$spec"' \
    'mkdir -p "$prefix/node_modules/microtypo/src/cli" || exit 1' \
    'printf "%s\n" "#!/usr/bin/env node" > "$prefix/node_modules/microtypo/src/cli/index.js"' \
    'printf "%s\n" "$spec" > "$prefix/package-spec.txt"' \
    'printf "%s\n" "$all_args" > "$prefix/npm-args.txt"' \
    > "$p"
  chmod +x "$p"
}

FAKE_NPM="$TMP/npm"; mk_fakenpm "$FAKE_NPM"
PRIVATE_PREFIX="$TMP/private-npm"
INSTALL_LOG="$TMP/install.log"
out="$(install_microtypo_package "$PRIVATE_PREFIX" "$FAKE_NPM" 2>"$INSTALL_LOG")"
eq "install_microtypo_package returns private cli" "$out" "$PRIVATE_PREFIX/node_modules/microtypo/src/cli/index.js"
if [ -f "$out" ]; then ok "install_microtypo_package writes private cli"; else bad "private cli missing"; fi
eq "install_microtypo_package defaults to pinned package" "$(cat "$PRIVATE_PREFIX/package-spec.txt")" "microtypo@0.2.0"
if grep -q -- "--ignore-scripts" "$PRIVATE_PREFIX/npm-args.txt"; then ok "install disables npm lifecycle scripts"; else bad "install allows npm lifecycle scripts"; fi
if grep -q "Installing microtypo@0.2.0" "$INSTALL_LOG"; then ok "install shows package status"; else bad "install status missing"; fi
if grep -q "fake npm: fetching microtypo@0.2.0" "$INSTALL_LOG"; then ok "install shows npm progress"; else bad "npm progress hidden"; fi
if grep -q "Installed microtypo@0.2.0" "$INSTALL_LOG"; then ok "install shows package completion"; else bad "install completion missing"; fi

PRIVATE_PREFIX_EN="$TMP/private-npm-en"
INSTALL_LOG_EN="$TMP/install-en.log"
out_en="$(install_microtypo_package "$PRIVATE_PREFIX_EN" "$FAKE_NPM" 2>"$INSTALL_LOG_EN")"
eq "install_microtypo_package returns second private cli" "$out_en" "$PRIVATE_PREFIX_EN/node_modules/microtypo/src/cli/index.js"
if grep -q "Installing microtypo@0.2.0" "$INSTALL_LOG_EN"; then ok "install shows repeated package status"; else bad "repeated install status missing"; fi

ROLLBACK_PREFIX="$TMP/rollback-npm"; mkdir -p "$ROLLBACK_PREFIX"
printf 'old runtime' > "$ROLLBACK_PREFIX/marker"
FAILING_NPM="$TMP/npm-fail"
printf '%s\n' '#!/bin/bash' 'exit 1' > "$FAILING_NPM"; chmod +x "$FAILING_NPM"
if install_microtypo_package "$ROLLBACK_PREFIX" "$FAILING_NPM" >/dev/null 2>&1; then
  bad "install reports success when npm fails"
else
  ok "install fails when npm fails"
fi
eq "failed install keeps the previous runtime" "$(cat "$ROLLBACK_PREFIX/marker" 2>/dev/null)" "old runtime"
if ls -d "$TMP"/microtypo-stage.* >/dev/null 2>&1; then bad "install leaves a staging directory"; else ok "install cleans its staging directory"; fi

WF_STAGE="$TMP/workflows"; rm -rf "$WF_STAGE"; mkdir -p "$WF_STAGE"
install_workflow_bundle "$REPO_DIR/services/Microtypo Text.workflow" "$WF_STAGE/Microtypo Text.workflow" "Microtypo Text"
if [ -d "$WF_STAGE/Microtypo Text.workflow" ]; then ok "workflow bundle folder exists"; else bad "workflow bundle folder missing"; fi
eq "workflow plist localized menu" "$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$WF_STAGE/Microtypo Text.workflow/Contents/Info.plist" 2>/dev/null)" "Microtypo Text"

echo "== selection core =="
cat > "$TMP/env.sh" <<EOF
NODE_BIN="$NODE"
MICROTYPO_CLI="$CLI"
EOF
export MICROTYPO_ENV="$TMP/env.sh"
export MICROTYPO_LOG="$TMP/microtypo.log"
SEL="$REPO_DIR/src/typograph-selection.sh"

out="$(printf '"Амбер" -- 150000 руб.' | bash "$SEL")"
eq "selection typography" "$out" "«Амбер» — 150 000 ₽"

out="$(printf '' | bash "$SEL")"
eq "selection empty->empty" "$out" ""

big="$(head -c 40000 /dev/zero | tr '\0' 'a')"
out="$(printf '%s' "$big" | MICROTYPO_ENV="$TMP/env.sh" bash "$SEL")"
eq "selection oversize restores original" "$out" "$big"

nl_in="$big"$'\n'
cap="$(printf '%s' "$nl_in" | MICROTYPO_ENV="$TMP/env.sh" bash "$SEL"; printf x)"; cap="${cap%x}"
eq "oversize fallback preserves trailing newline" "$cap" "$nl_in"

out="$(printf 'просто' | bash "$SEL" | xxd -p | tr -d '\n')"
last2="${out: -2}"
if [ "$last2" != "0a" ]; then ok "selection no trailing newline"; else bad "selection added trailing newline"; fi

FAKE_NODE_SEL="$TMP/fake-node-selection"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$*" > "$FAKE_NODE_ARGS_LOG"' \
  'printf processed' \
  > "$FAKE_NODE_SEL"
chmod +x "$FAKE_NODE_SEL"
cat > "$TMP/env-selection-markdown.sh" <<EOF
NODE_BIN="$FAKE_NODE_SEL"
MICROTYPO_CLI="$TMP/fake-cli"
MICROTYPO_SELECTION_INPUT="markdown"
EOF
out="$(printf 'plain' | FAKE_NODE_ARGS_LOG="$TMP/fake-node-args" MICROTYPO_ENV="$TMP/env-selection-markdown.sh" bash "$SEL")"
eq "selection fake cli output" "$out" "processed"
eq "selection passes bounded markdown input" "$(cat "$TMP/fake-node-args")" "$TMP/fake-cli --input markdown --max-input 5000000 --max-ms 30000"

cat > "$TMP/env-selection-text.sh" <<EOF
NODE_BIN="$FAKE_NODE_SEL"
MICROTYPO_CLI="$TMP/fake-cli"
MICROTYPO_SELECTION_INPUT="text"
EOF
printf 'plain' | FAKE_NODE_ARGS_LOG="$TMP/fake-node-args" MICROTYPO_ENV="$TMP/env-selection-text.sh" bash "$SEL" >/dev/null
eq "selection input override text stays bounded" "$(cat "$TMP/fake-node-args")" "$TMP/fake-cli --input text --max-input 5000000 --max-ms 30000"

echo "== detect_format =="
# shellcheck source=/dev/null
. "$REPO_DIR/src/typograph-file.sh"
eq "md->frontmatter"   "$(detect_format post.md)"        "frontmatter"
eq "markdown->fm"      "$(detect_format a.markdown)"     "frontmatter"
eq "html->html"        "$(detect_format i.HTML)"         "html"
eq "json->json"        "$(detect_format data.json)"      "json"
eq "yaml->yaml"        "$(detect_format c.yml)"          "yaml"
eq "toml->toml"        "$(detect_format c.toml)"         "toml"
eq "xml->xml"          "$(detect_format f.xml)"          "xml"
eq "txt->text"         "$(detect_format n.txt)"          "text"
eq "noext->text"       "$(detect_format README)"         "text"
if detect_format image.png >/dev/null; then bad "png must skip"; else ok "png skips (rc1)"; fi
if detect_format script.js >/dev/null; then bad "js must skip"; else ok "js skips (rc1)"; fi
eq "notification message" "$(notification_message 1 2 3)" "MicroTypo: 1, skipped: 2, errors: 3"
eq "notification message reports a ceiling" "$(notification_message 1 0 0 files)" "MicroTypo: 1, stopped at limit"
eq "progress message" "$(progress_message 5 20)" "MicroTypo: 5 of 20"
eq "number keeps a plain number" "$(number 42 7)" "42"
eq "number falls back on a non-number" "$(number abc 7)" "7"
eq "number falls back on an empty value" "$(number '' 7)" "7"
eq "log_path strips a newline from a name" "$(log_path "$(printf 'a\nb.txt')")" "a b.txt"
# shellcheck disable=SC2030,SC2031,SC2034
eq "progress message ru" "$(MT_LANG=ru; progress_message 5 20)" "MicroTypo: 5 из 20"
# MT_LANG and LOG below are consumed by functions sourced from src/*.sh.
# shellcheck disable=SC2030,SC2031,SC2034
eq "notification message ru" "$(MT_LANG=ru; notification_message 1 2 3)" "MicroTypo: 1, пропущено: 2, ошибок: 3"
# shellcheck disable=SC2030,SC2031,SC2034
eq "missing dependency ru" "$(MT_LANG=ru; missing_dependency_message)" "node или microtypo не найдены — запустите install.sh"

ROT_LOG="$TMP/rotate.log"
head -c 2000 /dev/zero | tr '\0' 'a' > "$ROT_LOG"
# shellcheck disable=SC2030,SC2031,SC2034
( LOG="$ROT_LOG"; MICROTYPO_LOG_MAX_BYTES=1000 rotate_log )
if [ -f "$ROT_LOG.1" ] && [ ! -f "$ROT_LOG" ]; then ok "rotate_log rotates oversize log"; else bad "rotate_log did not rotate"; fi
printf 'small' > "$ROT_LOG"
# shellcheck disable=SC2030,SC2031,SC2034
( LOG="$ROT_LOG"; MICROTYPO_LOG_MAX_BYTES=1000 rotate_log )
if [ -f "$ROT_LOG" ]; then ok "rotate_log keeps small log"; else bad "rotate_log dropped small log"; fi

echo "== file core =="
WORK="$TMP/work"; rm -rf "$WORK"; mkdir -p "$WORK"
cp tests/fixtures/sample.json "$WORK/a.json"
cp tests/fixtures/note.txt   "$WORK/b.txt"
cp tests/fixtures/pic.png    "$WORK/c.png"
FILE="$REPO_DIR/src/typograph-file.sh"

MICROTYPO_ENV="$TMP/env.sh" bash "$FILE" "$WORK/a.json" "$WORK/b.txt" "$WORK/c.png" >/dev/null 2>&1

if grep -q '—' "$WORK/a.json"; then ok "json typeset in place"; else bad "json not typeset"; fi
if grep -q '"n":150000' "$WORK/a.json"; then ok "json structure preserved"; else bad "json structure changed"; fi
if [ -f "$WORK/a.json.orig" ]; then ok "json backup created"; else bad "no json backup"; fi
if grep -q '«Амбер»' "$WORK/b.txt"; then ok "txt typeset"; else bad "txt not typeset"; fi
if [ ! -f "$WORK/c.png.orig" ]; then ok "png skipped (no backup)"; else bad "png was processed"; fi
if grep -q "$WORK/a.json" "$MICROTYPO_LOG"; then bad "default log exposes full paths"; else ok "default log avoids full paths"; fi
if grep -q "ok a.json (json)" "$MICROTYPO_LOG"; then ok "default log keeps basename status"; else bad "default log missing basename status"; fi

before="$(cat "$WORK/a.json.orig")"
MICROTYPO_ENV="$TMP/env.sh" bash "$FILE" "$WORK/a.json" >/dev/null 2>&1
eq "orig not clobbered on re-run" "$(cat "$WORK/a.json.orig")" "$before"

: > "$MICROTYPO_LOG"
printf 'plain' > "$WORK/target.txt"
ln -s "$WORK/target.txt" "$WORK/link.txt"
MICROTYPO_ENV="$TMP/env.sh" bash "$FILE" "$WORK/link.txt" >/dev/null 2>&1
eq "symlink target unchanged" "$(cat "$WORK/target.txt")" "plain"
if [ ! -e "$WORK/link.txt.orig" ]; then ok "symlink skipped without backup"; else bad "symlink backup created"; fi
if grep -q "skip link.txt (symlink)" "$MICROTYPO_LOG"; then ok "symlink skip logged"; else bad "symlink skip not logged"; fi

DIR="$WORK/dir"; mkdir -p "$DIR/.hidden"
cp tests/fixtures/sample.md "$DIR/p.md"
cp tests/fixtures/note.txt  "$DIR/.hidden/skip.txt"
mkdir -p "$DIR/pkg.app"; cp tests/fixtures/note.txt "$DIR/pkg.app/inner.txt"
MICROTYPO_ENV="$TMP/env.sh" bash "$FILE" "$DIR" >/dev/null 2>&1
if grep -q '«Амбер' "$DIR/p.md" && grep -q '₽' "$DIR/p.md"; then ok "folder recursion typeset md"; else bad "md not typeset"; fi
if [ ! -f "$DIR/.hidden/skip.txt.orig" ]; then ok "hidden pruned"; else bad "hidden not pruned"; fi
if [ ! -f "$DIR/pkg.app/inner.txt.orig" ]; then ok "bundle .app pruned"; else bad "bundle .app not pruned"; fi

echo "== batching =="
# shellcheck disable=SC2016
mk_recorder() {
  printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s|%s\n" "$PWD" "$*" >> "$FAKE_RECORD"' \
    '[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"' \
    'printf processed' \
    > "$1"
  chmod +x "$1"
}

REC_NODE="$TMP/rec-node"; mk_recorder "$REC_NODE"
REC="$TMP/rec.log"
: > "$TMP/fake-cli"
cat > "$TMP/env-rec.sh" <<EOF
NODE_BIN="$REC_NODE"
MICROTYPO_CLI="$TMP/fake-cli"
EOF

BATCH="$TMP/batch"; rm -rf "$BATCH"; mkdir -p "$BATCH"
for n in 1 2 3; do printf 'text %s\n' "$n" > "$BATCH/f$n.md"; done
printf '{"a":1}\n' > "$BATCH/d1.json"
printf '{"a":2}\n' > "$BATCH/d2.json"

run_batch() {
  : > "$REC"
  : > "$MICROTYPO_LOG"
  rm -f "$BATCH"/*.orig
  env FAKE_RECORD="$REC" MICROTYPO_ENV="$TMP/env-rec.sh" "$@" bash "$FILE" "$BATCH" >/dev/null 2>&1
}
runs() { wc -l < "$REC" | tr -d '[:space:]'; }
backups() { find "$BATCH" -name '*.orig' | wc -l | tr -d '[:space:]'; }

run_batch
eq "batch runs one process per format" "$(runs)" "2"
md_line="$(grep -F -- '--input frontmatter' "$REC")"
eq "batch runs in the target directory" "${md_line%%|*}" "$BATCH"
case "$md_line" in
  *"--write -- "*) ok "batch terminates options before file names" ;;
  *)               bad "batch terminates options before file names ($md_line)" ;;
esac
missing=""
for n in 1 2 3; do
  case "$md_line" in *"$BATCH/f$n.md"*) ;; *) missing="$missing f$n.md" ;; esac
done
if [ -z "$missing" ]; then ok "batch sends a whole format in one run"; else bad "batch left out:$missing"; fi
case "$md_line" in
  *.json*) bad "batch mixes formats in one run ($md_line)" ;;
  *)       ok "batch keeps formats apart" ;;
esac

run_batch MICROTYPO_CHUNK_FILES=2
eq "chunk file ceiling splits the run" "$(runs)" "3"
run_batch MICROTYPO_CHUNK_BYTES=10
eq "chunk byte ceiling splits the run" "$(runs)" "5"

printf 'dash\n' > "$BATCH/-lead.md"
run_batch
md_line="$(grep -F -- '--input frontmatter' "$REC")"
case "$md_line" in
  *"--write -- "*"$BATCH/-lead.md"*) ok "file with a leading dash goes after the terminator" ;;
  *) bad "file with a leading dash goes after the terminator ($md_line)" ;;
esac
rm -f "$BATCH/-lead.md"

run_batch MICROTYPO_MAX_FILES=2
if grep -q "stop: file limit 2" "$MICROTYPO_LOG"; then ok "file ceiling stops collection"; else bad "file ceiling not logged"; fi
eq "file ceiling limits what runs" "$(backups)" "2"

run_batch MICROTYPO_MAX_SECONDS=0
if grep -q "stop: time limit 0s" "$MICROTYPO_LOG"; then ok "time ceiling stops the run"; else bad "time ceiling not logged"; fi
eq "time ceiling starts no CLI" "$(runs)" "0"

run_batch MICROTYPO_MAX_SECONDS=abc
eq "a malformed ceiling falls back instead of stopping the run" "$(runs)" "2"

SLOW="$TMP/slow"; rm -rf "$SLOW"; mkdir -p "$SLOW"; printf 'slow\n' > "$SLOW/s.md"
: > "$MICROTYPO_LOG"; : > "$REC"
env FAKE_RECORD="$REC" FAKE_SLEEP=9 MICROTYPO_TIMEOUT=1 MICROTYPO_ENV="$TMP/env-rec.sh" \
  bash "$FILE" "$SLOW" >/dev/null 2>&1
if grep -q "timeout chunk (frontmatter, 1)" "$MICROTYPO_LOG"; then ok "chunk deadline kills a stuck CLI"; else bad "chunk deadline not logged"; fi

: > "$REC"
out="$(printf 'plain' | env FAKE_RECORD="$REC" MICROTYPO_ENV="$TMP/env-rec.sh" bash "$SEL")"
eq "selection returns the CLI output" "$out" "processed"
eq "selection runs in \$HOME" "$(head -n 1 "$REC" | sed 's/|.*//')" "$HOME"

echo "== plists =="
SVC_A="$REPO_DIR/services/Microtypo Text.workflow/Contents"
SVC_B="$REPO_DIR/services/Microtypo File.workflow/Contents"
for p in "$SVC_A/Info.plist" "$SVC_A/document.wflow" "$SVC_B/Info.plist" "$SVC_B/document.wflow"; do
  if plutil -lint "$p" >/dev/null 2>&1; then ok "lint $(basename "$(dirname "$(dirname "$p")")")/$(basename "$p")"; else bad "lint $p"; fi
done
eq "A source menu default english" "$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$SVC_A/Info.plist" 2>/dev/null)" "Microtypo Text"
eq "B source menu default english" "$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$SVC_B/Info.plist" 2>/dev/null)" "Microtypo File"
eq "A serviceProcessesInput=1" "$(plutil -extract workflowMetaData.serviceProcessesInput raw -o - "$SVC_A/document.wflow" 2>/dev/null)" "1"
eq "A input type=text"         "$(plutil -extract workflowMetaData.serviceInputTypeIdentifier raw -o - "$SVC_A/document.wflow" 2>/dev/null)" "com.apple.Automator.text"
eq "B serviceProcessesInput=0" "$(plutil -extract workflowMetaData.serviceProcessesInput raw -o - "$SVC_B/document.wflow" 2>/dev/null)" "0"
eq "B app bundle=finder"       "$(plutil -extract workflowMetaData.serviceApplicationBundleID raw -o - "$SVC_B/document.wflow" 2>/dev/null)" "com.apple.finder"

echo "== install (staged) =="
STAGE="$TMP/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
write_env_file "$STAGE/env.sh" "$NODE" "$CLI" "markdown"
env_loaded="$(NODE_BIN='' MICROTYPO_CLI='' MICROTYPO_SELECTION_INPUT='' bash -c '. "$1"; printf "%s\n%s\n%s\n" "$NODE_BIN" "$MICROTYPO_CLI" "$MICROTYPO_SELECTION_INPUT"' _ "$STAGE/env.sh")"
eq "env.sh has node path" "$(printf '%s\n' "$env_loaded" | sed -n '1p')" "$NODE"
eq "env.sh has cli path" "$(printf '%s\n' "$env_loaded" | sed -n '2p')" "$CLI"
eq "env.sh has selection input" "$(printf '%s\n' "$env_loaded" | sed -n '3p')" "markdown"

SPECIAL_NODE="$STAGE/node path & #'s"
SPECIAL_CLI="$STAGE/cli path & #'s.js"
SPECIAL_ENV="$STAGE/env-special.sh"
if write_env_file "$SPECIAL_ENV" "$SPECIAL_NODE" "$SPECIAL_CLI" "markdown"; then
  special_loaded="$(NODE_BIN='' MICROTYPO_CLI='' bash -c '. "$1"; printf "%s\n%s\n" "$NODE_BIN" "$MICROTYPO_CLI"' _ "$SPECIAL_ENV")"
  eq "env.sh preserves special node path" "$(printf '%s\n' "$special_loaded" | sed -n '1p')" "$SPECIAL_NODE"
  eq "env.sh preserves special cli path" "$(printf '%s\n' "$special_loaded" | sed -n '2p')" "$SPECIAL_CLI"
else
  bad "write_env_file special paths"
fi

echo "== release artifacts =="
REL_VERSION="$(cat "$REPO_DIR/VERSION")"
REL_TAG="v$REL_VERSION"
REL_BUNDLE="microtypo-actions-$REL_TAG"
REL_DIST="$TMP/release-dist"
REL_LOG="$TMP/release-build.log"
if "$REPO_DIR/scripts/build-release.sh" "$REL_TAG" "$REL_DIST" meritt/microtypo-actions >"$REL_LOG" 2>&1; then
  ok "build-release creates artifacts"
else
  bad "build-release failed ($(cat "$REL_LOG"))"
fi
if "$REPO_DIR/scripts/build-release.sh" v0.0.0-mismatch "$TMP/release-mismatch" meritt/microtypo-actions >/dev/null 2>&1; then
  bad "build-release accepts a tag that disagrees with VERSION"
else
  ok "build-release refuses a tag that disagrees with VERSION"
fi
REL_RELATIVE="$TMP/release-relative"
mkdir -p "$REL_RELATIVE"
if (cd "$REL_RELATIVE" && "$REPO_DIR/scripts/build-release.sh" "$REL_TAG" dist meritt/microtypo-actions >/dev/null 2>&1) \
  && [ -f "$REL_RELATIVE/dist/$REL_BUNDLE.tar.gz" ]; then
  ok "build-release supports relative out dir"
else
  bad "build-release relative out dir failed"
fi

REL_ARCHIVE="$REL_DIST/$REL_BUNDLE.tar.gz"
if [ -f "$REL_ARCHIVE" ]; then ok "release archive exists"; else bad "release archive missing"; fi
if [ -f "$REL_ARCHIVE.sha256" ]; then ok "release archive checksum exists"; else bad "release archive checksum missing"; fi
if [ -x "$REL_DIST/install.sh" ]; then ok "release bootstrap installer exists"; else bad "release bootstrap installer missing"; fi
if grep -q "DEFAULT_REPO='meritt/microtypo-actions'" "$REL_DIST/install.sh"; then
  ok "release bootstrap bakes repository"
else
  bad "release bootstrap repository missing"
fi
if (cd "$REL_DIST" && shasum -a 256 -c "$REL_BUNDLE.tar.gz.sha256" >/dev/null 2>&1); then
  ok "release checksum verifies"
else
  bad "release checksum does not verify"
fi

REL_CONTENTS="$(tar -tzf "$REL_ARCHIVE" 2>/dev/null)"
has_release_path() {
  if printf '%s\n' "$REL_CONTENTS" | grep -Fqx "$1"; then ok "$2"; else bad "$2"; fi
}
has_release_path "$REL_BUNDLE/install.sh" "release archive includes installer"
has_release_path "$REL_BUNDLE/uninstall.sh" "release archive includes uninstaller"
has_release_path "$REL_BUNDLE/VERSION" "release archive includes VERSION"
has_release_path "$REL_BUNDLE/src/common.sh" "release archive includes shared helpers"
has_release_path "$REL_BUNDLE/src/typograph-selection.sh" "release archive includes selection script"
has_release_path "$REL_BUNDLE/src/typograph-file.sh" "release archive includes file script"
has_release_path "$REL_BUNDLE/services/Microtypo Text.workflow/Contents/Info.plist" "release archive includes text workflow plist"
has_release_path "$REL_BUNDLE/services/Microtypo File.workflow/Contents/document.wflow" "release archive includes file workflow document"
if printf '%s\n' "$REL_CONTENTS" | grep -q '/tests/'; then bad "release archive includes tests"; else ok "release archive excludes tests"; fi
if printf '%s\n' "$REL_CONTENTS" | grep -q '\.DS_Store'; then bad "release archive includes .DS_Store"; else ok "release archive excludes .DS_Store"; fi

echo "== uninstall =="
U_APPSUP="$TMP/uninstall/appsup"
U_SERVICES="$TMP/uninstall/services"
U_LOG="$TMP/uninstall/microtypo.log"
setup_uninstall() {
  rm -rf "$TMP/uninstall"
  mkdir -p "$U_APPSUP" "$U_SERVICES/Microtypo Text.workflow" "$U_SERVICES/Microtypo File.workflow"
  printf 'x' > "$U_APPSUP/env.sh"
  printf 'x' > "$U_LOG"
}

setup_uninstall
MICROTYPO_APPSUP="$U_APPSUP" MICROTYPO_SERVICES="$U_SERVICES" MICROTYPO_LOG="$U_LOG" MICROTYPO_SKIP_PBS=1 \
  bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1
if [ ! -e "$U_APPSUP" ]; then ok "uninstall removes runtime"; else bad "uninstall left runtime"; fi
if [ ! -e "$U_SERVICES/Microtypo Text.workflow" ]; then ok "uninstall removes text workflow"; else bad "uninstall left text workflow"; fi
if [ ! -e "$U_SERVICES/Microtypo File.workflow" ]; then ok "uninstall removes file workflow"; else bad "uninstall left file workflow"; fi
if [ ! -e "$U_LOG" ]; then ok "uninstall removes log by default"; else bad "uninstall left log"; fi
if [ -d "$U_SERVICES" ]; then ok "uninstall keeps Services directory"; else bad "uninstall removed Services directory"; fi

setup_uninstall
MICROTYPO_APPSUP="$U_APPSUP" MICROTYPO_SERVICES="$U_SERVICES" MICROTYPO_LOG="$U_LOG" MICROTYPO_SKIP_PBS=1 \
  bash "$REPO_DIR/uninstall.sh" --keep-logs >/dev/null 2>&1
if [ -e "$U_LOG" ]; then ok "uninstall --keep-logs keeps log"; else bad "uninstall --keep-logs removed log"; fi
if [ ! -e "$U_APPSUP" ]; then ok "uninstall --keep-logs still removes runtime"; else bad "keep-logs left runtime"; fi

summary
