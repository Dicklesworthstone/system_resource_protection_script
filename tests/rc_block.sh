#!/usr/bin/env bash
# Regression test for the SRPS block in a user's shell rc file.
#
# It extracts the rc-block functions from install.sh and runs them, under the
# installer's own `set -euo pipefail`, against sandbox rc files in a temp dir.
# Nothing outside that temp dir is touched and no root is needed.
#
# What it pins:
#   - a fresh rc gets one block; an older block is replaced IN PLACE (same
#     position, every other line unchanged) with the previous file kept as
#     <rc>.srps-bak; re-runs and plan mode change nothing;
#   - an rc with damaged markers (start without end, end without start,
#     duplicates, wrong order) is left byte-identical by install AND uninstall.
#     A `sed '/START/,/END/d'` with the end marker missing deletes to end of file;
#   - a symlinked rc stays a symlink;
#   - the block exports TMPDIR=/data/tmp only where /data/tmp is a writable dir.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

W="$(mktemp -d)"
fail=0
ok() { echo "[rc_block] PASS $*"; }
bad() { echo "[rc_block] FAIL $*"; fail=1; }
START='# >>> system_resource_protection_script >>>'
END='# <<< system_resource_protection_script <<<'

fn() { sed -n "/^$1() {\$/,/^}\$/p" install.sh; }
{
  cat <<'STUB'
set -euo pipefail
print_success(){ echo "OK: $*"; }; print_info(){ echo "INFO: $*"; }; print_warning(){ echo "WARN: $*"; }
print_step(){ echo "STEP: $*"; }
detect_shell_rc(){ :; }
ENABLE_SHELL_ALIASES=1
STUB
  grep -E "^SRPS_RC_(START|END)=" install.sh
  for f in srps_rc_block_lines srps_rc_rewrite_block srps_shell_block configure_shell_aliases uninstall_shell_snippets; do
    fn "$f"
  done
} > "$W/fns.sh"
for f in srps_rc_block_lines srps_rc_rewrite_block srps_shell_block configure_shell_aliases uninstall_shell_snippets; do
  grep -q "^$f() {\$" "$W/fns.sh" || { echo "[rc_block] FAIL cannot find $f in install.sh"; exit 1; }
done

run() { DRY_RUN="${DRY:-0}" SHELL_RC="$W/rc" bash -c "source '$W/fns.sh'; configure_shell_aliases" 2>&1; }
uninstall() { HOME="$W/home" bash -c "source '$W/fns.sh'; uninstall_shell_snippets" 2>&1; }
blocks() { grep -c -x -F -- "$START" "$W/rc"; }
# An rc as an older installer left it: user line, blank line, old block, user lines.
oldblock() { printf 'export FOO=1\n\n%s\nexport TMPDIR=/tmp\nexport CARGO_TARGET_DIR=/tmp/cargo-target\n%s\nexport AFTER=2\nalias later=true\n' "$START" "$END" > "$W/rc"; }
outside() { # the file without its block
  local s e
  s=$(grep -n -x -F -- "$START" "$1" | cut -d: -f1); e=$(grep -n -x -F -- "$END" "$1" | cut -d: -f1)
  sed "${s},${e}d" "$1"
}

# fresh rc
printf 'export FOO=1\n' > "$W/rc"; run >/dev/null
[ "$(blocks)" = 1 ] && grep -q '^export FOO=1$' "$W/rc" && ok "fresh rc: one block appended" || bad "fresh rc"

# old block replaced in place, backup kept
oldblock; cp "$W/rc" "$W/rc.orig"; msg=$(run)
[ "$(blocks)" = 1 ] && ! grep -q '^export TMPDIR=/tmp$' "$W/rc" && grep -q 'if \[ -d /data/tmp \]' "$W/rc" && ok "old block replaced" || bad "old block not replaced: $msg"
s=$(grep -n -x -F -- "$START" "$W/rc" | cut -d: -f1); e=$(grep -n -x -F -- "$END" "$W/rc" | cut -d: -f1)
foo=$(grep -n '^export FOO=1$' "$W/rc" | cut -d: -f1); aft=$(grep -n '^export AFTER=2$' "$W/rc" | cut -d: -f1)
[ "$foo" -lt "$s" ] && [ "$e" -lt "$aft" ] && ok "block kept its position" || bad "block moved: FOO=$foo block=$s-$e AFTER=$aft"
diff <(outside "$W/rc") <(outside "$W/rc.orig") >/dev/null && ok "lines outside the block unchanged" || bad "lines outside the block changed"
cmp -s "$W/rc.srps-bak" "$W/rc.orig" && ok "backup equals the previous file" || bad "backup missing or wrong"

# idempotent, and plan mode
cp "$W/rc" "$W/rc.before"; for _ in 1 2 3; do run >/dev/null; done
cmp -s "$W/rc" "$W/rc.before" && ok "re-runs leave the file identical" || bad "re-runs changed the file"
oldblock; cp "$W/rc" "$W/rc.before"; msg=$(DRY=1 run)
cmp -s "$W/rc" "$W/rc.before" && echo "$msg" | grep -q 'Would update' && ok "plan mode changes nothing" || bad "plan mode: $msg"

