#!/usr/bin/env bash
# PostToolUse hook: formats and lints the file Claude just wrote.
#
# Three defects the audit found, fixed here:
#   - it ran `prettier --write` on *any* path, governance files included. A
#     CONSTITUTION.md or REGISTRY.md that the setup writes verbatim came back
#     reformatted, so the copy no longer matched the source.
#   - it sent stderr to /dev/null and always exited 0, so a formatter that could
#     not parse the file failed silently.
#   - it looked for `node_modules/.bin` at the current directory only, so in a
#     monorepo (where the binaries live in the package) it never ran at all.

set -uo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# ── Scope: code files only ────────────────────────────────────────────────────
#
# Markdown and JSON are excluded wholesale rather than by an exception list:
# governance docs, manifests and lock files are all content whose formatting is
# meaningful, and none of them gains anything from being rewritten here.

case "$FILE_PATH" in
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.vue|*.svelte|*.css|*.scss|*.sass) ;;
  *) exit 0 ;;
esac

# Generated and vendored trees are none of this hook's business.
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/coverage/*|*/vendor/*) exit 0 ;;
esac

# ── Per-package binary resolution ─────────────────────────────────────────────
#
# Walks up from the file towards the filesystem root and returns the first
# node_modules/.bin holding the requested tool: in an Nx or pnpm workspace that
# is the package's own copy, and the root copy is the fallback.

find_bin() {
  local tool="$1" dir
  dir="$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd)" || return 1

  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -x "$dir/node_modules/.bin/$tool" ]; then
      printf '%s' "$dir/node_modules/.bin/$tool"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

FAILED=""

# ── Prettier ──────────────────────────────────────────────────────────────────

if PRETTIER=$(find_bin prettier); then
  if ! PRETTIER_OUT=$("$PRETTIER" --write "$FILE_PATH" 2>&1); then
    FAILED="prettier"
    printf 'post-edit: prettier failed on %s\n%s\n' "$FILE_PATH" "$PRETTIER_OUT" >&2
  fi
fi

# ── ESLint ────────────────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.vue|*.svelte)
    if ESLINT=$(find_bin eslint); then
      if ! ESLINT_OUT=$("$ESLINT" --fix "$FILE_PATH" 2>&1); then
        FAILED="${FAILED:+$FAILED, }eslint"
        printf 'post-edit: eslint reported problems it could not fix in %s\n%s\n' \
          "$FILE_PATH" "$ESLINT_OUT" >&2
      fi
    fi
    ;;
esac

# Exit 2 makes the message above visible to Claude instead of only to the user:
# a rule ESLint cannot auto-fix is work still to do on the file just written.
[ -n "$FAILED" ] && exit 2

exit 0
