#!/usr/bin/env bash
# common.sh — shared helpers for the dev-setup plugin scripts.
#
# Script contract (decision 7 of the dev-setup revision):
#   - bash + jq, no other runtime dependency
#   - `--json` prints a flat object with UPPER_SNAKE keys on stdout
#   - diagnostics and errors go to stderr, never to stdout
#   - a failure exits with a status other than 0
#
# Sourced, never executed directly.

# shellcheck shell=bash

# ── Diagnostics (stderr only: stdout is the JSON contract) ────────────────────

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq not found: install it with 'brew install jq' or 'apt-get install jq'"
}

# ── JSON output ───────────────────────────────────────────────────────────────
#
# Collect the pairs with `json_set KEY VALUE`, then emit them with `json_emit`.
# Values are always encoded as JSON strings, so any character is safe. Keys are
# emitted in insertion order and every key is written exactly once (a second
# json_set on the same key overwrites the first).

JSON_KEYS=()
JSON_VALUES=()

json_set() {
  local key="$1" value="${2-}" i
  for i in "${!JSON_KEYS[@]}"; do
    if [ "${JSON_KEYS[$i]}" = "$key" ]; then
      JSON_VALUES[i]="$value"
      return 0
    fi
  done
  JSON_KEYS+=("$key")
  JSON_VALUES+=("$value")
}

json_get() {
  local key="$1" i
  for i in "${!JSON_KEYS[@]}"; do
    if [ "${JSON_KEYS[$i]}" = "$key" ]; then
      printf '%s' "${JSON_VALUES[$i]}"
      return 0
    fi
  done
  return 1
}

json_emit() {
  local args=() i
  for i in "${!JSON_KEYS[@]}"; do
    args+=(--arg "${JSON_KEYS[$i]}" "${JSON_VALUES[$i]}")
  done
  if [ ${#args[@]} -eq 0 ]; then
    printf '{}\n'
    return 0
  fi
  jq -n "${args[@]}" '$ARGS.named'
}

# Human-readable rendering of the same pairs, for a run without `--json`.
json_emit_text() {
  local i
  for i in "${!JSON_KEYS[@]}"; do
    printf '%s=%s\n' "${JSON_KEYS[$i]}" "${JSON_VALUES[$i]}"
  done
}

# ── Repository helpers ────────────────────────────────────────────────────────

# Prints the repository root, or the current directory when there is no VCS.
repo_root() {
  if git rev-parse --show-toplevel 2>/dev/null; then
    return 0
  fi
  pwd
}

# Prints the detected VCS: git | none. Only git is supported today; the key
# exists so the consumers do not have to guess.
detect_vcs() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git'
  else
    printf 'none'
  fi
}

# Prints the base branch of the current work, resolved from the repository and
# never hard-coded: on a project targeting `next` or `develop`, assuming `main`
# makes the diff cover the whole delta between the two long-lived branches
# instead of the branch's own commits.
#
# Among the candidates (the explicit upstream, the remote default branch, and
# the usual long-lived names) the winner is the one HEAD forked from *most
# recently* — the fewest commits between its merge base and HEAD. On a stacked
# branch cut from `next` in a repo whose default is `main`, that picks `next`,
# which is the only answer that makes the diff mean "this branch's work".
#
# Prints nothing and returns 1 when no base can be resolved (a fresh repo with
# a single branch, say).
detect_base_branch() {
  local current upstream remote_head candidate
  local mb ahead behind
  local best="" best_ahead=-1 best_behind=-1

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  git rev-parse HEAD >/dev/null 2>&1 || return 1

  # Candidate list, in tie-break order.
  local candidates=""

  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  if [ -n "$upstream" ] && [ "${upstream##*/}" != "$current" ]; then
    candidates="$upstream"
  fi

  remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$remote_head" ] && [ "${remote_head##*/}" != "$current" ]; then
    candidates="$candidates $remote_head"
  fi

  for candidate in main master develop next; do
    [ "$candidate" = "$current" ] && continue
    candidates="$candidates origin/$candidate $candidate"
  done

  # Two keys, in order:
  #   ahead  — commits on HEAD since the merge base. The base HEAD forked from
  #            most recently gives the smallest value, and it is the only one
  #            for which the diff means "this branch's work".
  #   behind — commits on the candidate since the merge base, as the tie-break.
  #            A branch cut straight from `main` ties with `next` on `ahead`;
  #            `main` wins because it has not moved on past the fork point.
  for candidate in $candidates; do
    git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 || continue

    mb=$(git merge-base HEAD "$candidate" 2>/dev/null) || continue
    [ -n "$mb" ] || continue

    ahead=$(git rev-list --count "$mb..HEAD" 2>/dev/null) || continue
    behind=$(git rev-list --count "$mb..$candidate" 2>/dev/null) || continue

    if [ "$best_ahead" -lt 0 ] \
      || [ "$ahead" -lt "$best_ahead" ] \
      || { [ "$ahead" -eq "$best_ahead" ] && [ "$behind" -lt "$best_behind" ]; }; then
      best="$candidate"
      best_ahead="$ahead"
      best_behind="$behind"
    fi
  done

  [ -n "$best" ] || return 1
  printf '%s' "$best"
}

# Prints the merge base between HEAD and the given ref — the point the branch
# forked from. This is what the diff has to be taken against: `git diff <ref>`
# on a stale local ref shows the other branch's commits too.
merge_base_with() {
  local base="$1"
  [ -n "$base" ] || return 1
  git merge-base HEAD "$base" 2>/dev/null
}

# ── Slug helper ───────────────────────────────────────────────────────────────

# Turns free text into a branch-safe slug: lowercase, non-alphanumerics folded
# to single dashes, trimmed, capped at the given length (default 40).
#
# The folding runs through `tr -cs`, not through sed: `\+` is a GNU extension
# that BSD sed (the one on macOS) treats as a literal plus, which left every
# space in place.
slugify() {
  local text="$1" max="${2:-40}"
  printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | cut -c "1-$max" \
    | sed -e 's/^-//' -e 's/-$//'
}