# plan mode never touches or creates the rc file; a re-run does not touch it either
printf 'export FOO=1\n' > "$W/rc"; touch -d '2020-01-01 00:00:00' "$W/rc"; before=$(stat -c %Y "$W/rc")
DRY=1 run >/dev/null
[ "$(stat -c %Y "$W/rc")" = "$before" ] && [ "$(blocks)" = 0 ] && ok "plan mode on an rc without a block: content and mtime unchanged" || bad "plan mode touched the rc"
rm -f "$W/rc"; DRY=1 run >/dev/null
[ ! -e "$W/rc" ] && ok "plan mode does not create a missing rc" || bad "plan mode created the rc"
run >/dev/null
[ "$(blocks)" = 1 ] && ok "a real run creates a missing rc with one block" || bad "missing rc not created"
touch -d '2020-01-01 00:00:00' "$W/rc"; before=$(stat -c %Y "$W/rc"); run >/dev/null
[ "$(stat -c %Y "$W/rc")" = "$before" ] && ok "re-run with a current block: mtime unchanged" || bad "re-run touched the rc"

# damaged markers: untouched by install
damaged() {
  printf '%b' "$2" > "$W/rc"; cp "$W/rc" "$W/rc.before"; rm -f "$W/rc.srps-bak"
  msg=$(run); rc=$?
  cmp -s "$W/rc" "$W/rc.before" && echo "$msg" | grep -q 'damaged SRPS block' && [ "$rc" -eq 0 ] && [ ! -e "$W/rc.srps-bak" ] \
    && ok "damaged ($1): untouched, warned" || bad "damaged ($1): rc=$rc $msg"
}
damaged "start, no end"    "line1\n$START\nexport TMPDIR=/tmp\nline4\nline5\nline6\n"
damaged "end, no start"    "line1\nexport TMPDIR=/tmp\n$END\nline4\n"
damaged "two starts"       "line1\n$START\nx\n$START\ny\n$END\nline7\n"
damaged "two ends"         "line1\n$START\nx\n$END\ny\n$END\nline7\n"
damaged "end before start" "line1\n$END\nx\n$START\nline5\n"

# marker text inside another line is not a block
printf 'echo "see %s docs"\nexport FOO=1\n' "$START" > "$W/rc"; run >/dev/null
[ "$(blocks)" = 1 ] && grep -q '^echo "see ' "$W/rc" && ok "marker text inside another line ignored" || bad "unanchored marker"

# symlinked rc stays a symlink
mkdir -p "$W/dot"; oldblock; mv "$W/rc" "$W/dot/bashrc"; ln -s "$W/dot/bashrc" "$W/rc"; run >/dev/null
[ -L "$W/rc" ] && grep -q 'if \[ -d /data/tmp \]' "$W/dot/bashrc" && ok "symlinked rc stays a symlink" || bad "symlinked rc"
rm -f "$W/rc"

# the block on a host without /data/tmp (path substituted so the test is host-independent)
bash -c "source '$W/fns.sh'; srps_shell_block" | sed 's#/data/tmp#/nonexistent-srps/tmp#g' > "$W/block-nodata.sh"
out=$(env -u TMPDIR -u CARGO_TARGET_DIR bash -c "source '$W/block-nodata.sh'; echo \$TMPDIR \$CARGO_TARGET_DIR")
[ "$out" = "/tmp /tmp/cargo-target" ] && ok "without /data/tmp: TMPDIR defaults to /tmp" || bad "without /data/tmp: $out"
out=$(TMPDIR=/var/tmp bash -c "source '$W/block-nodata.sh'; echo \$TMPDIR")
[ "$out" = "/var/tmp" ] && ok "without /data/tmp: an existing TMPDIR is kept" || bad "existing TMPDIR: $out"

# uninstall: a good block is removed in place, a damaged file is left alone
mkdir -p "$W/home"; oldblock; run >/dev/null; cp "$W/rc" "$W/home/.bashrc"
printf 'line1\n%s\nexport X=1\nline4\nline5\n' "$START" > "$W/home/.zshrc"; cp "$W/home/.zshrc" "$W/zshrc.before"
msg=$(uninstall)
! grep -q -x -F -- "$START" "$W/home/.bashrc" && ! grep -q -x -F -- "$END" "$W/home/.bashrc" && grep -q '^export FOO=1$' "$W/home/.bashrc" \
  && grep -q '^alias later=true$' "$W/home/.bashrc" && [ -e "$W/home/.bashrc.srps-bak" ] && ok "uninstall removes a good block, keeps user lines" || bad "uninstall: $msg"
cmp -s "$W/home/.zshrc" "$W/zshrc.before" && echo "$msg" | grep -q 'damaged SRPS block' && ok "uninstall leaves a damaged rc untouched" || bad "uninstall damaged: $msg"

rm -rf "$W"
if [ "$fail" -eq 0 ]; then echo "[rc_block] done"; else echo "[rc_block] FAILED"; fi
exit "$fail"
