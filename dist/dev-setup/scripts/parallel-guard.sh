#!/usr/bin/env bash
# parallel-guard.sh — may the agent run the project's worktree commands itself.
#
# `new` and `adopt` write the worktree's `.env`, which the Bash sandbox denies,
# so by default the developer types them. A project can let the agent run them
# by excluding them from the sandbox — and an excluded command runs project
# code outside every OS boundary. That is safe only with three guards, and this
# script is the one place that checks them, so the answer is not a reading of
# settings the model can be generous with:
#
#   1. the excluded pattern is the direct invocation of a script file
#      (`node scripts/parallel.mjs new *`), never an alias: `pnpm wt` runs
#      whatever package.json says today, and package.json stays editable;
#   2. that file cannot be written from inside the session — a `denyWrite` in
#      the sandbox and an `Edit(...)` deny, which covers every file tool;
#   3. every run asks: `Bash(<command> *)` in `permissions.ask`.
#
# Usage:
#   parallel-guard.sh [--json]
#
# Keys:
#   GUARDED      true when the agent may run NEW_CMD and ADOPT_CMD itself
#   REASON       why not, empty when guarded
#   SANDBOX      true when the project's settings enable the sandbox
#   NEW_CMD      the `new` command of .claude/parallel.json, empty when null
#   ADOPT_CMD    the `adopt` command, empty when null
#   SCRIPTS      newline-separated script files those commands run
#   MISSING      newline-separated settings entries the guards still need
#
# Reads .claude/settings.json and .claude/settings.local.json of the main
# checkout, merged. Writes nothing.
#
# Exit: 0 answered (guarded or not) · 1 usage error or malformed JSON
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

# The main checkout, wherever this runs from: the commands are recorded there
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "not inside a git repository"
MAIN=$(dirname "$COMMON")
CONFIG="$MAIN/.claude/parallel.json"

GUARDED=false
REASON=""
SANDBOX=false
NEW_CMD=""
ADOPT_CMD=""
SCRIPTS=""
MISSING=""

# Both settings files, merged: the guards may sit in the developer's local one
SETTINGS='{}'
for file in "$MAIN/.claude/settings.json" "$MAIN/.claude/settings.local.json"; do
  [ -f "$file" ] || continue
  jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON"
  SETTINGS=$(jq -n --argjson a "$SETTINGS" --slurpfile b "$file" '
    def u(p): ((($a | p) // []) + (($b[0] | p) // [])) | unique;
    {
      enabled: (($a.enabled // false) or ($b[0].sandbox.enabled // false)),
      excluded: u(.excluded // .sandbox.excludedCommands),
      denyWrite: u(.denyWrite // .sandbox.filesystem.denyWrite),
      ask: u(.ask // .permissions.ask),
      deny: u(.deny // .permissions.deny)
    }')
done
[ "$(printf '%s' "$SETTINGS" | jq -r '.enabled // false')" = true ] && SANDBOX=true

has() { # has <list> <entry>
  printf '%s' "$SETTINGS" | jq -e --arg k "$1" --arg v "$2" '(.[$k] // []) | index($v) != null' >/dev/null
}
has_path() { # has_path <list> <wrapper-prefix> <file>: the forms a path rule is written in
  local list="$1" pre="$2" file="$3" form
  for form in "$file" "./$file" "/$file" "**/$file"; do
    if [ -n "$pre" ]; then has "$list" "$pre($form)" && return 0
    else has "$list" "$form" && return 0
    fi
  done
  return 1
}
need() { MISSING="${MISSING:+$MISSING$'\n'}$1"; }

if [ ! -f "$CONFIG" ]; then
  REASON="no .claude/parallel.json in the main checkout: the project has not recorded its worktree commands"
else
  jq -e . "$CONFIG" >/dev/null 2>&1 || die "$CONFIG is not valid JSON"
  NEW_CMD=$(jq -r '.new // empty' "$CONFIG")
  ADOPT_CMD=$(jq -r '.adopt // empty' "$CONFIG")

  if [ -z "$NEW_CMD" ] && [ -z "$ADOPT_CMD" ]; then
    REASON="parallel.json records neither new nor adopt"
  elif [ "$SANDBOX" != true ]; then
    REASON="the project's settings do not enable the sandbox: there is no boundary to guard, so run setup in UPDATE mode first"
  else
    for cmd in "$NEW_CMD" "$ADOPT_CMD"; do
      [ -n "$cmd" ] || continue
      # The script file the command runs: its first argument with a script extension
      file=$(printf '%s\n' "$cmd" | tr ' ' '\n' | grep -E '\.(mjs|cjs|js|ts|sh|py)$' | head -1)
      file="${file#./}"
      if [ -z "$file" ]; then
        REASON="\"$cmd\" runs no script file the sandbox can protect: record the direct invocation in parallel.json (node scripts/<file> …), not an alias"
        break
      fi
      case "$SCRIPTS" in *"$file"*) ;; *) SCRIPTS="${SCRIPTS:+$SCRIPTS$'\n'}$file" ;; esac
      has excluded "$cmd *" || need "sandbox.excludedCommands: $cmd *"
      has ask "Bash($cmd *)" || need "permissions.ask: Bash($cmd *)"
    done
    if [ -z "$REASON" ]; then
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        has_path denyWrite "" "$file" || need "sandbox.filesystem.denyWrite: $file"
        has_path deny Edit "$file" || need "permissions.deny: Edit(**/$file)"
      done <<< "$SCRIPTS"
      if [ -z "$MISSING" ]; then
        GUARDED=true
      else
        REASON="the settings lack $(printf '%s\n' "$MISSING" | grep -c .) of the guards that make running it outside the sandbox safe"
      fi
    fi
  fi
fi

json_set GUARDED "$GUARDED"
json_set REASON "$REASON"
json_set SANDBOX "$SANDBOX"
json_set NEW_CMD "$NEW_CMD"
json_set ADOPT_CMD "$ADOPT_CMD"
json_set SCRIPTS "$SCRIPTS"
json_set MISSING "$MISSING"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
