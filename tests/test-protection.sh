#!/usr/bin/env bash

# shellcheck disable=SC2088 # Quoted tilde paths are explicit test inputs.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/shorinniri"
TEST_ROOT="$(mktemp -d)"
TEST_HOME="$TEST_ROOT/home"
PROTECTED_LIST="$TEST_HOME/.config/shorin-niri/protected.list"

trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_HOME"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_file_equals() {
    local expected="$1"
    local actual
    actual="$(<"$PROTECTED_LIST")"
    [[ "$actual" == "$expected" ]] || fail "expected protected.list '$expected', got '$actual'"
}

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect .config/example/config.ini >/dev/null
assert_file_equals ".config/example/config.ini"

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect '~/.config/example/config.ini' >/dev/null
assert_file_equals ".config/example/config.ini"

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect "$TEST_HOME/.config/absolute/config.ini" >/dev/null
assert_file_equals $'.config/example/config.ini\n.config/absolute/config.ini'

if HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect ../outside >/dev/null 2>&1; then
    fail "path outside HOME was accepted"
fi
if HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect '~' >/dev/null 2>&1; then
    fail "HOME itself was accepted"
fi
if HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect '~another-user/config' >/dev/null 2>&1; then
    fail "another user's tilde path was accepted"
fi
if HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect '#comment-like/path' >/dev/null 2>&1; then
    fail "comment-prefixed path was accepted"
fi

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" unprotect '~/.config/example/config.ini' >/dev/null
assert_file_equals ".config/absolute/config.ini"

printf '%s\n' \
    '.config/relative/file' \
    '~/.config/tilde/file' \
    "$TEST_HOME/.config/absolute/file" \
    "$TEST_ROOT/outside" > "$PROTECTED_LIST"

result="$(HOME="$TEST_HOME" LANG=C bash -c '
    source "$1" protected-list >/dev/null
    build_ignore_list
    printf "ignore:%s\n" "${ALL_IGNORES[@]}"
    printf "invalid:%s\n" "${INVALID_IGNORE_RULES[@]}"
    is_ignored ".config/niri/binds.kdl" && printf "built-in-match\n"
    is_ignored ".config/relative/file" && printf "custom-match\n"
    is_ignored ".config/unrelated/file" || printf "unrelated-not-matched\n"
' _ "$SCRIPT")"

[[ "$result" == *"ignore:.config/niri"* ]] || fail "built-in rule was not normalized"
[[ "$result" == *"ignore:.config/relative/file"* ]] || fail "relative rule was not normalized"
[[ "$result" == *"ignore:.config/tilde/file"* ]] || fail "tilde rule was not normalized"
[[ "$result" == *"ignore:.config/absolute/file"* ]] || fail "absolute rule was not normalized"
[[ "$result" == *"invalid:"*"$TEST_ROOT/outside"* ]] || fail "outside-HOME rule was not reported"
[[ "$result" == *"built-in-match"* ]] || fail "built-in directory did not protect a child file"
[[ "$result" == *"custom-match"* ]] || fail "exact custom rule did not match"
[[ "$result" == *"unrelated-not-matched"* ]] || fail "unrelated path was incorrectly protected"

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" unprotect .config/tilde/file >/dev/null
assert_file_equals "$(printf '%s\n' \
    '.config/relative/file' \
    "$TEST_HOME/.config/absolute/file" \
    "$TEST_ROOT/outside")"

printf '%s' '~/.config/no-newline/file' > "$PROTECTED_LIST"
result="$(HOME="$TEST_HOME" LANG=C bash -c '
    source "$1" protected-list >/dev/null
    build_ignore_list
    printf "%s\n" "${ALL_IGNORES[@]}"
' _ "$SCRIPT")"
[[ "$result" == *".config/no-newline/file"* ]] || fail "final rule without a newline was ignored"

HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect .config/after-no-newline/file >/dev/null
assert_file_equals $'~/.config/no-newline/file\n.config/after-no-newline/file'

: > "$PROTECTED_LIST"
pids=()
for i in $(seq 1 20); do
    HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect ".config/concurrent/$i" >/dev/null &
    pids+=("$!")
done
for pid in "${pids[@]}"; do
    wait "$pid"
