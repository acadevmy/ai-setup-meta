#!/usr/bin/env bash
# SessionStart hook (compact): re-injects the project context lost to compaction.
#
# Compaction is exactly where the context budget is tightest, so this hook stays
# small. Three changes against the version the audit reviewed:
#   - REGISTRY.md is capped instead of pasted whole: an ~800-line registry cost
#     more than the compaction saved.
#   - the three generic reminders are gone — CONSTITUTION, Conventional Commits
#     and the protected files are already in AGENTS.md, which is loaded anyway.
#   - the stack no longer comes from a STACK_PROFILE key in .env.local that no
#     step ever wrote (and that the sandbox denies reading): detect-stack.sh
#     derives it from the files on disk.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Project name ──────────────────────────────────────────────────────────────

PROJECT_NAME=""
if [ -f "package.json" ] && command -v jq >/dev/null 2>&1; then
  PROJECT_NAME=$(jq -r '.name // empty' package.json 2>/dev/null)
fi
[ -n "$PROJECT_NAME" ] || PROJECT_NAME=$(basename "$(pwd)")

# ── Stack, from detection rather than from a phantom variable ─────────────────

STACK_LINE=""
for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" \
  "$HOOK_DIR/../../scripts" \
  "$HOOK_DIR/../scripts"; do
  if [ -f "$CANDIDATE/detect-stack.sh" ]; then
    STACK_JSON=$(bash "$CANDIDATE/detect-stack.sh" --json 2>/dev/null || true)
    if [ -n "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
      STACK_LINE=$(printf '%s' "$STACK_JSON" | jq -r '
        [ .LANG,
          (if .FRAMEWORKS != "" then .FRAMEWORKS else empty end),
          (if .MONOREPO != "" then "monorepo: " + .MONOREPO else empty end)
        ] | join(" | ")' 2>/dev/null)
    fi
    break
  fi
done

# ── Output (stdout is appended to the context) ────────────────────────────────

printf '[Context re-injected after compaction]\n'
printf -- '- Project: %s\n' "$PROJECT_NAME"
[ -n "$STACK_LINE" ] && printf -- '- Stack: %s\n' "$STACK_LINE"

# ── REGISTRY.md, capped ───────────────────────────────────────────────────────
#
# The head carries the project map, which is what is worth paying for. The
# section index tells Claude what the rest holds, so it can read on demand.

REGISTRY_MAX_LINES=60

if [ -f "REGISTRY.md" ]; then
  TOTAL=$(wc -l < REGISTRY.md | tr -d ' ')
  printf '\n[REGISTRY.md — first %s of %s lines]\n' "$REGISTRY_MAX_LINES" "$TOTAL"
  head -n "$REGISTRY_MAX_LINES" REGISTRY.md

  if [ "$TOTAL" -gt "$REGISTRY_MAX_LINES" ]; then
    printf '\n[REGISTRY.md — remaining sections, read the file for the detail]\n'
    tail -n +"$((REGISTRY_MAX_LINES + 1))" REGISTRY.md | grep -E '^#{1,3} ' || true
  fi
fi

exit 0
