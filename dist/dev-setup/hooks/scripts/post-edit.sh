#!/usr/bin/env bash
# PostToolUse hook: formats and lints the file Claude just wrote.
#
# Three defects the audit found, fixed here:
#   - it ran `prettier --write` on *any* path, governance files included. A
#     REGISTRY.md or a generated rule that the setup writes verbatim came back
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

# What the model is told, collected here and sent once at the end.
REPORT=""

# Keeps the report readable: the tail is where a formatter puts its summary.
# A line cap, not a byte cap — the harness accepts 10,000 characters of
# additionalContext, and 40 lines per tool keeps a formatter's report inside
# that in practice, while a byte cap would cut exactly the tail that matters.
MAX_OUTPUT_LINES=40

# ── Prettier ──────────────────────────────────────────────────────────────────

if PRETTIER=$(find_bin prettier); then
  if ! PRETTIER_OUT=$("$PRETTIER" --write "$FILE_PATH" 2>&1); then
    REPORT="${REPORT}post-edit: prettier failed on $FILE_PATH
$(printf '%s\n' "$PRETTIER_OUT" | tail -n "$MAX_OUTPUT_LINES")
"
  fi
fi

# ── ESLint ────────────────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.vue|*.svelte)
    if ESLINT=$(find_bin eslint); then
      if ! ESLINT_OUT=$("$ESLINT" --fix "$FILE_PATH" 2>&1); then
        REPORT="${REPORT}post-edit: eslint reported problems it could not fix in $FILE_PATH
$(printf '%s\n' "$ESLINT_OUT" | tail -n "$MAX_OUTPUT_LINES")
"
      fi
    fi
    ;;
esac

# ── The report ────────────────────────────────────────────────────────────────
#
# A rule ESLint cannot auto-fix is work still to do on the file just written,
# and the model learns it through `additionalContext`: on PostToolUse that is
# the channel the hooks reference gives a hook with something to say, and it
# arrives next to the tool result rather than as a hook error (DE-17064). The
# exit code is 0 either way — the edit happened and stays.

if [ -n "$REPORT" ]; then
  jq -n --arg text "$REPORT" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $text}}'
fi

exit 0