done
mapfile -t concurrent_rules < "$PROTECTED_LIST"
[[ ${#concurrent_rules[@]} -eq 20 ]] || fail "concurrent protect calls lost rules"

LOCK_TARGET="$TEST_ROOT/lock-target"
printf '%s\n' 'must remain intact' > "$LOCK_TARGET"
ln -s "$LOCK_TARGET" "$PROTECTED_LIST.lock"
HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect .config/lock-safety/file >/dev/null
[[ "$(<"$LOCK_TARGET")" == "must remain intact" ]] || fail "a symlinked legacy lock path was modified"
rm -f "$PROTECTED_LIST.lock"

chmod 400 "$PROTECTED_LIST"
HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protected-list >/dev/null
if HOME="$TEST_HOME" LANG=C bash "$SCRIPT" protect .config/read-only/file >/dev/null 2>&1; then
    fail "protect modified a read-only protection list"
fi
chmod 600 "$PROTECTED_LIST"

TEMPLATE_DIR="$TEST_ROOT/templates"
mkdir -p \
    "$TEMPLATE_DIR/.config/niri" \
    "$TEMPLATE_DIR/.config/unprotected" \
    "$TEST_HOME/.config/niri" \
    "$TEST_HOME/.config/unprotected"
printf '%s\n' 'template binding' > "$TEMPLATE_DIR/.config/niri/binds.kdl"
printf '%s\n' 'template value' > "$TEMPLATE_DIR/.config/unprotected/config.ini"
printf '%s\n' 'custom binding' > "$TEST_HOME/.config/niri/binds.kdl"
printf '%s\n' 'old value' > "$TEST_HOME/.config/unprotected/config.ini"

HOME="$TEST_HOME" LANG=C bash -c '
    source "$1" protected-list >/dev/null
    TEMPLATE_DIR="$2"
    BASE_BACKUP_DIR="$3/backups"
    BACKUP_DIR="$BASE_BACKUP_DIR/current"
    sync_dotfiles update >/dev/null
' _ "$SCRIPT" "$TEMPLATE_DIR" "$TEST_ROOT"

[[ "$(<"$TEST_HOME/.config/niri/binds.kdl")" == "custom binding" ]] || \
    fail "update overwrote a file covered by a built-in directory rule"
[[ "$(<"$TEST_HOME/.config/unprotected/config.ini")" == "template value" ]] || \
    fail "update did not replace an unprotected file"

BROKEN_HOME="$TEST_ROOT/broken-home"
BROKEN_TEMPLATE="$TEST_ROOT/broken-template"
mkdir -p \
    "$BROKEN_HOME/.config/shorin-niri/protected.list" \
    "$BROKEN_TEMPLATE/.config/example"
printf '%s\n' 'template value' > "$BROKEN_TEMPLATE/.config/example/config.ini"
if HOME="$BROKEN_HOME" LANG=C bash -c '
    source "$1" protected-list >/dev/null 2>&1
    TEMPLATE_DIR="$2"
    BASE_BACKUP_DIR="$3/backups"
    BACKUP_DIR="$BASE_BACKUP_DIR/current"
    sync_dotfiles update >/dev/null 2>&1
' _ "$SCRIPT" "$BROKEN_TEMPLATE" "$TEST_ROOT"; then
    fail "update continued with a non-regular protection list"
fi
[[ ! -e "$BROKEN_HOME/.config/example/config.ini" ]] || \
    fail "failed-open update copied files despite an unavailable protection list"

DENIED_HOME="$TEST_ROOT/denied-home"
DENIED_TEMPLATE="$TEST_ROOT/denied-template"
mkdir -p \
    "$DENIED_HOME/.config/shorin-niri" \
    "$DENIED_TEMPLATE/.config/example"
printf '%s\n' '.config/example/config.ini' > "$DENIED_HOME/.config/shorin-niri/protected.list"
printf '%s\n' 'template value' > "$DENIED_TEMPLATE/.config/example/config.ini"
chmod 000 "$DENIED_HOME/.config/shorin-niri"
if HOME="$DENIED_HOME" LANG=C bash -c '
    source "$1" protected-list >/dev/null 2>&1
    TEMPLATE_DIR="$2"
    BASE_BACKUP_DIR="$3/backups"
    BACKUP_DIR="$BASE_BACKUP_DIR/current"
    sync_dotfiles update >/dev/null 2>&1
' _ "$SCRIPT" "$DENIED_TEMPLATE" "$TEST_ROOT"; then
    chmod 700 "$DENIED_HOME/.config/shorin-niri"
    fail "update continued with an inaccessible protection directory"
fi
chmod 700 "$DENIED_HOME/.config/shorin-niri"
[[ ! -e "$DENIED_HOME/.config/example/config.ini" ]] || \
    fail "update copied files while the protection directory was inaccessible"

echo "Protection tests passed."
