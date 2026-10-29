#!/usr/bin/env bash
# test-plugin-scripts.sh — tests for the dev-setup plugin scripts and hooks.
#
# Covers the four acceptance criteria of DE-16476:
#   1. detect-stack.sh --json against Next/NestJS/Flutter/monorepo fixtures
#      (snapshot comparison)
#   2. gate-commit.sh in full-gate mode: red suite -> deny with the real output,
#      green suite -> the commit goes through
#   3. gate-commit.sh in anti-bypass mode: with a hook manager it runs no check
#      of its own, and HUSKY=0 is refused
#   4. check-prerequisites.sh on a repository whose base is `next`: the diff
#      holds only the branch's own commits
# Plus, for DE-16477: every rule template renders from detect-stack output, and
# core.md is the only one that loads unconditionally.
# Plus, for DE-16479: the auto-sdd workflow script compiles the way the harness
# compiles it, its meta matches the name the launcher calls, and the surface the
# workflow replaced (three agents, two standalone skills) is gone.
# Plus, for DE-16480: worktree-info.sh gives two worktrees different dev-server
# ports and names the files they both declare, and the interactive flow invokes
# `simplify` once, asks no methodology question and mandates no bookkeeping
# commit.
# Plus, for DE-16487: the multi-sdd cap refuses six tasks with a non-zero exit,
# the overlap warning answers from pre-flight estimates before any worktree
# exists, and the command reimplements none of the workflow.
# Plus: the Challenge improves the spec and cannot stop the run — the workflow
# body runs under stubbed agents and comes back ready-for-mr whatever the
# reviewers say.
#
# Usage:
#   bash scripts/test-plugin-scripts.sh            # run the suite
#   bash scripts/test-plugin-scripts.sh --update   # rewrite the snapshots
#
# The work directory defaults to .tmp-script-tests/ inside the repository:
# mktemp under /var/folders is denied in a sandboxed session, and a repo-local
# path behaves the same locally and in CI. TEST_TMPDIR overrides it, and names a
# base to work *under*: the suite creates dev-setup-script-tests/ inside it and
# removes only that. Pointing it at a shared temp root is safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_SCRIPTS="$REPO_ROOT/templates/dev-setup/.claude/scripts"
PLUGIN_HOOKS="$REPO_ROOT/templates/dev-setup/.claude/hooks"
FIXTURES="$REPO_ROOT/scripts/fixtures"
# Resolved below: several of these tests need to create git repositories, which
# a sandboxed session refuses to do inside the project (writes under any .git/
# are blocked there, new repositories included).
WORK_DIR=""
EMPTY_GIT_TEMPLATE=""

# The two names this script owns. Nothing else is ever removed: the suite wipes
# its work directory on entry and on exit, and TEST_TMPDIR is a path the caller
# chose — quite possibly $TMPDIR, ~/tmp or another directory holding work that
# has nothing to do with these tests.
WORK_DIR_NAME="dev-setup-script-tests"
REPO_WORK_DIR_NAME=".tmp-script-tests"

# `rm -rf` goes through here, never straight at a variable.
discard_dir() {
  case "${1:-}" in
    */"$WORK_DIR_NAME"|*/"$REPO_WORK_DIR_NAME") rm -rf "$1" 2>/dev/null ;;
    *) echo "refusing to remove $1: not a directory this suite owns" >&2 ;;
  esac
  return 0
}

UPDATE=false
[ "${1:-}" = "--update" ] && UPDATE=true

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
DIM=$'\033[2m'
NC=$'\033[0m'

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '%s  ok%s  %s\n' "$GREEN" "$NC" "$1"; }

fail() {
  FAILED=$((FAILED + 1))
  printf '%sFAIL%s  %s\n' "$RED" "$NC" "$1"
  [ $# -gt 1 ] && printf '%s%s%s\n' "$DIM" "$2" "$NC"
}

# Asserts two strings are equal.
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label" "expected: $expected
  actual: $actual"
  fi
}

# Asserts the haystack contains the needle.
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) pass "$label" ;;
    *) fail "$label" "expected to contain: $needle
  got: $haystack" ;;
  esac
}

# The harness cannot run the harness's own hook matcher. The permissions
# reference gives one rule for the shapes the plugin uses — every `*` stands for
# any text, including none, and leading `VAR=value` assignments are stripped
# before matching — and bash pattern matching on the text between `Bash(` and
# `)` is that rule. Each segment of a compound command is checked on its own,
# as the hooks reference describes (DE-17064). The proxy does not strip quoted
# strings, so a `;`, `&` or `|` inside quotes splits a segment here where the
# hooks' own scan would not: keep the tables to shapes with no delimiter inside
# quotes.
if_matches() {
  local rule="$1" command="$2" glob segment
  glob="${rule#Bash(}"
  glob="${glob%)}"
  while IFS= read -r segment; do
    segment="${segment#"${segment%%[![:space:]]*}"}"
    while [[ "$segment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
      segment="${segment#"${BASH_REMATCH[0]}"}"
    done
    # shellcheck disable=SC2053
    [[ "$segment" == $glob ]] && return 0
  done <<EOF
$(printf '%s\n' "$command" | tr ';&|' '\n\n\n')
EOF
  return 1
}

# True when at least one of the newline-separated rules spawns the command.
rules_match() {
  local rules="$1" command="$2" rule
  while IFS= read -r rule; do
    [ -n "$rule" ] && if_matches "$rule" "$command" && return 0
  done <<EOF
$rules
EOF
  return 1
}

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# ── Git environment ───────────────────────────────────────────────────────────
#
# The developer's own configuration is neutralised: a global core.hooksPath
# would otherwise make HOOK_MANAGER detection differ between machines.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

# Every `git init` here uses an empty template directory. Git's default one
# lives outside the project (/usr/share, /opt/homebrew), which a sandboxed
# session cannot read — and a failed sample-hook copy aborts the whole init.
git_init() {
  local target="$1"
  mkdir -p "$EMPTY_GIT_TEMPLATE"
  git init --quiet --template="$EMPTY_GIT_TEMPLATE" "$target"
}

# ── Pick the work directory ───────────────────────────────────────────────────
#
# Candidates in order: a directory under an explicit TEST_TMPDIR, then a
# repo-local directory (what CI uses), then one under the system temp directory.
# Every candidate ends in a name this script owns, because it is created and
# removed wholesale — TEST_TMPDIR itself is never the work directory, and never
# the argument of an `rm -rf`.
#
# A candidate is only accepted if `git init` actually succeeds in it: under the
# sandbox the repo-local one fails, and silently losing the git-dependent tests
# would be worse than spending a probe on it.
pick_work_dir() {
  local candidate
  for candidate in \
    ${TEST_TMPDIR:+"${TEST_TMPDIR%/}/$WORK_DIR_NAME"} \
    "$REPO_ROOT/$REPO_WORK_DIR_NAME" \
    "${TMPDIR:-/tmp}/$WORK_DIR_NAME"; do

    discard_dir "$candidate"
    mkdir -p "$candidate/probe" 2>/dev/null || continue

    # `git init` creates .git/ before it writes the config, so neither the
    # directory existing nor `--is-inside-work-tree` proves anything: the latter
    # answers about the enclosing repository when the nested one is broken.
    # The repository is usable only if it reports itself as the top level.
    EMPTY_GIT_TEMPLATE="$candidate/.git-template"
    git_init "$candidate/probe" >/dev/null 2>&1

    # Both sides resolved with `pwd -P`: on macOS $TMPDIR sits under /tmp, which
    # is a symlink to /private/tmp, and git reports the physical path. Comparing
    # it against a logical `pwd` rejected a directory that works perfectly.
    if [ "$(cd "$(git -C "$candidate/probe" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P)" \
       = "$(cd "$candidate/probe" && pwd -P)" ]; then
      rm -rf "$candidate/probe"
      printf '%s' "$candidate"
      return 0
    fi

    discard_dir "$candidate"
  done
  return 1
}

WORK_DIR=$(pick_work_dir) || {
  echo "cannot find a directory where git repositories can be created." >&2
  echo "Set TEST_TMPDIR to a writable directory outside the project: the suite" >&2
  echo "works in $WORK_DIR_NAME/ inside it and removes nothing else." >&2
  exit 1
}

mkdir -p "$WORK_DIR" || { echo "cannot create $WORK_DIR" >&2; exit 1; }

EMPTY_GIT_TEMPLATE="$WORK_DIR/.git-template"
mkdir -p "$EMPTY_GIT_TEMPLATE"

# Without a ceiling, a work directory inside the repository would make git
# report the meta-repo as every fixture's VCS. The fixtures that need a
# repository create their own.
export GIT_CEILING_DIRECTORIES="$WORK_DIR"

printf 'work dir: %s\n' "$WORK_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# 1. detect-stack.sh snapshots
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── detect-stack.sh (fixture snapshots) ──"

for FIXTURE_DIR in "$FIXTURES"/*/; do
  [ -d "$FIXTURE_DIR" ] || continue
  NAME=$(basename "$FIXTURE_DIR")
  SNAPSHOT="$FIXTURES/$NAME.expected.json"

  # Run on a copy outside the repository: inside it, git would report the
  # meta-repo as the fixture's VCS.
  cp -R "$FIXTURE_DIR" "$WORK_DIR/$NAME"

  ACTUAL=$(cd "$WORK_DIR/$NAME" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json 2>/dev/null | jq -S .)

  if [ "$UPDATE" = true ]; then
    printf '%s\n' "$ACTUAL" > "$SNAPSHOT"
    pass "snapshot written: $NAME"
    continue
  fi

  if [ ! -f "$SNAPSHOT" ]; then
    fail "$NAME" "no snapshot at $SNAPSHOT — run with --update"
    continue
  fi

  EXPECTED=$(jq -S . "$SNAPSHOT")

  if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "detect-stack: $NAME"
  else
    fail "detect-stack: $NAME" "$(diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") | head -20)"
  fi
done

[ "$UPDATE" = true ] && { echo ""; echo "Snapshots updated."; exit 0; }

# ═══════════════════════════════════════════════════════════════════════════════
# 2. detect-stack.sh: HOOK_MANAGER, the flag the commit gate switches on
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── detect-stack.sh (hook manager detection) ──"

hook_manager_of() { (cd "$1" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json 2>/dev/null | jq -r '.HOOK_MANAGER'); }

assert_eq "husky detected" "husky" "$(hook_manager_of "$WORK_DIR/nextjs")"
assert_eq "lefthook detected" "lefthook" "$(hook_manager_of "$WORK_DIR/monorepo")"
assert_eq "no hook manager on a plain project" "" "$(hook_manager_of "$WORK_DIR/nestjs")"

# ── Determinism ──
# `find` walks in filesystem order, which is not the same on macOS and on the
# Linux CI runner. The list is sorted so that the same project always yields the
# same JSON; this pins the expected order rather than leaving it to a snapshot
# regenerated on whichever machine ran --update.
assert_eq "workspace frameworks come out in a stable order" \
  "nestjs,nextjs,terraform" \
  "$( (cd "$WORK_DIR/monorepo" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json) | jq -r '.FRAMEWORKS')"

# simple-git-hooks, declared in package.json rather than by a file
SGH="$WORK_DIR/simple-git-hooks"
mkdir -p "$SGH"
echo '{"name":"x","simple-git-hooks":{"pre-commit":"npm test"}}' > "$SGH/package.json"
assert_eq "simple-git-hooks detected" "simple-git-hooks" "$(hook_manager_of "$SGH")"

# a custom core.hooksPath
CHP="$WORK_DIR/custom-hookspath"
mkdir -p "$CHP"
git_init "$CHP"
git -C "$CHP" config core.hooksPath .githooks
assert_eq "custom core.hooksPath detected" "custom-hookspath" "$(hook_manager_of "$CHP")"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. check-prerequisites.sh: base branch resolved by merge-base
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── check-prerequisites.sh (base branch via merge-base) ──"

# A repository shaped like this one and like Corolla: default branch `main`,
# work targeting `next`, feature branch cut from `next`. The old
# `git diff main...HEAD` reported the whole main..next delta as part of the
# branch; the diff must hold the branch's own commit only.
SANDBOX="$WORK_DIR/base-branch-repo"
mkdir -p "$SANDBOX"
(
  cd "$SANDBOX" || exit 1
  git_init .
  git symbolic-ref HEAD refs/heads/main
  git config user.email "test@example.com"
  git config user.name "Test"

  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"

  git checkout --quiet -b next
  for i in 1 2 3; do
    echo "next change $i" > "next-$i.txt"
    git add . && git commit --quiet -m "feat: next change $i"
  done

  git checkout --quiet -b feat/DE-999-my-work
  echo "my work" > my-work.txt
  git add . && git commit --quiet -m "feat: my work"

  mkdir -p .specs
  printf -- '---\nstatus: approved\n---\n\n# DE-999\n\n## Implementation plan\n' > .specs/DE-999-my-work.md
  git add . && git commit --quiet -m "docs: spec for DE-999"
) >/dev/null 2>&1

PREREQ=$(cd "$SANDBOX" && bash "$PLUGIN_SCRIPTS/check-prerequisites.sh" --json 2>/dev/null)

assert_eq "base branch is next, not main" \
  "next" "$(printf '%s' "$PREREQ" | jq -r '.BASE_BRANCH')"

assert_eq "diff holds the branch's own files" \
  ".specs/DE-999-my-work.md
my-work.txt" "$(printf '%s' "$PREREQ" | jq -r '.CHANGED_FILES')"

# The regression this guards: with `main` hard-coded as the base, the three
# commits `next` carries over `main` were reported as part of the branch.
case "$(printf '%s' "$PREREQ" | jq -r '.CHANGED_FILES')" in
  *next-1.txt*|*next-2.txt*|*next-3.txt*)
    fail "the base commits leak into the diff" ;;
  *) pass "the commits next carries over main stay out of the diff" ;;
esac

assert_eq "task id read from the branch name" \
  "DE-999" "$(printf '%s' "$PREREQ" | jq -r '.TASK_ID')"

assert_contains "spec found" \
  "$(printf '%s' "$PREREQ" | jq -r '.SPEC')" ".specs/DE-999-my-work.md"

assert_eq "spec status read from the frontmatter" \
  "approved" "$(printf '%s' "$PREREQ" | jq -r '.SPEC_STATUS')"

assert_eq "a spec carrying its own plan section counts as the plan" \
  "$(printf '%s' "$PREREQ" | jq -r '.SPEC')" "$(printf '%s' "$PREREQ" | jq -r '.PLAN')"

# Untracked work belongs to the change set too.
echo "brand new" > "$SANDBOX/untracked.txt"
assert_contains "untracked files are included" \
  "$(cd "$SANDBOX" && bash "$PLUGIN_SCRIPTS/check-prerequisites.sh" --json 2>/dev/null | jq -r '.CHANGED_FILES')" \
  "untracked.txt"
rm -f "$SANDBOX/untracked.txt"

# --require-spec must fail loudly when there is no spec.
(cd "$SANDBOX" && bash "$PLUGIN_SCRIPTS/check-prerequisites.sh" --task DE-404 --require-spec --json) >/dev/null 2>&1
assert_eq "--require-spec exits non-zero without a spec" "1" "$?"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. sdd-start.sh: branch naming
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── sdd-start.sh (branch naming) ──"

sdd_start() { (cd "$SANDBOX" && bash "$PLUGIN_SCRIPTS/sdd-start.sh" "$@" 2>/dev/null); }

assert_eq "type, task id and slug" \
  "feat/DE-123_add-refresh-token-rotation" \
  "$(sdd_start --task DE-123 --title "Add refresh token rotation" --json | jq -r '.BRANCH')"

assert_eq "punctuation folded into single dashes" \
  "fix/DE-1_login-500-on-empty-body" \
  "$(sdd_start --task DE-1 --type fix --title "Login: 500 on empty body!" --json | jq -r '.BRANCH')"

assert_eq "no title, no slug" \
  "chore/DE-7" \
  "$(sdd_start --task DE-7 --type chore --json | jq -r '.BRANCH')"

assert_eq "the context goes in parentheses after the type" \
  "feat(auth)/DE-123_add-refresh-token-rotation" \
  "$(sdd_start --task DE-123 --context Auth --title "Add refresh token rotation" --json | jq -r '.BRANCH')"

assert_eq "a context without a task id" \
  "fix(ui)/typo-in-the-login-copy" \
  "$(sdd_start --type fix --context "UI" --title "Typo in the login copy" --json | jq -r '.BRANCH')"

sdd_start --task DE-9 --context "!!!" --json >/dev/null 2>&1
assert_eq "a context that slugifies to nothing is refused" "1" "$?"

sdd_start --task 'DE-1; rm -rf /' --json >/dev/null 2>&1
assert_eq "a task id carrying a shell command is refused" "1" "$?"

assert_eq "spec dir sits at the repository root" \
  "$(cd "$SANDBOX" && pwd -P)/.specs" \
  "$(sdd_start --task DE-7 --json | jq -r '.SPEC_DIR')"

assert_eq "a title alone names a branch, for a fix with no ticket" \
  "fix/typo-in-the-login-copy" \
  "$(sdd_start --type fix --title "Typo in the login copy" --json | jq -r '.BRANCH')"

sdd_start --task DE-9 --type banana --json >/dev/null 2>&1
assert_eq "an invalid type is refused" "1" "$?"

sdd_start --json >/dev/null 2>&1
assert_eq "neither --task nor --title is refused" "1" "$?"

sdd_start --type fix --title "!!!" --json >/dev/null 2>&1
assert_eq "a title that slugifies to nothing is refused" "1" "$?"

# ── --base: the caller overrides the resolved base (DE-16479) ──
#
# A worktree the harness created is branched from the remote default, so inside
# it the resolution below would answer `main` on a project whose work targets
# `next`. The workflow passes the base it resolved in the developer checkout.
assert_eq "without --base the repository answers" \
  "next" "$(sdd_start --task DE-5 --json | jq -r '.BASE_BRANCH')"

assert_eq "--base wins over the resolved base" \
  "main" "$(sdd_start --task DE-5 --base main --json | jq -r '.BASE_BRANCH')"

sdd_start --task DE-5 --base no/such/ref --json >/dev/null 2>&1
assert_eq "an unknown --base is refused" "1" "$?"

# And --create actually forks from it: the new branch sits on main's commit, not
# on the tip of the branch the script was called from.
sdd_start --task DE-5 --base main --create --json >/dev/null 2>&1
assert_eq "--create forks from the --base ref" \
  "$(cd "$SANDBOX" && git rev-parse main)" \
  "$(cd "$SANDBOX" && git rev-parse feat/DE-5 2>/dev/null)"
(cd "$SANDBOX" && git checkout --quiet feat/DE-999-my-work && git branch --quiet -D feat/DE-5) >/dev/null 2>&1

# --create never sets up tracking: from a remote base it would write
# branch.<name>.* into .git/config, which the Claude Code sandbox protects, and
# the branch would not be cut at all. `git push -u` sets the upstream later.
(cd "$SANDBOX" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=branch.autoSetupMerge GIT_CONFIG_VALUE_0=always \
  bash "$PLUGIN_SCRIPTS/sdd-start.sh" --task DE-5 --base main --create --json) >/dev/null 2>&1
assert_eq "--create cuts the branch without tracking its base" "" \
  "$(cd "$SANDBOX" && git config --get branch.feat/DE-5.merge)"
(cd "$SANDBOX" && git checkout --quiet feat/DE-999-my-work && git branch --quiet -D feat/DE-5) >/dev/null 2>&1

# ── --stop: the stop point survives the session (DE-17076) ──
#
# Chosen once at launch and read back on resume, so a resumed run does not ask
# it again. It sits beside the clock, in the common git directory.
assert_eq "nothing saved, nothing reported" \
  "" "$(sdd_start --task DE-6 --json | jq -r '.STOP_POINT')"

assert_eq "a report-only call with --stop writes nothing" \
  "" "$(sdd_start --task DE-6 --stop push --json | jq -r '.STOP_POINT')"

sdd_start --task DE-6 --stop push --create --json >/dev/null 2>&1
assert_eq "--create --stop saves the stop point, read back on resume" \
  "push" "$(sdd_start --task DE-6 --json | jq -r '.STOP_POINT')"
assert_eq "the stop point sits in the common git directory" \
  "push" "$(cd "$SANDBOX" && cat "$(git rev-parse --git-common-dir)/dev-setup/stop-point/DE-6" 2>/dev/null)"

assert_eq "--create --stop on the existing branch replaces it" \
  "commit" "$(sdd_start --task DE-6 --stop commit --create --json | jq -r '.STOP_POINT')"

sdd_start --task DE-6 --stop banana --json >/dev/null 2>&1
assert_eq "an invalid stop point is refused" "1" "$?"

sdd_start --type fix --title "Typo" --stop push --json >/dev/null 2>&1
assert_eq "--stop without --task is refused" "1" "$?"
(cd "$SANDBOX" && git checkout --quiet feat/DE-999-my-work && git branch --quiet -D feat/DE-6 \
  && rm -rf "$(git rev-parse --git-common-dir)/dev-setup/stop-point") >/dev/null 2>&1

# The task id is read back out of the branch name in both conventions: the
# current feat(auth)/DE-123_slug, and feat/DE-123-slug for a branch cut before it.
(cd "$SANDBOX" && git checkout --quiet -b "feat(auth)/DE-999_my-work") >/dev/null 2>&1
assert_eq "check-prerequisites reads the task id from a branch with a context" "DE-999" \
  "$(cd "$SANDBOX" && bash "$PLUGIN_SCRIPTS/check-prerequisites.sh" --json 2>/dev/null | jq -r '.TASK_ID')"
(cd "$SANDBOX" && git checkout --quiet feat/DE-999-my-work && git branch --quiet -D "feat(auth)/DE-999_my-work") >/dev/null 2>&1

# ═══════════════════════════════════════════════════════════════════════════════
# 4b. mr-meta.sh: the merge request's language, title and labels
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── mr-meta.sh (merge request metadata) ──"

MR_META_REPO="$WORK_DIR/mr-meta-repo"
mkdir -p "$MR_META_REPO"
(
  cd "$MR_META_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --quiet --allow-empty -m "chore: base"
  git checkout --quiet -b "feat(auth)/DE-321_add-refresh-token"
) >/dev/null 2>&1

mr_meta() { (cd "$MR_META_REPO" && bash "$PLUGIN_SCRIPTS/mr-meta.sh" --json "$@" 2>/dev/null); }

MR_NO_META=$(mr_meta --summary "Add refresh token rotation")
assert_eq "the title reads type and task id from the branch" \
  "Feat: Add refresh token rotation [DE-321]" "$(printf '%s' "$MR_NO_META" | jq -r '.TITLE')"
assert_eq "the context comes out of the parentheses" \
  "auth" "$(printf '%s' "$MR_NO_META" | jq -r '.CONTEXT')"
assert_eq "without a metadata file there is no language" \
  "" "$(printf '%s' "$MR_NO_META" | jq -r '.LANGUAGE')"
assert_eq "and no label is invented" \
  "" "$(printf '%s' "$MR_NO_META" | jq -r '.LABELS')"

mkdir -p "$MR_META_REPO/.claude" "$MR_META_REPO/.github"
cp "$REPO_ROOT/templates/dev-setup/boilerplate/merge-request.json" "$MR_META_REPO/.claude/merge-request.json"
: > "$MR_META_REPO/.github/PULL_REQUEST_TEMPLATE.md"

MR_META=$(mr_meta --summary "Aggiunta rotazione del refresh token" --priority High --breaking)
assert_eq "the shipped metadata is Italian" \
  "it" "$(printf '%s' "$MR_META" | jq -r '.LANGUAGE')"
assert_eq "the template is the one in the host's folder" \
  ".github/PULL_REQUEST_TEMPLATE.md" "$(printf '%s' "$MR_META" | jq -r '.TEMPLATE')"
assert_eq "labels in order: type, breaking, priority, on open" \
  "Type: Feature,Breaking Change,Priority: High,State: Pending" \
  "$(printf '%s' "$MR_META" | jq -r '.LABELS')"
assert_eq "a branch with no task id gets no brackets" \
  "Chore: Aggiornamento toolchain" \
  "$(mr_meta --branch chore/update-toolchain --summary "Aggiornamento toolchain" | jq -r '.TITLE')"

# The file is the developers' to edit: what they write is what the script reads.
jq '.language = "en" | .labels.by_type.feat = "Enhancement" | .labels.on_open = []' \
  "$REPO_ROOT/templates/dev-setup/boilerplate/merge-request.json" > "$MR_META_REPO/.claude/merge-request.json"
MR_EDITED=$(mr_meta)
assert_eq "an edited language is read back" "en" "$(printf '%s' "$MR_EDITED" | jq -r '.LANGUAGE')"
assert_eq "a single label where a list belongs is a list of one" \
  "Enhancement" "$(printf '%s' "$MR_EDITED" | jq -r '.LABELS')"

echo 'not json' > "$MR_META_REPO/.claude/merge-request.json"
mr_meta >/dev/null 2>&1
assert_eq "a malformed metadata file is an error, not an empty answer" "1" "$?"

mr_meta --priority whenever >/dev/null 2>&1
assert_eq "an unknown priority is refused" "1" "$?"

# ═══════════════════════════════════════════════════════════════════════════════
# 5. render-template.sh
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── render-template.sh ──"

TPL="$WORK_DIR/tpl.md"
printf '# {{PROJECT_NAME}}\n\nTest: `{{TEST_CMD}}`\n' > "$TPL"

assert_eq "placeholders substituted" \
  "# acme
Test: \`pnpm run test\`" \
  "$(bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" \
       --var PROJECT_NAME=acme --var TEST_CMD="pnpm run test" 2>/dev/null | grep -v '^$')"

# A value holding sed's metacharacters must survive verbatim.
assert_contains "value with & and / is literal" \
  "$(bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" \
       --var PROJECT_NAME='a&b/c\d' --var TEST_CMD=x 2>/dev/null)" \
  'a&b/c\d'

bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" --var PROJECT_NAME=acme >/dev/null 2>&1
assert_eq "an unresolved placeholder is an error" "1" "$?"

assert_contains "--allow-missing keeps the placeholder" \
  "$(bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" --var PROJECT_NAME=acme --allow-missing 2>/dev/null)" \
  "{{TEST_CMD}}"

assert_eq "--list reports the placeholders" \
  "PROJECT_NAME
TEST_CMD" \
  "$(bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" --list 2>/dev/null)"

# detect-stack's output feeds straight in as the variable set.
assert_contains "--vars-json consumes detect-stack output" \
  "$( (cd "$WORK_DIR/nextjs" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json) \
      | bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$TPL" --vars-json - --allow-missing 2>/dev/null)" \
  "pnpm run test"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. gate-commit.sh
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── gate-commit.sh ──"

# Feeds a PreToolUse payload to the hook and prints its stdout.
gate() {
  local dir="$1" command="$2"
  jq -n --arg cmd "$command" '{tool_name: "Bash", tool_input: {command: $cmd}}' \
    | (cd "$dir" && bash "$PLUGIN_HOOKS/gate-commit.sh" 2>/dev/null)
}

# A hook that stays silent has made no decision: the call proceeds through the
# normal permission flow. Only a JSON payload on stdout carries a decision.
decision_of() {
  [ -n "$1" ] || { printf 'none'; return 0; }
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || printf 'none'
}

reason_of() {
  [ -n "$1" ] || return 0
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null
}

# ── Commands the gate must ignore ──
assert_eq "a non-commit command is ignored" \
  "none" "$(decision_of "$(gate "$SANDBOX" 'git status')")"

assert_eq "git log with a commit format is ignored" \
  "none" "$(decision_of "$(gate "$SANDBOX" 'git log --format=%H -1')")"

assert_eq "a mention of the word commit is ignored" \
  "none" "$(decision_of "$(gate "$SANDBOX" 'echo "about to commit"')")"

# ── Anti-bypass ──
assert_eq "--no-verify is refused" \
  "deny" "$(decision_of "$(gate "$SANDBOX" 'git commit -m "wip" --no-verify')")"

assert_eq "-n is refused" \
  "deny" "$(decision_of "$(gate "$SANDBOX" 'git commit -n -m "wip"')")"

assert_eq "HUSKY=0 is refused" \
  "deny" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'HUSKY=0 git commit -m "wip"')")"

assert_eq "a core.hooksPath override is refused" \
  "deny" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git -c core.hooksPath=/dev/null commit -m "wip"')")"

assert_eq "LEFTHOOK=0 is refused" \
  "deny" "$(decision_of "$(gate "$WORK_DIR/monorepo" 'LEFTHOOK=0 git commit -m "wip"')")"

# The bypass scan must read flags, not the commit message.
assert_eq "a message mentioning HUSKY=0 is not a bypass" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "docs: explain HUSKY=0"')")"

assert_eq "a message containing -n is not a bypass" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "fix: handle -n flag"')")"

# A flag belongs to the command that carries it. The gate used to scan the whole
# line, so any `-n` anywhere in a chained command refused the commit — which is
# how a quality gate teaches people to route around it.
assert_eq "another command's -n is not a bypass" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "feat: x" && git show --stat | sed -n "1,5p"')")"

assert_eq "another command's --no-verify is not a bypass" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'npm publish --no-verify && git commit -m "feat: x"')")"

assert_eq "-n on a second chained commit is still refused" \
  "deny" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "feat: a" && git commit -n -m "feat: b"')")"

# The environment bypasses keep the whole line: they work from a segment of
# their own, which the commit segment would never show.
assert_eq "HUSKY=0 exported in an earlier segment is refused" \
  "deny" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'export HUSKY=0 && git commit -m "feat: x"')")"

# ── Anti-bypass mode: no check of its own ──
# The husky fixture has "test": "jest" and no node_modules, so a check run here
# would fail. Getting no decision back proves the gate delegated instead.
assert_eq "with husky the gate runs no check of its own" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "feat: something"')")"

# ── The `if` rule: the gate spawns only on a git commit call (DE-17064) ──
#
# The handler carries `"if": "Bash(*git *commit*)"`, which is `is_git_commit`
# written in permission-rule syntax, so the harness never spawns the gate on a
# `git status`. Asserted on the generated hooks.json rather than the template:
# a builder that dropped the key would fail here.
HOOKS_JSON="$REPO_ROOT/dist/dev-setup/hooks/hooks.json"
GATE_HANDLERS="$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Bash")
  | .hooks[] | select(.command | endswith("/gate-commit.sh\""))]' "$HOOKS_JSON")"
assert_eq "the gate is mounted once as a PreToolUse hook on Bash" "1" \
  "$(printf '%s' "$GATE_HANDLERS" | jq 'length')"
GATE_RULE="$(printf '%s' "$GATE_HANDLERS" | jq -r '.[0].if // ""')"
assert_eq "and spawns on a git commit call only" "Bash(*git *commit*)" "$GATE_RULE"
# Twenty minutes, over the slowest suite measured (about 13), and no
# onFailure: a gate that runs out of time lets the commit through and says so.
assert_eq "with twenty minutes for the checks, and the commit never blocked by a timeout" "1200 none" \
  "$(printf '%s' "$GATE_HANDLERS" | jq -r '"\(.[0].timeout // "") \(.[0].onFailure // "none")"')"

for CMD in 'git status' 'git log --format=%H -1' 'npm test' 'echo "about to commit"'; do
  assert_eq "the rule leaves alone: $CMD" "false" \
    "$(if_matches "$GATE_RULE" "$CMD" && echo true || echo false)"
done
for CMD in 'git commit -m "x"' 'git commit' 'git -c core.hooksPath=/dev/null commit -m "x"' \
           'git -C dir commit -m "x"' 'HUSKY=0 git commit -m "x"' 'env HUSKY=0 git commit -m "x"'; do
  assert_eq "the rule spawns on: $CMD" "true" \
    "$(if_matches "$GATE_RULE" "$CMD" && echo true || echo false)"
done

# ── Full-gate mode ──
make_gate_project() {
  local dir="$1" test_exit="$2"
  mkdir -p "$dir"
  cat > "$dir/package.json" <<EOF
{
  "name": "gate-fixture",
  "scripts": { "test": "echo RUNNING_THE_SUITE && exit $test_exit" }
}
EOF
  git_init "$dir"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" add -A
}

if command -v npm >/dev/null 2>&1; then
  RED_PROJECT="$WORK_DIR/gate-red"
  make_gate_project "$RED_PROJECT" 1
  RED_OUT=$(gate "$RED_PROJECT" 'git commit -m "feat: thing"')

  assert_eq "a red suite denies the commit" "deny" "$(decision_of "$RED_OUT")"
  assert_contains "the reason carries the real suite output" \
    "$(reason_of "$RED_OUT")" "RUNNING_THE_SUITE"

  GREEN_PROJECT="$WORK_DIR/gate-green"
  make_gate_project "$GREEN_PROJECT" 0
  assert_eq "a green suite lets the commit through" \
    "none" "$(decision_of "$(gate "$GREEN_PROJECT" 'git commit -m "feat: thing"')")"

  # Nothing staged: git will refuse the commit itself, so the suite must not run.
  EMPTY_PROJECT="$WORK_DIR/gate-empty"
  make_gate_project "$EMPTY_PROJECT" 1
  git -C "$EMPTY_PROJECT" commit --quiet -m "chore: base"
  assert_eq "nothing to commit, no suite run" \
    "none" "$(decision_of "$(gate "$EMPTY_PROJECT" 'git commit -m "feat: thing"')")"

  # The hook runs before the whole line: in `git add -A && git commit` the index
  # is still empty when it looks. That is how a commit went in unchecked on
  # DE-17941, so the working tree counts too.
  echo 'change' > "$EMPTY_PROJECT/a.txt"
  assert_eq "git add -A && git commit is gated: the red suite denies it" \
    "deny" "$(decision_of "$(gate "$EMPTY_PROJECT" 'git add -A && git commit -m "feat: thing"')")"
  rm -f "$EMPTY_PROJECT/a.txt"

  # Out of time: the gate stops its checks itself before the harness's timeout,
  # lets the commit through and says so, and the branch keeps a note that
  # mr-meta.sh hands to the merge request. A budget of 3 s stands for 1140.
  SLOW_PROJECT="$WORK_DIR/gate-slow"
  make_gate_project "$SLOW_PROJECT" 0
  git -C "$SLOW_PROJECT" commit --quiet -m "chore: base"
  jq '.scripts.test = "echo SLOW_SUITE_STARTED && sleep 30"' "$SLOW_PROJECT/package.json" > "$SLOW_PROJECT/p.json" \
    && mv "$SLOW_PROJECT/p.json" "$SLOW_PROJECT/package.json"
  git -C "$SLOW_PROJECT" add -A
  SLOW_START=$(date +%s)
  SLOW_OUT=$(DEV_SETUP_GATE_BUDGET_S=3 gate "$SLOW_PROJECT" 'git commit -m "feat: thing"')
  SLOW_TOOK=$(( $(date +%s) - SLOW_START ))
  assert_eq "out of time: no decision, the commit goes on through the normal flow" \
    "none" "$(decision_of "$SLOW_OUT")"
  assert_eq "and the gate stopped its checks at its own budget, not the suite's 30 s" "true" \
    "$([ "$SLOW_TOOK" -lt 15 ] && echo true || echo "false ($SLOW_TOOK s)")"
  assert_contains "the model is told, as additionalContext" \
    "$(printf '%s' "$SLOW_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""')" "did not finish"
  assert_contains "the developer too, as a systemMessage" \
    "$(printf '%s' "$SLOW_OUT" | jq -r '.systemMessage // ""')" "committed unchecked"
  assert_contains "and mr-meta.sh hands the note to the merge request" \
    "$(cd "$SLOW_PROJECT" && bash "$PLUGIN_SCRIPTS/mr-meta.sh" --json 2>/dev/null | jq -r .UNCHECKED_AT_COMMIT)" \
    "tests (\`npm run test\`, stopped): not finished in 3 s"
  jq '.scripts.test = "echo fast"' "$SLOW_PROJECT/package.json" > "$SLOW_PROJECT/p.json" \
    && mv "$SLOW_PROJECT/p.json" "$SLOW_PROJECT/package.json"
  assert_eq "a later gate that finishes green lets the commit through" \
    "none" "$(decision_of "$(gate "$SLOW_PROJECT" 'git commit -am "feat: thing"')")"
  assert_eq "and clears the note: the whole tree is checked now" "" \
    "$(cd "$SLOW_PROJECT" && bash "$PLUGIN_SCRIPTS/mr-meta.sh" --json 2>/dev/null | jq -r .UNCHECKED_AT_COMMIT)"

  # The internal filter stays, for a client that ignores `if` and for the
  # compound commands the harness cannot narrow — and it is asserted where a
  # spawn would show. A gate that reached the checks here would deny (the
  # suite is red), so silence and exit 0 prove the filter, not an empty stack.
  RED_STATUS_OUT=$(gate "$RED_PROJECT" 'git status')
  RED_STATUS_RC=$?
  assert_eq "git status in a red project: no decision" "none" "$(decision_of "$RED_STATUS_OUT")"
  assert_eq "git status in a red project: empty stdout" "" "$RED_STATUS_OUT"
  assert_eq "git status in a red project: exit 0" "0" "$RED_STATUS_RC"

  # Every shape the hook acts on is one the rule spawns. A form the gate denies
  # that the rule never starts would be a silent gap: the rule is
  # `*git *commit*` rather than `git commit*` precisely for `git -c … commit`
  # and the `env` prefix, which the gate refuses today.
  for CMD in 'git commit -m "x"' 'git -c core.hooksPath=/dev/null commit -m "x"' \
             'HUSKY=0 git commit -m "x"' 'env HUSKY=0 git commit -m "x"' \
             'export HUSKY=0 && git commit -m "x"'; do
    assert_eq "the gate acts on: $CMD" "deny" "$(decision_of "$(gate "$RED_PROJECT" "$CMD")")"
    assert_eq "and the rule spawns it: $CMD" "true" \
      "$(if_matches "$GATE_RULE" "$CMD" && echo true || echo false)"
  done
else
  echo "  ${DIM}npm not found: full-gate execution tests skipped${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 6b. The quality commands are a declaration of the project (DE-17535)
# ═══════════════════════════════════════════════════════════════════════════════
#
# On DE-17472 detection found no stack it knew, returned three empty commands,
# and every consumer read "empty" as "the project has none": an autonomous run
# spent its whole budget without running a test. The commands are now declared
# by the project in `.claude/quality-commands.json`, which detect-stack.sh reads
# before its heuristics — and "declared absent" is a value, not an empty string.

echo ""
echo "── detect-stack.sh (the quality-commands declaration) ──"

stack_of() { (cd "$1" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json 2>/dev/null); }
stack_key() { stack_of "$1" | jq -r --arg k "$2" '.[$k]'; }

# Writes a declaration into a fresh directory under the work directory.
declare_in() {
  local dir="$1" json="$2"
  mkdir -p "$dir/.claude"
  printf '%s\n' "$json" > "$dir/.claude/quality-commands.json"
}

# REQ-2: the declaration wins over the heuristics, wholesale. The fixture's
# package.json has lint and test scripts and a tsconfig.json, so the heuristics
# would answer `npm run lint`, `npm run test` and `npx tsc --noEmit`.
assert_eq "a declared lint wins over the package.json script" \
  "make lint-all" "$(stack_key "$WORK_DIR/declared" LINT_CMD)"
assert_eq "a declared test wins over the package.json script" \
  "make test-all" "$(stack_key "$WORK_DIR/declared" TEST_CMD)"
# REQ-3: null is a decision, not a gap — never filled in from a heuristic.
assert_eq "a command declared absent stays empty, although tsconfig.json would give one" \
  "" "$(stack_key "$WORK_DIR/declared" TYPECHECK_CMD)"
assert_eq "and the source says the commands are declared" \
  "declared" "$(stack_key "$WORK_DIR/declared" COMMANDS_SOURCE)"
assert_eq "the declared preflight is reported" \
  "bin/check-toolchain.sh" "$(stack_key "$WORK_DIR/declared" PREFLIGHT_CMD)"

# REQ-4: without a declaration, "detected" means at least one heuristic
# command, and "none" means all three are empty — the case that must never
# reach an autonomous run unnoticed again.
for NAME in plain-node unknown-make laravel-api; do
  assert_eq "no declaration and nothing detected is none: $NAME" \
    "none" "$(stack_key "$WORK_DIR/$NAME" COMMANDS_SOURCE)"
done
for NAME in nestjs nextjs flutter monorepo; do
  assert_eq "no declaration and heuristic commands is detected: $NAME" \
    "detected" "$(stack_key "$WORK_DIR/$NAME" COMMANDS_SOURCE)"
done
LINT_ONLY="$WORK_DIR/lint-only"
mkdir -p "$LINT_ONLY"
echo '{"scripts":{"lint":"eslint ."}}' > "$LINT_ONLY/package.json"
assert_eq "one detected command is enough to be detected" \
  "detected" "$(stack_key "$LINT_ONLY" COMMANDS_SOURCE)"
assert_eq "no declaration, no preflight" "" "$(stack_key "$WORK_DIR/nestjs" PREFLIGHT_CMD)"
for SNAPSHOT in "$FIXTURES"/*.expected.json; do
  assert_eq "the snapshot carries the two new keys: $(basename "$SNAPSHOT")" "true" \
    "$(jq 'has("COMMANDS_SOURCE") and has("PREFLIGHT_CMD")' "$SNAPSHOT")"
done

# REQ-1: a malformed declaration is an error, not a guess. Exit non-zero, the
# cause on stderr, nothing on stdout — the precedent mr-meta.sh set.
slug_of() { printf '%s' "$1" | tr -cs 'A-Za-z0-9' '-'; }
malformed_case() {
  local label="$1" json="$2" dir out err rc
  dir="$WORK_DIR/malformed-$(slug_of "$label")"
  declare_in "$dir" "$json"
  out=$(cd "$dir" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json 2>"$dir.err")
  rc=$?
  err=$(cat "$dir.err")
  assert_eq "malformed ($label): non-zero exit" "true" "$([ "$rc" -ne 0 ] && echo true || echo false)"
  assert_eq "malformed ($label): nothing on stdout" "" "$out"
  assert_eq "malformed ($label): the cause on stderr" "true" "$([ -n "$err" ] && echo true || echo false)"
}

malformed_case "missing test key" '{"lint":"make lint","typecheck":null,"absent":{"typecheck":"none"}}'
malformed_case "empty-string lint" '{"lint":"","typecheck":"make types","test":"make test"}'
malformed_case "null without a reason" '{"lint":"make lint","typecheck":null,"test":"make test"}'
malformed_case "hook manager with a space" '{"lint":"make lint","typecheck":"make types","test":"make test","hook_manager":"a b"}'
malformed_case "invalid JSON" '{"lint": "make lint",'

# REQ-5: a declared hook manager is the hook manager, even one no detection
# rule knows. The gate then stands down to anti-bypass.
HM_PRECOMMIT="$WORK_DIR/hm-pre-commit"
declare_in "$HM_PRECOMMIT" '{"lint":"make lint","typecheck":"make types","test":"make test","hook_manager":"pre-commit"}'
assert_eq "a declared pre-commit is accepted" "pre-commit" "$(stack_key "$HM_PRECOMMIT" HOOK_MANAGER)"

HM_CAPTAIN="$WORK_DIR/hm-captainhook"
declare_in "$HM_CAPTAIN" '{"lint":"false","typecheck":null,"absent":{"typecheck":"none"},"test":"true","hook_manager":"captainhook"}'
git_init "$HM_CAPTAIN"
echo "x" > "$HM_CAPTAIN/x.txt"
git -C "$HM_CAPTAIN" add -A
assert_eq "a declared captainhook becomes HOOK_MANAGER" "captainhook" "$(stack_key "$HM_CAPTAIN" HOOK_MANAGER)"
assert_eq "and the gate delegates: a red declared lint does not refuse the commit" \
  "none" "$(decision_of "$(gate "$HM_CAPTAIN" 'git commit -m "feat: x"')")"

# The control: the same red lint, no hook manager declared — the gate runs it.
HM_NONE="$WORK_DIR/hm-none"
declare_in "$HM_NONE" '{"lint":"false","typecheck":null,"absent":{"typecheck":"none"},"test":"true"}'
git_init "$HM_NONE"
echo "x" > "$HM_NONE/x.txt"
git -C "$HM_NONE" add -A
assert_eq "without a declared hook manager the red declared lint refuses the commit" \
  "deny" "$(decision_of "$(gate "$HM_NONE" 'git commit -m "feat: x"')")"

echo ""
echo "── quality-candidates.sh (what the setup proposes) ──"

# The candidates come from where a project already declares its gates — CI,
# task runners, package scripts, docs — and only last from the per-language
# heuristics. Nothing here knows a language: that is the point (DE-17472).
candidates() { (cd "$1" && shift && bash "$PLUGIN_SCRIPTS/quality-candidates.sh" --json "$@" 2>/dev/null); }
cand_key() { local dir="$1" key="$2"; shift 2; candidates "$dir" "$@" | jq -r --arg k "$key" '.[$k]'; }
TAB=$'\t'

# Asserts a candidate list holds the exact `<command>\t<source>` line.
assert_line() {
  local label="$1" haystack="$2" line="$3"
  if printf '%s\n' "$haystack" | grep -Fxq -- "$line"; then
    pass "$label"
  else
    fail "$label" "expected the line: $line
  got: $haystack"
  fi
}

# One ad-hoc directory per reader, each yielding a command no other reader
# yields, so a reader that silently stopped working shows up by name.
CAND="$WORK_DIR/candidates"

mkdir -p "$CAND/run-block/.github/workflows"
cat > "$CAND/run-block/.github/workflows/ci.yml" <<'EOF'
jobs:
  types:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Types
        run: |
          npm ci
          npm run check:types
EOF
assert_line "a run: | block is read line by line" \
  "$(cand_key "$CAND/run-block" TYPECHECK_CANDIDATES)" "npm run check:types${TAB}ci:.github/workflows/ci.yml"
assert_eq "and the install line in it is no gate" "" \
  "$(candidates "$CAND/run-block" | jq -r '[.LINT_CANDIDATES, .TYPECHECK_CANDIDATES, .TEST_CANDIDATES] | join("\n")' | grep -F 'npm ci' || true)"

mkdir -p "$CAND/step-wd/.github/workflows"
cat > "$CAND/step-wd/.github/workflows/ci.yml" <<'EOF'
jobs:
  web:
    runs-on: ubuntu-latest
    steps:
      - name: Test
        working-directory: web
        run: npm test
EOF
assert_line "a step's working-directory is folded into the command" \
  "$(cand_key "$CAND/step-wd" TEST_CANDIDATES)" "cd web && npm test${TAB}ci:.github/workflows/ci.yml"

mkdir -p "$CAND/job-wd/.github/workflows"
cat > "$CAND/job-wd/.github/workflows/ci.yml" <<'EOF'
jobs:
  svc:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: svc
    steps:
      - run: make lint
EOF
assert_line "a job's defaults.run.working-directory is folded in too" \
  "$(cand_key "$CAND/job-wd" LINT_CANDIDATES)" "cd svc && make lint${TAB}ci:.github/workflows/ci.yml"

mkdir -p "$CAND/gitlab"
cat > "$CAND/gitlab/.gitlab-ci.yml" <<'EOF'
test:
  stage: test
  before_script:
    - ./gradlew --version
  script:
    - ./gradlew test
EOF
assert_line "a GitLab script: item" \
  "$(cand_key "$CAND/gitlab" TEST_CANDIDATES)" "./gradlew test${TAB}ci:.gitlab-ci.yml"

mkdir -p "$CAND/just"
printf 'set shell := ["bash", "-c"]\n\nlint:\n    cargo clippy\n' > "$CAND/just/justfile"
assert_line "a justfile recipe" \
  "$(cand_key "$CAND/just" LINT_CANDIDATES)" "just lint${TAB}runner:justfile"

mkdir -p "$CAND/taskfile"
printf "version: '3'\n\ntasks:\n  test:\n    cmds:\n      - go test ./...\n" > "$CAND/taskfile/Taskfile.yml"
assert_line "a Taskfile task" \
  "$(cand_key "$CAND/taskfile" TEST_CANDIDATES)" "task test${TAB}runner:Taskfile.yml"

mkdir -p "$CAND/composer"
echo '{"scripts":{"post-install-cmd":"@php artisan key:generate","analyse":"phpstan analyse"}}' > "$CAND/composer/composer.json"
assert_line "a composer script" \
  "$(cand_key "$CAND/composer" TYPECHECK_CANDIDATES)" "composer analyse${TAB}scripts:composer.json"

mkdir -p "$CAND/pyproject"
printf '[project]\nname = "x"\n\n[tool.poe.tasks]\nlint = "ruff check ."\n\n[tool.pdm.scripts]\ntest = "pytest"\n' > "$CAND/pyproject/pyproject.toml"
assert_line "a poe task" \
  "$(cand_key "$CAND/pyproject" LINT_CANDIDATES)" "poe lint${TAB}scripts:pyproject.toml"
assert_line "a pdm script" \
  "$(cand_key "$CAND/pyproject" TEST_CANDIDATES)" "pdm run test${TAB}scripts:pyproject.toml"

mkdir -p "$CAND/docs"
printf '# x\n\n```bash\nmake test\n```\n\n```json\n{ "lint": "not a command" }\n```\n' > "$CAND/docs/README.md"
printf '# Agents\n\n```sh\n$ make lint\n```\n' > "$CAND/docs/AGENTS.md"
assert_line "a fenced command in README.md" \
  "$(cand_key "$CAND/docs" TEST_CANDIDATES)" "make test${TAB}docs:README.md"
assert_line "a fenced command in AGENTS.md" \
  "$(cand_key "$CAND/docs" LINT_CANDIDATES)" "make lint${TAB}docs:AGENTS.md"
assert_eq "a JSON block is not read as a command" "" \
  "$(cand_key "$CAND/docs" LINT_CANDIDATES | grep -F 'not a command' || true)"

mkdir -p "$CAND/go"
printf 'module example.com/x\n\ngo 1.23\n' > "$CAND/go/go.mod"
assert_line "the detect-stack heuristics come last" \
  "$(cand_key "$CAND/go" TEST_CANDIDATES)" "go test ./...${TAB}heuristic:detect-stack.sh"

UM_LINT=$(cand_key "$WORK_DIR/unknown-make" LINT_CANDIDATES)
assert_line "a stack nobody wrote a rule for still gets its make lint" \
  "$UM_LINT" "make lint${TAB}ci:.github/workflows/ci.yml"
assert_eq "once, with the CI source, although the Makefile and the README yield it too" "1" \
  "$(printf '%s\n' "$UM_LINT" | grep -c '^make lint	')"
assert_line "and its make test" \
  "$(cand_key "$WORK_DIR/unknown-make" TEST_CANDIDATES)" "make test${TAB}ci:.github/workflows/ci.yml"

assert_line "package.json scripts, with the package manager's runner" \
  "$(cand_key "$WORK_DIR/nestjs" LINT_CANDIDATES)" "npm run lint${TAB}scripts:package.json"

LA_DIR_ALL=$(candidates "$WORK_DIR/laravel-api" --dir api \
  | jq -r '[.LINT_CANDIDATES, .TYPECHECK_CANDIDATES, .TEST_CANDIDATES] | join("\n")')
assert_line "--dir points the scan at a sub-project and folds it into the command" \
  "$LA_DIR_ALL" "cd api && composer lint${TAB}scripts:api/composer.json"
assert_line "every script of it" \
  "$LA_DIR_ALL" "cd api && composer test${TAB}scripts:api/composer.json"

EMPTY_CAND="$CAND/empty"
mkdir -p "$EMPTY_CAND"
assert_eq "an empty directory has no candidate" "0" "$(cand_key "$EMPTY_CAND" CANDIDATE_COUNT)"
(cd "$EMPTY_CAND" && bash "$PLUGIN_SCRIPTS/quality-candidates.sh" --json) >/dev/null 2>&1
assert_eq "and that is not an error" "0" "$?"

# REQ-7, the DE-17472 regression: the gates are in a root Makefile and in the CI
# job `api`. They come out as root commands — no `cd api`, which would run the
# root Makefile's targets in the wrong directory — and no PHP rule found them.
LA_LINT=$(cand_key "$WORK_DIR/laravel-api" LINT_CANDIDATES)
LA_TEST=$(cand_key "$WORK_DIR/laravel-api" TEST_CANDIDATES)
assert_line "laravel-api: make lint from the CI, at the root" "$LA_LINT" "make lint${TAB}ci:.github/workflows/ci.yml"
assert_line "laravel-api: make test from the CI, at the root" "$LA_TEST" "make test${TAB}ci:.github/workflows/ci.yml"
assert_eq "laravel-api: detect-stack still knows no language there" \
  "unknown" "$(stack_key "$WORK_DIR/laravel-api" LANG)"
assert_eq "no rule for PHP was added to detect-stack.sh" "" \
  "$(grep -n -E 'composer\.json|artisan|\.php\b|phpunit|laravel' "$PLUGIN_SCRIPTS/detect-stack.sh" || true)"

assert_eq "the candidates script ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/quality-candidates.sh" ] && echo true || echo false)"

echo ""
echo "── quality-preflight.sh (no autonomous run starts without its commands) ──"

# The launchers ask this before the board, the fork point and the workflow. A
# refusal is exit 3 with the reason, and it costs seconds: nothing but the
# declared preflight runs unless --run asks for the commands themselves.
qp() { (cd "$1" && shift && bash "$PLUGIN_SCRIPTS/quality-preflight.sh" --json "$@" 2>/dev/null); }
qp_key() { local dir="$1" key="$2"; shift 2; qp "$dir" "$@" | jq -r --arg k "$key" '.[$k]'; }
qp_exit() {
  (cd "$1" && shift && bash "$PLUGIN_SCRIPTS/quality-preflight.sh" --json "$@" >/dev/null 2>&1)
  printf '%s' "$?"
}
QP="$WORK_DIR/preflight"

mkdir -p "$QP/undeclared"
assert_eq "no declaration with --require-declared is refused" "3" \
  "$(qp_exit "$QP/undeclared" --require-declared)"
assert_contains "and the reason points at the setup" \
  "$(qp_key "$QP/undeclared" REASON --require-declared)" "/dev-setup:setup"
assert_eq "and says the run is not ready" "false" "$(qp_key "$QP/undeclared" READY --require-declared)"
assert_eq "no declaration and nothing detected is refused even without the flag" "3" \
  "$(qp_exit "$QP/undeclared")"

declare_in "$QP/empty-lint" '{"lint":"","typecheck":null,"absent":{"typecheck":"none"},"test":"true"}'
assert_eq "a rejected declaration is a refusal, not a crash" "3" "$(qp_exit "$QP/empty-lint")"
assert_eq "with a JSON object on stdout" "object" "$(qp "$QP/empty-lint" | jq -r 'type')"
assert_contains "whose reason carries detect-stack's cause" \
  "$(qp_key "$QP/empty-lint" REASON)" "lint"

declare_in "$QP/all-null" '{"lint":null,"typecheck":null,"test":null,"absent":{"lint":"x","typecheck":"x","test":"x"}}'
assert_eq "every command declared absent leaves nothing to check with" "3" "$(qp_exit "$QP/all-null")"

declare_in "$QP/missing" '{"lint":"definitely-not-installed-qp lint","typecheck":null,"absent":{"typecheck":"x"},"test":"touch ran"}'
assert_eq "a command whose program is not installed is refused" "3" "$(qp_exit "$QP/missing")"
assert_contains "and MISSING names it" \
  "$(qp_key "$QP/missing" MISSING)" "definitely-not-installed-qp"
assert_eq "and nothing ran" "false" "$([ -e "$QP/missing/ran" ] && echo true || echo false)"

declare_in "$QP/cd-sub" '{"lint":"CI=1 true","typecheck":null,"absent":{"typecheck":"x"},"test":"cd sub && ./run-tests"}'
assert_eq "a relative program is looked for in the directory the command enters" "3" \
  "$(qp_exit "$QP/cd-sub")"
mkdir -p "$QP/cd-sub/sub"
printf '#!/bin/sh\nexit 0\n' > "$QP/cd-sub/sub/run-tests"
chmod +x "$QP/cd-sub/sub/run-tests"
assert_eq "and found there once it exists (a leading VAR=value is skipped too)" "0" \
  "$(qp_exit "$QP/cd-sub")"

declare_in "$QP/preflight-red" '{"lint":"true","typecheck":null,"absent":{"typecheck":"x"},"test":"true","preflight":"echo boom; exit 7"}'
assert_eq "a red declared preflight is refused" "3" "$(qp_exit "$QP/preflight-red")"
assert_contains "with its output" "$(qp_key "$QP/preflight-red" OUTPUT)" "boom"
assert_eq "and PREFLIGHT says it failed" "failed" "$(qp_key "$QP/preflight-red" PREFLIGHT)"

# REQ-17: what the environment lacks is not what the project lacks. With
# --allow-unavailable the launchers get a ready answer that names the commands
# this machine cannot run, and the run goes on to a merge request that says so.
QP_ALLOW=$(qp "$QP/missing" --require-declared --allow-unavailable)
assert_eq "--allow-unavailable: a missing program does not refuse" "0" \
  "$(qp_exit "$QP/missing" --require-declared --allow-unavailable)"
assert_eq "its kind comes back unavailable, the others untouched" "lint|unavailable|absent" \
  "$(printf '%s' "$QP_ALLOW" | jq -r '[.UNAVAILABLE, .LINT_STATUS, .TYPECHECK_STATUS] | join("|")')"
assert_contains "with the reason the merge request will carry" \
  "$(printf '%s' "$QP_ALLOW" | jq -r '.UNAVAILABLE_REASON')" "definitely-not-installed-qp"
assert_eq "and still nothing ran" "false" "$([ -e "$QP/missing/ran" ] && echo true || echo false)"
QP_ALLOW=$(qp "$QP/preflight-red" --allow-unavailable)
assert_eq "--allow-unavailable: a red preflight makes every declared command unavailable" \
  "true|lint test|failed" \
  "$(printf '%s' "$QP_ALLOW" | jq -r '[.READY, .UNAVAILABLE, .PREFLIGHT] | join("|")')"
assert_contains "and keeps the preflight's output" "$(printf '%s' "$QP_ALLOW" | jq -r '.OUTPUT')" "boom"
assert_eq "--run does not run an unavailable command" "unavailable 0" \
  "$(qp_key "$QP/preflight-red" TEST_STATUS --run --allow-unavailable) $(qp_exit "$QP/preflight-red" --run --allow-unavailable)"
assert_eq "--allow-unavailable never excuses a missing declaration" "3" \
  "$(qp_exit "$QP/undeclared" --require-declared --allow-unavailable)"
assert_eq "nor every command declared absent" "3" "$(qp_exit "$QP/all-null" --allow-unavailable)"

QP_READY="$QP/ready"
declare_in "$QP_READY" '{"lint":"true","typecheck":null,"absent":{"typecheck":"none"},"test":"touch ran"}'
assert_eq "a declaration with lint and test and no typecheck is ready" "0" \
  "$(qp_exit "$QP_READY" --require-declared)"
assert_eq "READY says so" "true" "$(qp_key "$QP_READY" READY)"
assert_eq "nothing is missing" "" "$(qp_key "$QP_READY" MISSING)"
assert_eq "and without --run no command was executed" "false" \
  "$([ -e "$QP_READY/ran" ] && echo true || echo false)"
QP_RUN=$(qp "$QP_READY" --run)
assert_eq "--run runs each command once and reports it" "passed absent passed" \
  "$(printf '%s' "$QP_RUN" | jq -r '[.LINT_STATUS, .TYPECHECK_STATUS, .TEST_STATUS] | join(" ")')"
assert_eq "from the repository root" "true" "$([ -e "$QP_READY/ran" ] && echo true || echo false)"

declare_in "$QP/red-test" '{"lint":"true","typecheck":null,"absent":{"typecheck":"x"},"test":"false"}'
assert_eq "a red test is reported, not refused" "failed 0" \
  "$(qp_key "$QP/red-test" TEST_STATUS --run) $(qp_exit "$QP/red-test" --run)"

declare_in "$QP/not-started" '{"lint":"true","typecheck":null,"absent":{"typecheck":"x"},"test":"exit 127"}'
assert_eq "a command that did not start (127) is not-found, and refused" "not-found 3" \
  "$(qp_key "$QP/not-started" TEST_STATUS --run) $(qp_exit "$QP/not-started" --run)"

assert_eq "an unknown flag is a usage error" "1" "$(qp_exit "$QP_READY" --frobnicate)"

# REQ-7, end to end: the DE-17472 project with its root commands declared
# passes the setup's verification — no PHP rule, no `cd api`.
if command -v make >/dev/null 2>&1; then
  cp -R "$WORK_DIR/laravel-api" "$QP/laravel-api"
  declare_in "$QP/laravel-api" '{"lint":"make lint","typecheck":null,"absent":{"typecheck":"none"},"test":"make test"}'
  assert_eq "laravel-api: the declared make lint and make test pass the verification" "passed passed 0" \
    "$(qp_key "$QP/laravel-api" LINT_STATUS --run) $(qp_key "$QP/laravel-api" TEST_STATUS --run) $(qp_exit "$QP/laravel-api" --run --require-declared)"
else
  printf '%s  skip%s  make not found: the laravel-api verification needs it\n' "$DIM" "$NC"
fi

assert_eq "the preflight script ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/quality-preflight.sh" ] && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# 7. rules/ — the path-scoped rule templates (DE-16477)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── rules/ ──"

RULES_SRC="$REPO_ROOT/templates/dev-setup/rules"
RULES_OUT="$WORK_DIR/rules-out"
mkdir -p "$RULES_OUT"

# Every declared rule renders against a real project's detect-stack output, with
# no unresolved placeholder left. This is the check that would catch a template
# growing a `{{VAR}}` detect-stack does not emit.
RULES_STACK="$WORK_DIR/rules-stack.json"
(cd "$WORK_DIR/nestjs" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json) > "$RULES_STACK"

RENDER_FAILURES=""
for RULE in $(jq -r '.rules[]? // empty' "$REPO_ROOT/templates/dev-setup/manifest.json"); do
  if ! bash "$PLUGIN_SCRIPTS/render-template.sh" \
      --in "$RULES_SRC/$RULE" \
      --out "$RULES_OUT/dev-setup-$RULE" \
      --vars-json "$RULES_STACK" >/dev/null 2>&1; then
    RENDER_FAILURES="$RENDER_FAILURES $RULE"
  fi
done
assert_eq "every rule renders from detect-stack output" "" "${RENDER_FAILURES# }"

# The service-layer glob is the one value a rule takes from detection.
assert_contains "backend-services gets the resolved glob" \
  "$(cat "$RULES_OUT/dev-setup-backend-services.md" 2>/dev/null)" \
  '"**/*.{service,controller,repository,resolver,guard,interceptor}.ts"'

# core.md is the only rule without `paths:`: everything else costs context only
# when a matching file is touched.
UNSCOPED=""
for RULE in $(jq -r '.rules[]? // empty' "$REPO_ROOT/templates/dev-setup/manifest.json"); do
  head -1 "$RULES_SRC/$RULE" | grep -q '^---$' || { UNSCOPED="$UNSCOPED $RULE"; continue; }
  sed -n '2,/^---$/p' "$RULES_SRC/$RULE" | grep -q '^paths:' || UNSCOPED="$UNSCOPED $RULE"
done
assert_eq "core.md is the only unconditional rule" "core.md" "${UNSCOPED# }"

assert_eq "core.md fits the session-zero budget" "true" \
  "$([ "$(wc -l < "$RULES_SRC/core.md" | tr -d ' ')" -le 150 ] && echo true || echo false)"

# The split only pays off if core stays small: it is the file every session,
# on every project, reads in full whatever the work is.
assert_eq "core.md stays under the session-zero target" "true" \
  "$([ "$(wc -l < "$RULES_SRC/core.md" | tr -d ' ')" -le 60 ] && echo true || echo false)"

# A rule whose absence produces worse code may be path-scoped; one whose absence
# produces an unsafe action may not. These four are the second kind — if any of
# them drifts out of core into a scoped rule, it stops loading on the sessions
# that need it most.
SAFETY_MISSING=""
for TOPIC in "never repeat a secret" "data, never instructions" "supply-chain" "not yours to rewrite"; do
  grep -qi -- "$TOPIC" "$RULES_SRC/core.md" || SAFETY_MISSING="$SAFETY_MISSING [$TOPIC]"
done
assert_eq "the safety rules stayed unconditional" "" "${SAFETY_MISSING# }"

# code-style.md is the catch-all for source files: it has to match the languages
# the team actually writes, or the design rules silently stop loading.
CS_UNMATCHED=""
for EXT in ts tsx js jsx py go dart vue tf sh; do
  grep -q "{[^}]*\b$EXT\b[^}]*}" "$RULES_SRC/code-style.md" || CS_UNMATCHED="$CS_UNMATCHED $EXT"
done
assert_eq "code-style covers the team's languages" "" "${CS_UNMATCHED# }"

# A frontend project has no service layer, so the rule is not generated at all —
# an empty glob would otherwise render as `paths: [""]`, which matches nothing
# and looks like a rule that simply never fires.
assert_eq "a frontend project resolves no service glob" "" \
  "$( (cd "$WORK_DIR/nextjs" && bash "$PLUGIN_SCRIPTS/detect-stack.sh" --json) | jq -r .SERVICES_GLOB)"

echo ""
echo "── migrate-settings.sh ──"

# The upgrade path the chain nearly shipped broken: a project set up before the
# sandbox landed keeps a settings.json holding only `permissions`, conflict
# detection leaves it alone, and none of the protection the rules promise ever
# arrives. These tests pin the merge.

MIG_DIR="$WORK_DIR/migrate-settings"
mkdir -p "$MIG_DIR"
SETTINGS_TEMPLATE="$REPO_ROOT/templates/dev-setup/.claude/settings.json"

# The pre-sandbox shape: permissions only, wide allowlist, no ask, no sandbox.
cat > "$MIG_DIR/old.json" <<'OLDJSON'
{
  "permissions": {
    "allow": ["Bash(git *)", "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
              "Bash(claude *)", "mcp__context7__*", "Bash(terraform *)"],
    "deny": ["Bash(git push --force*)", "Bash(kubectl delete*)"]
  }
}
OLDJSON

MIG_REPORT=$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" \
  --in "$MIG_DIR/old.json" --template "$SETTINGS_TEMPLATE" \
  --out "$MIG_DIR/merged.json" --json 2>/dev/null)

assert_eq "a pre-sandbox settings is migrated" "true" \
  "$(printf '%s' "$MIG_REPORT" | jq -r .MIGRATED)"

# The whole point: after the merge the project actually has the sandbox the
# unconditional rule claims it has.
assert_eq "the merged settings carries the sandbox" "true" \
  "$(jq -r '.sandbox.enabled' "$MIG_DIR/merged.json")"

# Reads of .env are open again (a task that makes a real call needs the
# values); writes stay denied at both levels.
assert_eq "the merged settings does not deny reading .env" "0" \
  "$(jq -r '[(.sandbox.filesystem.denyRead // [])[],
             (.permissions.deny[] | select(startswith("Read(")))]
            | map(select(test("\\.env"))) | length' "$MIG_DIR/merged.json")"

assert_eq "the merged settings still denies writing .env" "true" \
  "$(jq -r '[.sandbox.filesystem.denyWrite[],
             (.permissions.deny[] | select(startswith("Edit(")))]
            | map(select(test("\\.env"))) | length > 0' "$MIG_DIR/merged.json")"

assert_eq "the ask checkpoints arrive" "true" \
  "$(jq -r '.permissions.ask | any(startswith("Bash(gh pr create"))' "$MIG_DIR/merged.json")"

# Arbitrary-execution entries go: allowing them allows everything, including the
# `claude --dangerously-skip-permissions` the deny list forbids by name.
assert_eq "the retired allow entries are dropped" "0" \
  "$(jq -r '.permissions.allow
            | map(select(. == "Bash(npx *)" or . == "Bash(node *)"
                         or . == "Bash(claude *)" or . == "mcp__context7__*"))
            | length' "$MIG_DIR/merged.json")"

# And the reason this is a script and not three jq snippets in prose: whatever
# the team added has to survive, in both lists.
assert_eq "the team's own allow entry survives" "true" \
  "$(jq -r '.permissions.allow | index("Bash(terraform *)") != null' "$MIG_DIR/merged.json")"

assert_eq "the team's own deny entry survives" "true" \
  "$(jq -r '.permissions.deny | index("Bash(kubectl delete*)") != null' "$MIG_DIR/merged.json")"

assert_contains "the report names what it dropped" "$MIG_REPORT" "Bash(npx *)"
assert_contains "the report names what it kept" "$MIG_REPORT" "Bash(terraform *)"

# Idempotent: a settings that already has a sandbox is the team's file, and the
# script refuses to touch it (exit 3, so the caller can tell the two apart).
bash "$PLUGIN_SCRIPTS/migrate-settings.sh" --in "$MIG_DIR/merged.json" \
  --template "$SETTINGS_TEMPLATE" --json >"$MIG_DIR/again.json" 2>/dev/null
assert_eq "a current settings is left alone" "3" "$?"
assert_eq "and reports why" "already-sandboxed" "$(jq -r .REASON "$MIG_DIR/again.json")"

# It never writes in place: the caller shows the diff and asks first.
assert_eq "the input file is never modified" "true" \
  "$(jq -r 'has("sandbox") | not' "$MIG_DIR/old.json")"

# A settings written by an earlier sandbox-era template still carries the .env
# read denies the template later retired. UPDATE removes exactly those entries
# and nothing else: write denies and the team's own additions stay.
jq '.permissions.deny += ["Read(**/.env)", "Read(**/.env.local)"]
    | .sandbox.filesystem.denyRead = [".env", "**/.env", "secrets/"]' \
  "$MIG_DIR/merged.json" > "$MIG_DIR/read-blocked.json"

LIGHT_REPORT=$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" \
  --in "$MIG_DIR/read-blocked.json" --template "$SETTINGS_TEMPLATE" \
  --out "$MIG_DIR/unblocked.json" --json 2>/dev/null)

assert_eq "a sandboxed settings with the read block is migrated" "env-read-unblocked" \
  "$(printf '%s' "$LIGHT_REPORT" | jq -r .REASON)"

assert_eq "the retired read denies are removed" "0" \
  "$(jq -r '[.permissions.deny[] | select(startswith("Read("))] | length' \
     "$MIG_DIR/unblocked.json")"

assert_eq "a denyRead the team added survives" '["secrets/"]' \
  "$(jq -c '.sandbox.filesystem.denyRead' "$MIG_DIR/unblocked.json")"

assert_eq "the write denies stay after the retire pass" "true" \
  "$(jq -r '.sandbox.filesystem.denyWrite
            | map(select(test("\\.env"))) | length > 0' "$MIG_DIR/unblocked.json")"

assert_contains "the report names the retired denies" "$LIGHT_REPORT" "Read(**/.env)"

# And once unblocked the file is current: the next run refuses to touch it.
bash "$PLUGIN_SCRIPTS/migrate-settings.sh" --in "$MIG_DIR/unblocked.json" \
  --template "$SETTINGS_TEMPLATE" --json >/dev/null 2>&1
assert_eq "an unblocked settings is then left alone" "3" "$?"

# `gh` and `glab` run outside the sandbox: inside it, on macOS, they cannot
# verify a TLS certificate and every call fails. A project sandboxed before the entry existed
# gets it on UPDATE — added next to the team's own entries, nothing else touched.
assert_eq "the merged settings excludes gh, glab and the push to origin from the sandbox" \
  '["gh *","glab *","git push origin *","git push -u origin *"]' \
  "$(jq -c '.sandbox.excludedCommands' "$MIG_DIR/merged.json")"

jq '.sandbox.excludedCommands = ["docker"]' "$MIG_DIR/merged.json" > "$MIG_DIR/no-gh.json"

EXCL_REPORT=$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" \
  --in "$MIG_DIR/no-gh.json" --template "$SETTINGS_TEMPLATE" \
  --out "$MIG_DIR/with-gh.json" --json 2>/dev/null)

assert_eq "a sandboxed settings without gh is migrated" "excluded-commands-added" \
  "$(printf '%s' "$EXCL_REPORT" | jq -r .REASON)"
assert_eq "the report names the added entries" "gh *,glab *,git push origin *,git push -u origin *" \
  "$(printf '%s' "$EXCL_REPORT" | jq -r .ADDED_EXCLUDED)"
assert_eq "they are added after the team's own entries" \
  '["docker","gh *","glab *","git push origin *","git push -u origin *"]' \
  "$(jq -c '.sandbox.excludedCommands' "$MIG_DIR/with-gh.json")"
assert_eq "nothing else changes on the excluded-commands pass" "true" \
  "$(jq -n --slurpfile a "$MIG_DIR/no-gh.json" --slurpfile b "$MIG_DIR/with-gh.json" '
     ($a[0] | del(.sandbox.excludedCommands)) == ($b[0] | del(.sandbox.excludedCommands))')"

bash "$PLUGIN_SCRIPTS/migrate-settings.sh" --in "$MIG_DIR/with-gh.json" \
  --template "$SETTINGS_TEMPLATE" --json >/dev/null 2>&1
assert_eq "a settings with gh excluded is then left alone" "3" "$?"

# 3.3.0 shipped bare "gh" and "glab". Entries match like Bash(...) rules, so a
# pattern with no wildcard matches the command with no arguments only, and
# `gh pr view 12` stayed sandboxed (invictus-monorepo). The bare entry is
# replaced by its ` *` form, the team's other entries kept.
jq '.sandbox.excludedCommands = ["docker", "gh", "glab"]' "$MIG_DIR/merged.json" > "$MIG_DIR/bare-gh.json"
BARE_REPORT=$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" \
  --in "$MIG_DIR/bare-gh.json" --template "$SETTINGS_TEMPLATE" \
  --out "$MIG_DIR/fixed-gh.json" --json 2>/dev/null)
assert_eq "a bare gh entry is replaced by gh *" \
  '["docker","gh *","glab *","git push origin *","git push -u origin *"]' \
  "$(jq -c '.sandbox.excludedCommands' "$MIG_DIR/fixed-gh.json")"
assert_eq "and the report names what it replaced" "gh,glab" \
  "$(printf '%s' "$BARE_REPORT" | jq -r .RETIRED_EXCLUDED)"

# Pushing leaves the sandbox — an SSH origin cannot be reached from inside it —
# but only towards origin. `allow` carries `Bash(git *)` and there is no `ask`
# on a push, so a bare `git push *` would send an unsandboxed push to any URL
# with no allowlist and no prompt. origin itself lives in .git/config, which
# the sandbox protects.
assert_eq "no exclusion lets a push leave the sandbox towards an arbitrary URL" "" \
  "$(jq -r '.sandbox.excludedCommands[] | select(startswith("git push") and (contains(" origin ") | not))' "$SETTINGS_TEMPLATE")"
assert_contains "the template denies a push to a protected branch with -u" \
  "$(jq -r '.permissions.deny[]' "$SETTINGS_TEMPLATE")" "Bash(git push * origin next*)"

# Outside the sandbox the deny rules are the only boundary, so on UPDATE an
# exclusion never arrives without the template's denies that guard it — and a
# project that already has the exclusion gets the guards it lacks.
jq '.sandbox.excludedCommands = ["gh *", "glab *"]
    | .permissions.deny |= map(select(startswith("Bash(git push * origin ") | not))' \
  "$MIG_DIR/merged.json" > "$MIG_DIR/no-push.json"
GUARD_REPORT=$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" \
  --in "$MIG_DIR/no-push.json" --template "$SETTINGS_TEMPLATE" \
  --out "$MIG_DIR/with-push.json" --json 2>/dev/null)
assert_eq "the push exclusion is added" "git push origin *,git push -u origin *" \
  "$(printf '%s' "$GUARD_REPORT" | jq -r .ADDED_EXCLUDED)"
assert_eq "with the push denies that guard it" "4" \
  "$(printf '%s' "$GUARD_REPORT" | jq -r .ADDED_DENY)"
assert_contains "the -u push to next is denied after UPDATE" \
  "$(jq -r '.permissions.deny[]' "$MIG_DIR/with-push.json")" "Bash(git push * origin next*)"
assert_eq "no deny unrelated to an excluded command is added" "" \
  "$(jq -n --slurpfile a "$MIG_DIR/no-push.json" --slurpfile b "$MIG_DIR/with-push.json" -r '
     ($b[0].permissions.deny - $a[0].permissions.deny)[] | select(startswith("Bash(git push") | not)')"

jq '.permissions.deny |= map(select(startswith("Bash(git push * origin ") | not))' \
  "$MIG_DIR/with-push.json" > "$MIG_DIR/unguarded.json"
assert_eq "an exclusion already there still gets its guards" "excluded-commands-guarded" \
  "$(bash "$PLUGIN_SCRIPTS/migrate-settings.sh" --in "$MIG_DIR/unguarded.json" \
       --template "$SETTINGS_TEMPLATE" --json 2>/dev/null | jq -r .REASON)"

# ═══════════════════════════════════════════════════════════════════════════════
# 8. auto-sdd-run.js: the workflow script (DE-16479)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The autonomous orchestration is code now, so it is tested like code. What the
# static check cannot see is whether the file compiles: the harness parses the
# `export const meta` literal and then compiles the rest as the body of an async
# function, which is neither valid CommonJS nor a valid ES module on its own —
# `node --check` answers the wrong question. This reproduces both halves.

echo ""
echo "── auto-sdd-run.js (workflow script) ──"

AUTO_SDD="$REPO_ROOT/templates/dev-setup/.claude/workflows/auto-sdd-run.js"

if [ ! -f "$AUTO_SDD" ]; then
  fail "the auto-sdd workflow script exists" "$AUTO_SDD not found"
elif command -v node >/dev/null 2>&1; then
  cat > "$WORK_DIR/workflow-parse.cjs" <<'NODEJS'
// Reproduces how the harness loads a workflow: the meta literal is evaluated,
// the body is compiled as the body of an async function (that is why a
// top-level `return` is legal in one and a syntax error in the other).
const fs = require('fs');
const vm = require('vm');

const file = process.argv[2];
const src = fs.readFileSync(file, 'utf8');
const match = src.match(/^export const meta = \{[\s\S]*?\n\}\n/);
if (!match) {
  console.error('no `export const meta = {...}` literal at the top of the file');
  process.exit(1);
}
const meta = vm.runInNewContext(match[0].replace(/^export /, '') + '\n;meta');
new vm.Script('(async () => {' + src.slice(match[0].length) + '})()', { filename: file });
console.log(JSON.stringify({
  name: meta.name,
  description: meta.description || '',
  phases: (meta.phases || []).map((p) => p.title),
}));
NODEJS

  if WF_META="$(node "$WORK_DIR/workflow-parse.cjs" "$AUTO_SDD" 2>&1)"; then
    pass "the script compiles the way the harness compiles it"

    assert_eq "meta.name is the name the launcher calls" \
      "auto-sdd-run" "$(printf '%s' "$WF_META" | jq -r '.name')"

    assert_eq "the four phases are declared in order" \
      "Spec Challenge Dev Verify" \
      "$(printf '%s' "$WF_META" | jq -r '.phases | join(" ")')"

    assert_eq "meta carries a description" "false" \
      "$(printf '%s' "$WF_META" | jq -r '.description == ""')"

    for LAUNCHER_DOC in skills/auto-sdd/SKILL.md skills/multi-sdd/reference/fan-out.md; do
      assert_contains "$LAUNCHER_DOC launches the workflow by its name" \
        "$(cat "$REPO_ROOT/templates/dev-setup/.claude/$LAUNCHER_DOC")" '"name": "dev-setup:auto-sdd-run"'
    done
  else
    fail "the script compiles the way the harness compiles it" "$WF_META"
  fi

  # The harness registers every workflow as the slash command
  # /<plugin>:<meta.name> too, and one named like a skill shadows it: in
  # `claude -p`, `/dev-setup:auto-sdd DE-1` reached the workflow with "DE-1" as
  # its arguments, past the launcher (2026-10-28), and `/dev-setup:auto-dev`
  # did the same on its first live run. No workflow is named like a skill.
  SKILL_NAMES="$(find "$REPO_ROOT/templates" "$REPO_ROOT/shared" -name SKILL.md \
    -exec awk '/^name:/ { sub(/^name:[ \t]*/, ""); print; exit }' {} \; | LC_ALL=C sort -u)"
  SHADOWED=""
  for WF in "$REPO_ROOT"/templates/*/.claude/workflows/*.js; do
    WF_NAME="$(node "$WORK_DIR/workflow-parse.cjs" "$WF" 2>/dev/null | jq -r '.name // empty')"
    [ -n "$WF_NAME" ] || continue
    printf '%s\n' "$SKILL_NAMES" | grep -qxF "$WF_NAME" && SHADOWED="$SHADOWED $WF_NAME"
  done
  assert_eq "no workflow is named like a skill, so every command reaches its skill" "" "${SHADOWED# }"
else
  printf '%s  skip%s  node not found: the workflow compile test needs it\n' "$DIM" "$NC"
fi

if [ -f "$AUTO_SDD" ]; then
  # The decisions the audit turned into code. A number in prose was a suggestion;
  # these are the lines that make them bounds.
  assert_eq "three adversarial lenses, no more and no fewer" \
    "3" "$(grep -c "^    key: '" "$AUTO_SDD")"

  # A proposal is work, not a veto: the spec is revised on it once, and the
  # behaviour is pinned by the simulation below.
  assert_contains "a reviewer proposes on grounds, never on doubt" \
    "$(cat "$AUTO_SDD")" "A doubt you cannot ground is not a proposal"
  assert_contains "a dead verifier is asked once more" \
    "$(cat "$AUTO_SDD")" "attempt <= 2"
  assert_contains "a lens that never answered is reported, not hidden" \
    "$(cat "$AUTO_SDD")" "unchecked,"

  assert_contains "the dev stage runs in an isolated worktree" \
    "$(cat "$AUTO_SDD")" "isolation: 'worktree'"

  # Effort is differentiated per call: high on the spec, its reviewers, its
  # revision and dev, low on the stage that only runs commands.
  assert_eq "nothing in the run goes above high effort" \
    "0" "$(grep -cE "effort: '(xhigh|max)'" "$AUTO_SDD")"
  # max costs more than it returns: nothing in the plugin runs at it.
  assert_eq "no skill, agent or workflow runs at max effort" "" \
    "$(grep -rlE "effort: '?max'?" "$REPO_ROOT/templates/dev-setup" "$REPO_ROOT/shared" || true)"
  assert_eq "spec, reviewers, revision and dev run at high effort" \
    "4" "$(grep -c "effort: 'high'" "$AUTO_SDD")"
  assert_eq "the command runner stays at low effort" \
    "1" "$(grep -c "effort: 'low'" "$AUTO_SDD")"

  # The workflow reports; the launcher acts. Nothing outward-facing happens
  # inside a background run: no push, no merge request, no board write.
  assert_eq "the workflow itself pushes nothing and opens nothing" "" \
    "$(grep -n -E "git push|gh pr create|glab mr create|mcp__clickup" "$AUTO_SDD" || true)"

  # The quality commands are the project's own, never a guess.
  assert_contains "the quality commands come from detect-stack" \
    "$(cat "$AUTO_SDD")" "stack.lint"

  # The task id and the slug reach a branch name, a path and a shell command
  # inside an agent prompt, and they come from the board: they are validated
  # before they get there, not trusted.
  assert_contains "the task id is validated before it reaches a prompt" \
    "$(cat "$AUTO_SDD")" "TASK_ID_SHAPE"
  assert_contains "the slug is normalised, not trusted" \
    "$(cat "$AUTO_SDD")" "replace(/[^a-z0-9]+/g, '-')"
fi

# The surface the workflow replaced: three agents that let the model approve its
# own spec, and two standalone skills that duplicated sdd-dev. Acceptance
# criterion 5 of DE-16479, made permanent.
#
# CHANGELOG.md is excluded for the same reason `docs/migration-v2-to-v3.md` is
# excluded from checks 14-15: its subject *is* what was removed. release-please
# generates it from the commit messages, so the BREAKING CHANGE footer of
# DE-16479 — "/dev-setup:tdd and /dev-setup:bdd no longer exist" — lands there on
# the release cut and matches a grep looking for the names. A record of a removal
# is the opposite of a live reference to a retired command, and the file is
# regenerated on every release, so editing it around the check would not hold.
assert_eq "the replaced agents are gone from the distributed surface" "" \
  "$(grep -rl --exclude=CHANGELOG.md -E "sdd-approver|discovery-responder|methodology-picker" \
       "$REPO_ROOT/templates" "$REPO_ROOT/dist" 2>/dev/null || true)"

assert_eq "no command points at the retired tdd/bdd skills" "" \
  "$(grep -rl --exclude=CHANGELOG.md -E "dev-setup:(tdd|bdd)" \
       "$REPO_ROOT/templates" "$REPO_ROOT/dist" 2>/dev/null || true)"

assert_eq "the workflow ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/workflows/auto-sdd-run.js" ] && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# 9. worktree-info.sh and the slimmed interactive flow (DE-16480)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Two worktrees of the same repository, each with a spec declaring the files it
# will touch. The script has to give them different dev-server ports and name
# the one file they both declared.

echo ""
echo "── worktree-info.sh ──"

WT_MAIN="$WORK_DIR/wt-main"
WT_SIDE="$WORK_DIR/wt-side"
mkdir -p "$WT_MAIN/.specs"

cat > "$WT_MAIN/.specs/DE-1-alpha.md" <<'SPECA'
# Spec: Alpha [DE-1]
> Status: approved

## Impact
- **Files to create**: src/auth/token.service.ts
- **Files to modify**: src/app.module.ts
- **Dependencies**: zod

## Implementation plan
1. do it
SPECA

git_init "$WT_MAIN"
git -C "$WT_MAIN" config user.email "test@example.com"
git -C "$WT_MAIN" config user.name "Test"
git -C "$WT_MAIN" add -A
git -C "$WT_MAIN" commit --quiet -m "chore: base"
git -C "$WT_MAIN" checkout --quiet -b feat/DE-1-alpha
git -C "$WT_MAIN" worktree add --quiet "$WT_SIDE" -b feat/DE-2-beta >/dev/null 2>&1

mkdir -p "$WT_SIDE/.specs"
cat > "$WT_SIDE/.specs/DE-2-beta.md" <<'SPECB'
# Spec: Beta [DE-2]
> Status: approved

## Impact
- **Files to create**: src/user/user.service.ts
- **Files to modify**: src/app.module.ts
- **Dependencies**: none

## Implementation plan
1. do it
SPECB

wt_info() { (cd "$1" && bash "$PLUGIN_SCRIPTS/worktree-info.sh" --json 2>/dev/null); }

assert_eq "both worktrees are listed" "2" \
  "$(wt_info "$WT_MAIN" | jq -r '.WORKTREES | split("\n") | length')"

# The whole point of the offset: the same `dev` script in two checkouts must not
# fight over one port.
assert_eq "the main checkout gets offset 0" "0" \
  "$(wt_info "$WT_MAIN" | jq -r '.PORT_OFFSET')"
assert_eq "the second worktree gets a different offset" "1" \
  "$(wt_info "$WT_SIDE" | jq -r '.PORT_OFFSET')"

# The overlap warning: one file declared by both specs, and only that one.
assert_eq "the shared file is the only overlap" "1" \
  "$(wt_info "$WT_SIDE" | jq -r '.OVERLAP_COUNT')"
assert_contains "the overlap names the file and both branches" \
  "$(wt_info "$WT_SIDE" | jq -r '.OVERLAPS')" \
  "src/app.module.ts	feat/DE-1-alpha,feat/DE-2-beta"

# A dependency is not a file: `zod` on the Dependencies line must not become a
# phantom overlap, and a file only one worktree declares is not one either.
assert_eq "files declared by one worktree only are not overlaps" "" \
  "$(wt_info "$WT_SIDE" | jq -r '.OVERLAPS' | grep -E 'token.service|user.service|zod' || true)"

# The gate has to run in the worktree the commit is happening in: in one,
# $CLAUDE_PROJECT_DIR still points at the main checkout, so a gate reading its
# own pwd would lint and test a tree nobody is committing.
assert_contains "the commit gate reads the worktree from the hook payload" \
  "$(cat "$PLUGIN_HOOKS/gate-commit.sh")" \
  "jq -r '.cwd // empty'"

echo ""
echo "── the slimmed interactive flow ──"

SDD_DIR="$REPO_ROOT/templates/dev-setup/.claude/skills"

# One simplify invocation in the whole flow. It used to run in sdd-dev and again
# in the orchestrator's closure, so every task paid for it twice.
assert_eq "simplify is invoked in exactly one place" "1" \
  "$(grep -rl "the \`simplify\` skill" "$SDD_DIR" | wc -l | tr -d ' ')"

# The methodology question is gone: the layer decides the cycle and tests.md
# states it, so asking produced an answer the rules already held.
assert_eq "nothing asks which methodology to use" "" \
  "$(grep -rln "which development methodology\|METHODOLOGY" "$SDD_DIR" || true)"

# The spec is a requirements document: no run-state sections, and none of the
# three bookkeeping commits they fed.
assert_eq "the spec template carries no run-state sections" "" \
  "$(grep -l "^## Simplify phase\|^## Review phase" \
       "$SDD_DIR/sdd-spec/reference/spec-template.md" || true)"

assert_eq "no bookkeeping commit is mandated" "" \
  "$(grep -rn "commit it: \`docs(registry)\|add \`docs(spec): track review outcome" "$SDD_DIR" || true)"

# The deterministic steps are script calls, not prose: intake must not re-derive
# the base branch by hand.
assert_contains "intake creates the branch through sdd-start.sh" \
  "$(cat "$SDD_DIR/sdd/reference/intake.md")" "sdd-start.sh"
# The prose still names `git checkout` — to forbid it. What must be gone is the
# command itself, so the pattern is a command line and not a mention of one.
assert_eq "intake runs no git checkout of its own" "" \
  "$(grep -nE '^[[:space:]]*git (checkout|pull)' "$SDD_DIR/sdd/reference/intake.md" || true)"
assert_contains "intake reads the preconditions from the script" \
  "$(cat "$SDD_DIR/sdd/reference/intake.md")" "check-prerequisites.sh"

# The fast path exists, is a person's call, and states its own bar.
QUICK="$SDD_DIR/quick/SKILL.md"
assert_eq "the quick fast path ships" "true" \
  "$([ -f "$QUICK" ] && echo true || echo false)"
assert_contains "quick is started by a person, never inferred" \
  "$(cat "$QUICK")" "disable-model-invocation: true"
assert_contains "quick declares no spec and no discovery" \
  "$(cat "$QUICK")" "No discovery, no spec"

# Discovery asks the gaps only, in one call of up to four questions, and a
# resume reads the saved stop point instead of asking it again (DE-17076).
assert_contains "discovery offers the one-click way to the spec" \
  "$(cat "$SDD_DIR/sdd-discovery/reference/question-bank.md")" "Requirements clear: go to spec"
assert_eq "no 10–12 question cap and no one-question-at-a-time left in discovery" "" \
  "$(grep -rln "10–12\|one question at a time" "$SDD_DIR/sdd-discovery" || true)"
assert_contains "turn discipline bounds a call at four related questions" \
  "$(cat "$REPO_ROOT/templates/dev-setup/.claude/reference/turn-discipline.md")" "up to four related questions"
assert_eq "sdd no longer promises two stops" "" \
  "$(grep -ln "Two stops" "$SDD_DIR/sdd/SKILL.md" || true)"
assert_eq "a resumed run no longer asks the stop point again" "" \
  "$(grep -ln "Nothing writes it down" "$SDD_DIR/sdd/reference/stop-point.md" || true)"
assert_contains "intake saves the stop point on --create" \
  "$(cat "$SDD_DIR/sdd/reference/intake.md")" "--stop <the chosen stop point> --create"
assert_contains "the worktree path saves it too" \
  "$(cat "$REPO_ROOT/templates/dev-setup/.claude/reference/worktree.md")" "--stop <the chosen stop point>] --create"

# The routing bar is in both descriptions, so /help alone answers which to use.
for SURFACE in "$QUICK" "$SDD_DIR/sdd/SKILL.md"; do
  assert_contains "the routing bar is in $(basename "$(dirname "$SURFACE")")'s description" \
    "$(sed -n '2,/^---$/p' "$SURFACE")" "three files"
done

# A flag declared in a Usage line and never acted on is worse than no flag: the
# skill would pass `--base` while still working in the main checkout. Whichever
# surface offers `--worktree` has to say to enter one.
for SURFACE in "$QUICK" "$SDD_DIR/sdd/SKILL.md"; do
  NAME="$(basename "$(dirname "$SURFACE")")"
  grep -q -- '--worktree' "$SURFACE" || continue
  assert_eq "$NAME says to enter the worktree, not just to pass --base" "true" \
    "$(grep -rqE 'enter the worktree' "$SURFACE" "$(dirname "$SURFACE")/reference" 2>/dev/null \
       && echo true || echo false)"
done

echo ""
echo "── DE-17128 — sdd-dev aligned with the stops and the script, no history in the instructions ──"

# Prose assertions read the file with its newlines folded: a sentence markdown
# wraps still counts, and a removed phrase cannot pass because an edit wrapped it.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
frontmatter_of() { sed -n '2,/^---$/p' "$1"; }

METH="$SDD_DIR/sdd-dev/reference/methodologies.md"
INSTALL="$REPO_ROOT/templates/dev-setup/setup/reference/install.md"
TEMPLATE_ROOT="$REPO_ROOT/templates/dev-setup"

# The scenarios go into the test names, never in front of the developer: the
# flow's stops are declared in sdd/SKILL.md and the autonomous run has nobody
# to answer one more.
assert_eq "nothing under sdd-dev presents the scenarios to the developer" "" \
  "$(grep -rln 'Present the scenarios' "$SDD_DIR/sdd-dev" || true)"
assert_contains "the scenarios are written into the test names" \
  "$(flat "$METH")" "into the test names before implementing them"

# No per-stack table: detect-stack.sh is the one source of the commands, and a
# table restating it drifted the moment the script changed.
assert_eq "methodologies.md carries no per-stack command table" "" \
  "$(grep -n '^|' "$METH" || true)"
assert_eq "and names none of the commands the table held" "" \
  "$(grep -nE 'npm test|ruff check|go test|cargo test|flutter test' "$METH" || true)"
assert_contains "it points at detect-stack.sh" "$(flat "$METH")" "detect-stack.sh --json"

# One rule for an empty command, in both flows: run nothing, substitute
# nothing, report it where the step reports.
assert_eq "nothing under sdd-dev asks which commands to use" "" \
  "$(grep -rn 'ask the developer which commands\|If both come back empty' "$SDD_DIR/sdd-dev" || true)"
assert_contains "an empty command is never substituted" \
  "$(flat "$METH")" "never substitute one of your own"
assert_contains "and is reported in notes on the autonomous run" \
  "$(flat "$METH")" '`notes`'

# The rule stays, the story goes. A sentence that narrates what the flow used
# to do is a sentence the model can re-perform.
while IFS='|' read -r HIST_FILE HIST_PHRASE; do
  [ -n "$HIST_FILE" ] || continue
  assert_eq "$(basename "$HIST_FILE") tells no history: $HIST_PHRASE" "" \
    "$(flat "$TEMPLATE_ROOT/$HIST_FILE" | grep -o "$HIST_PHRASE" || true)"
done <<'HIST_GONE'
.claude/skills/sdd-dev/SKILL.md|second approval wearing
.claude/skills/sdd-dev/SKILL.md|once cost a task four commits
.claude/skills/sdd/reference/closure.md|this flow used to mandate
.claude/skills/sdd/reference/closure.md|no longer calls it
.claude/skills/sdd-spec/reference/spec-template.md|this template used to carry
.claude/skills/review/reference/registry-updates.md|this reference used to mandate
setup/reference/mcp-env.md|used to be two bullets
HIST_GONE

while IFS='|' read -r HIST_FILE HIST_PHRASE; do
  [ -n "$HIST_FILE" ] || continue
  assert_contains "$(basename "$HIST_FILE") keeps the rule: $HIST_PHRASE" \
    "$(flat "$TEMPLATE_ROOT/$HIST_FILE")" "$HIST_PHRASE"
done <<'HIST_KEPT'
.claude/skills/sdd-dev/SKILL.md|Do not ask the developer to confirm the breakdown
.claude/skills/sdd-dev/SKILL.md|Do not commit, simplify or touch the spec's status
.claude/skills/sdd/reference/closure.md|the gates run before the commit, and there is one commit
.claude/skills/sdd/reference/closure.md|This is the only place `simplify` runs in the flow
.claude/skills/sdd-spec/reference/spec-template.md|Nothing in here records how the run went
.claude/skills/review/reference/registry-updates.md|Leave the change in the working tree — do not commit it
setup/reference/mcp-env.md|settings on the host
HIST_KEPT

# Over the prose the model reads, the three phrases survive only where they
# state a present fact (fork-point.md, rules-generation.md) or the recognition
# rule UPDATE applies to an old AGENTS.md (agents-generation.md).
assert_eq "the only history phrases left are present-tense facts and the UPDATE recognition rule" \
  "templates/dev-setup/.claude/reference/fork-point.md
templates/dev-setup/setup/reference/agents-generation.md
templates/dev-setup/setup/reference/rules-generation.md" \
  "$(cd "$REPO_ROOT" && grep -rln "used to\|no longer\|once cost" \
       templates/dev-setup/.claude/skills templates/dev-setup/.claude/reference \
       templates/dev-setup/.claude/agents templates/dev-setup/setup 2>/dev/null | LC_ALL=C sort)"

# The verbatim-write rule keeps its constraint and gains its reason; the bold
# IMPORTANT goes. Pinned on its own, so a regression names the file.
INSTALL_BLOCK="$(sed -n '/^### 3.2 /,/^### 3.2b/p' "$INSTALL" | tr '\n' ' ' | tr -s ' ')"
assert_eq "no shouted IMPORTANT in the verbatim-write rule" "" \
  "$(printf '%s' "$INSTALL_BLOCK" | grep -o '\*\*IMPORTANT\*\*' || true)"
assert_contains "the verbatim-write rule is kept" "$INSTALL_BLOCK" "exactly as received"
assert_contains "and states its reason" "$INSTALL_BLOCK" "read them back"
assert_eq "install.md carries no history phrase" "" \
  "$(grep -n 'used to\|no longer\|once cost' "$INSTALL" || true)"

assert_eq "sdd-dev/SKILL.md stays inside the 500-word budget" "true" \
  "$([ "$(wc -w < "$SDD_DIR/sdd-dev/SKILL.md" | tr -d ' ')" -le 500 ] && echo true || echo false)"

echo ""
echo "── DE-17130 — the generated AGENTS.md describes the plugin that ships it ──"

# The AGENTS.md the setup writes into a project is read in every session of
# that project, so its tables are pinned to the plugin's own surface rather
# than to a list kept here: a public command is a `user-invocable: true`
# skill, an agent is the `name:` of a file under agents/. A row for something
# that does not exist and no row for something that does are both red.
GEN_SINGLE="$TEMPLATE_ROOT/AGENTS.template.md"
GEN_WORKSPACE="$TEMPLATE_ROOT/AGENTS.workspace-template.md"
GEN_PROJECT="$TEMPLATE_ROOT/AGENTS.project-template.md"
GEN_REGISTRY="$TEMPLATE_ROOT/REGISTRY.md"
AGENTS_GEN="$TEMPLATE_ROOT/setup/reference/agents-generation.md"

# The headless commands are user-invocable because `claude -p` starts them by
# name, and they are not part of a project session's surface: a job runner
# types them, never a developer. Listing them in every generated AGENTS.md
# would make every session of every project pay to describe commands nobody
# there runs, so the AGENTS.md checks below read the interactive surface only.
# The developer guide documents them all the same (check 15). The optional
# `devcontainer` command is left out for the same reason: it is typed once per
# repository, and only on a project whose unattended runs go to GCP.
HEADLESS_SKILLS="auto-dev auto-dev-select"
OPTIONAL_SKILLS="devcontainer"
ALL_PUBLIC_SKILLS="$(for S in "$SDD_DIR"/*/SKILL.md "$REPO_ROOT"/shared/skills/*/SKILL.md \
                          "$TEMPLATE_ROOT/setup/SKILL.md"; do
    FM="$(frontmatter_of "$S")"
    printf '%s\n' "$FM" | grep -q '^user-invocable: true' || continue
    printf '%s\n' "$FM" | sed -n 's/^name:[[:space:]]*//p'
  done | LC_ALL=C sort)"
PUBLIC_SKILLS="$(printf '%s\n' "$ALL_PUBLIC_SKILLS" | grep -vxF -e auto-dev -e auto-dev-select -e devcontainer)"
assert_eq "the headless commands are exactly the two auto-dev ones" \
  "$HEADLESS_SKILLS" "$(printf '%s\n' "$ALL_PUBLIC_SKILLS" | grep -xF -e auto-dev -e auto-dev-select | tr '\n' ' ' | sed 's/ $//')"
assert_eq "and the optional one is devcontainer" \
  "$OPTIONAL_SKILLS" "$(printf '%s\n' "$ALL_PUBLIC_SKILLS" | grep -xF -e devcontainer)"
for GEN in "$GEN_SINGLE" "$GEN_WORKSPACE"; do
  assert_eq "$(basename "$GEN") does not describe the optional devcontainer command" "false" \
    "$(grep -q '/dev-setup:devcontainer' "$GEN" && echo true || echo false)"
done
SHIPPED_AGENTS="$(for A in "$TEMPLATE_ROOT"/.claude/agents/*.md "$REPO_ROOT"/shared/agents/*.md; do
    frontmatter_of "$A" | sed -n 's/^name:[[:space:]]*//p'
  done | LC_ALL=C sort -u)"
assert_eq "the surface the check reads is the six public commands" \
  "auto-sdd multi-sdd quick review sdd setup" "$(printf '%s' "$PUBLIC_SKILLS" | tr '\n' ' ')"

# The names from $2 (one per line) with no row in $1 matching $3, where `@`
# stands for the name.
missing_rows() {
  local file="$1" names="$2" pattern="$3" name missing=""
  while IFS= read -r name; do
    grep -q "${pattern//@/$name}" "$file" || missing="$missing $name"
  done <<<"$names"
  printf '%s' "${missing# }"
}
agents_table_rows() {
  awk '/^## Available agents/{f=1; next} /^## /{f=0} f && /^\| \*\*/' "$1" | grep -c .
}

for GEN in "$GEN_SINGLE" "$GEN_WORKSPACE"; do
  NAME="$(basename "$GEN")"
  assert_eq "$NAME lists every public command" "" \
    "$(missing_rows "$GEN" "$PUBLIC_SKILLS" '^| `/dev-setup:@')"
  assert_eq "$NAME lists no command the plugin does not expose" \
    "$(printf '%s\n' "$PUBLIC_SKILLS" | grep -c .)" "$(grep -c '^| `/dev-setup:' "$GEN")"
  assert_eq "$NAME lists every shipped agent by its frontmatter name" "" \
    "$(missing_rows "$GEN" "$SHIPPED_AGENTS" '^| \*\*@\*\* |')"
  assert_eq "$NAME names no agent that does not exist" \
    "$(printf '%s\n' "$SHIPPED_AGENTS" | grep -c .)" "$(agents_table_rows "$GEN")"
  assert_contains "$NAME carries quick's bar" "$(grep '^| `/dev-setup:quick' "$GEN")" "three files"

  # The stops are named, never counted: a count went stale once already.
  FLAT_GEN="$(flat "$GEN")"
  assert_contains "$NAME names the stops and closes the list" "$FLAT_GEN" \
    "for your approval of the spec — nowhere else"
  assert_eq "$NAME promises no checkpoint between phases" "false" \
    "$(printf '%s' "$FLAT_GEN" | grep -q 'each checkpoint' && echo true || echo false)"
  assert_eq "$NAME keeps git conventions out of the rules row" "false" \
    "$(grep '^| Rules on the code' "$GEN" | grep -q 'git' && echo true || echo false)"
  assert_contains "$NAME sends them to vcs-ops" "$(grep '^| Branch, commit' "$GEN")" '`vcs-ops`'
done

# Nothing loads the registry at session start — Claude Code reads AGENTS.md,
# which imports nothing — so no generated file may say it is read then.
for GEN in "$GEN_SINGLE" "$GEN_WORKSPACE" "$GEN_PROJECT" "$GEN_REGISTRY"; do
  assert_eq "$(basename "$GEN") never asks for the registry at session start" "false" \
    "$(flat "$GEN" | grep -qi 'start of each session\|start of a new session' && echo true || echo false)"
done
for GEN in "$GEN_PROJECT" "$GEN_REGISTRY"; do
  assert_contains "$(basename "$GEN") says when the registry is read" \
    "$(flat "$GEN")" "before adding something that may already exist"
done

# A placeholder the template declares and the reference does not fill is a
# render-template.sh failure on the first multi-project setup.
DOCUMENTED_VARS="$(grep -o '{{[A-Z_]*}}' "$AGENTS_GEN" | LC_ALL=C sort -u)"
for GEN in "$GEN_SINGLE" "$GEN_WORKSPACE" "$GEN_PROJECT"; do
  DECLARED_VARS="$(bash "$PLUGIN_SCRIPTS/render-template.sh" --in "$GEN" --list 2>/dev/null)"
  UNDOCUMENTED=""
  while IFS= read -r VAR; do
    [ -n "$VAR" ] || continue
    printf '%s\n' "$DOCUMENTED_VARS" | grep -qxF "{{$VAR}}" || UNDOCUMENTED="$UNDOCUMENTED $VAR"
  done <<<"$DECLARED_VARS"
  assert_eq "every placeholder of $(basename "$GEN") is one agents-generation.md fills" "" "${UNDOCUMENTED# }"
  [ "$GEN" = "$GEN_PROJECT" ] || continue
  assert_contains "the sub-project template carries the type-check" "$DECLARED_VARS" "TYPECHECK_COMMAND"
done

# UPDATE carries the whole plugin-owned tail, and says what it did with it.
FLAT_AGEN="$(flat "$AGENTS_GEN")"
assert_contains "UPDATE compares the tail from its heading" "$FLAT_AGEN" '`## Available agents`'
assert_contains "and the sub-project tail from its own" "$FLAT_AGEN" '`## Project registry`'
for LINE in "AGENTS.md: plugin sections updated" "AGENTS.md: plugin sections DECLINED" "AGENTS.md already current"; do
  assert_contains "the offer reports: $LINE" "$FLAT_AGEN" "$LINE"
done

# DE-17079 wants the generated file shorter; these fixes may not lengthen it.
for BUDGET in "$GEN_SINGLE:131" "$GEN_WORKSPACE:136" "$GEN_PROJECT:30"; do
  GEN="${BUDGET%:*}"; MAX="${BUDGET##*:}"
  assert_eq "$(basename "$GEN") stays within $MAX lines" "true" \
    "$([ "$(wc -l < "$GEN" | tr -d ' ')" -le "$MAX" ] && echo true || echo false)"
done


# ═══════════════════════════════════════════════════════════════════════════════
# 10. multi-sdd: the cap, the overlap and the composition (DE-16487)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The command fans out `n` autonomous runs from one session. Two of its three
# guarantees are testable without running anything: the cap is a script that
# exits non-zero, and the overlap comparison happens before any worktree exists.
# The third — that the command composes the workflow and reimplements none of it
# — is a property of the diff, so it is pinned as one.

echo ""
echo "── multi-preflight.sh (the cap) ──"

preflight() { bash "$PLUGIN_SCRIPTS/multi-preflight.sh" --json "$@" 2>/dev/null; }
preflight_exit() {
  bash "$PLUGIN_SCRIPTS/multi-preflight.sh" --json "$@" >/dev/null 2>&1
  printf '%s' "$?"
}

assert_eq "the cap the script enforces is 5" "5" \
  "$(preflight DE-1 | jq -r '.CAP')"

assert_eq "five tasks are accepted" "true" \
  "$(preflight DE-1 DE-2 DE-3 DE-4 DE-5 | jq -r '.ACCEPTED')"
assert_eq "and the caller sees a zero exit" "0" \
  "$(preflight_exit DE-1 DE-2 DE-3 DE-4 DE-5)"

# The refusal is an exit status, not a paragraph: a bound in prose gets read
# charitably ("six is close enough"), a non-zero exit does not.
assert_eq "six tasks are refused" "false" \
  "$(preflight DE-1 DE-2 DE-3 DE-4 DE-5 DE-6 | jq -r '.ACCEPTED')"
assert_eq "and the refusal is exit 3" "3" \
  "$(preflight_exit DE-1 DE-2 DE-3 DE-4 DE-5 DE-6)"
assert_contains "the reason names the cap" \
  "$(preflight DE-1 DE-2 DE-3 DE-4 DE-5 DE-6 | jq -r '.REASON')" "cap of 5"

# An empty SPRINT reaches the gate as zero ids: the message, and no run.
assert_eq "no task at all is refused" "3" "$(preflight_exit)"
assert_contains "and says how to name some" \
  "$(preflight | jq -r '.REASON')" "--from-sprint"

# Two runs on one task would race for the same branch name.
assert_eq "a duplicate id is refused" "3" "$(preflight_exit DE-1 DE-2 DE-1)"
assert_contains "and names the id" \
  "$(preflight DE-1 DE-2 DE-1 | jq -r '.REASON')" "DE-1 is listed twice"

# The id reaches a branch name and a shell command inside an agent prompt, so it
# is validated here rather than after four runs have started.
assert_eq "an id that is not a plain identifier is refused" "3" \
  "$(preflight_exit 'DE-1; rm -rf /')"

# --from-sprint validates the count only: the ids come back through the gate.
assert_eq "--from-sprint 2 passes the count through" "2" \
  "$(preflight --from-sprint 2 | jq -r '.FROM_SPRINT')"
assert_eq "and asks for no task yet" "0" \
  "$(preflight --from-sprint 2 | jq -r '.COUNT')"
assert_eq "--from-sprint over the cap is refused" "3" "$(preflight_exit --from-sprint 6)"
assert_eq "--from-sprint 0 is refused" "3" "$(preflight_exit --from-sprint 0)"
assert_eq "ids and --from-sprint together are refused" "3" \
  "$(preflight_exit --from-sprint 2 DE-1)"

assert_eq "the script ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/multi-preflight.sh" ] && echo true || echo false)"

echo ""
echo "── worktree-info.sh --impact (the overlap before the fan-out) ──"

# At pre-flight there is no spec and no worktree yet, only an estimate per task.
# The same comparison has to answer from the estimates, or the warning arrives
# after the branches have already diverged. The two worktrees of section 9 are
# still on disk, and that is deliberate: the estimates are compared against them
# too, so the paths below are ones no spec claims.
IMPACT_A="DE-10=src/multi/shared.ts,src/multi/only-a.ts"
IMPACT_B="DE-11=./src/multi/shared.ts src/multi/only-b.ts"

wt_impact() { (cd "$1" && shift && bash "$PLUGIN_SCRIPTS/worktree-info.sh" --json "$@" 2>/dev/null); }

IMPACT_OVERLAPS=$(wt_impact "$WT_SIDE" --impact "$IMPACT_A" --impact "$IMPACT_B" | jq -r '.OVERLAPS')

# The label is what the warning names, so the developer knows which two tasks to
# choose between. And `./src/...` has to match `src/...`: a key that does not
# match is an overlap silently missed.
assert_contains "two estimates sharing a file are named, with both labels" \
  "$IMPACT_OVERLAPS" "src/multi/shared.ts	DE-10,DE-11"

assert_eq "a file only one task declares is not an overlap" "" \
  "$(printf '%s\n' "$IMPACT_OVERLAPS" | grep -E 'only-a|only-b' || true)"

# A task about to start is compared against the worktrees already in flight, for
# free — that is the reason this lives in the same script.
assert_contains "an estimate collides with a worktree already in flight" \
  "$(wt_impact "$WT_SIDE" --impact "DE-10=src/user/user.service.ts" | jq -r '.OVERLAPS')" \
  "src/user/user.service.ts	feat/DE-2-beta,DE-10"

# And a task whose worktree already exists must not overlap with *itself*: the
# declarer is the task, not the checkout, so the spec on disk and the estimate
# for the same run are one declarer. A false conflict shown to a human is the
# noise this warning exists to avoid.
assert_eq "a task does not collide with its own worktree" "" \
  "$(wt_impact "$WT_SIDE" --impact "DE-2=src/user/user.service.ts" \
     | jq -r '.OVERLAPS' | grep -E 'user.service' || true)"

# The port offset is unaffected by the new mode.
assert_eq "the port offset still answers" "1" \
  "$(wt_impact "$WT_SIDE" --impact "$IMPACT_A" | jq -r '.PORT_OFFSET')"

echo ""
echo "── multi-sdd composes, it does not reimplement ──"

MULTI="$SDD_DIR/multi-sdd"

assert_eq "the command ships" "true" \
  "$([ -f "$MULTI/SKILL.md" ] && echo true || echo false)"
assert_eq "and in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/skills/multi-sdd/SKILL.md" ] && echo true || echo false)"

# Only a person starts a fan-out of five background runs.
assert_contains "a fan-out is never inferred by the model" \
  "$(cat "$MULTI/SKILL.md")" "disable-model-invocation: true"
assert_contains "a person can invoke it" \
  "$(cat "$MULTI/SKILL.md")" "user-invocable: true"

# The cap is enforced by the script, and the command has to actually call it —
# a flag declared and never acted on is worse than no flag at all.
assert_contains "the command runs the gate" \
  "$(cat "$MULTI/SKILL.md")" "multi-preflight.sh"

# And passes each id as one quoted argument. Splicing $ARGUMENTS into that line
# would let an id carrying a `;` run as shell *before* the check written to
# reject it — the validation would be bypassed by exactly what it validates.
assert_eq "no raw \$ARGUMENTS is spliced into the gate call" "" \
  "$(grep -n 'multi-preflight.sh.*\$ARGUMENTS' "$MULTI"/SKILL.md "$MULTI"/reference/*.md || true)"
assert_contains "each id goes in as one quoted argument" \
  "$(cat "$MULTI/SKILL.md")" '--task "DE-1"'

# It launches the PR 9 workflow rather than carrying a flow of its own.
assert_contains "it launches the auto-sdd workflow" \
  "$(cat "$MULTI"/SKILL.md "$MULTI"/reference/*.md)" "dev-setup:auto-sdd-run"

# Acceptance criterion 4: the spec -> challenge -> dev -> verify logic lives in
# exactly one place. The command must not name a lens, declare a phase, or hold
# a spec template — those are the workflow's, and a second copy is a second
# thing to keep in step.
assert_eq "the command declares no phase and names no lens" "" \
  "$(grep -nE "phase\(|refuted|'simpler'|'testable'|specMarkdown|planSteps" \
       "$MULTI"/SKILL.md "$MULTI"/reference/*.md || true)"

# Both launchers act on the outcome through the one shared contract.
assert_eq "the outcomes contract is a plugin reference, not a skill's own" "true" \
  "$([ -f "$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md" ] \
     && echo true || echo false)"
for LAUNCHER in auto-sdd multi-sdd; do
  assert_contains "$LAUNCHER cites the shared outcomes contract" \
    "$(cat "$SDD_DIR/$LAUNCHER"/SKILL.md "$SDD_DIR/$LAUNCHER"/reference/*.md 2>/dev/null)" \
    "reference/run-outcomes.md"
done
assert_eq "nothing still points at the old per-skill path" "" \
  "$(grep -rln "reference/outcomes.md" "$REPO_ROOT/templates" "$REPO_ROOT/dist" \
       "$REPO_ROOT/README.md" "$REPO_ROOT/docs" 2>/dev/null || true)"

echo ""
echo "── the Challenge improves the spec, it never stops the run ──"

# The gate used to let a reviewer label its own objection a business decision
# and halt on it, before the spec was ever rewritten on it: on DE-16864 every
# lens did, on objections the repository itself settled. The phase is now run
# for real — the workflow body under stubbed agents, the way the harness runs
# it — so what is pinned is the behaviour, not a line of its source: how many
# agents it launches included, since one pass is the whole point of its shape.
if [ -f "$AUTO_SDD" ] && command -v node >/dev/null 2>&1; then
  cat > "$WORK_DIR/workflow-sim.cjs" <<'NODEJS'
// Runs auto-sdd-run.js with stubbed agents. argv[3] maps a reviewer focus to what
// it answers: "ok" (satisfied), "propose", or "dead"; "revise": "dead" makes
// the reviser return nothing. The reviser declines simpler on an ADR, applies
// scope, and leaves testable without an answer.
const fs = require('fs');
const vm = require('vm');

const src = fs.readFileSync(process.argv[2], 'utf8');
const meta = src.match(/^export const meta = \{[\s\S]*?\n\}\n/);
const scenario = JSON.parse(process.argv[3]);
const prompts = {};
const calls = [];
const spec = {
  slug: 'sim', specMarkdown: '# spec', planSteps: ['one'],
  reqs: [{ id: 'REQ-1', statement: 'a requirement', test: 'a test' }],
  deviations: ['the task asks for <style scoped>; the styling ADR forbids it'],
  toConfirm: [],
};

async function agent(prompt, opts) {
  const label = opts.label;
  prompts[label] = prompt;
  calls.push(label);
  if (label.startsWith('spec:')) return spec;
  if (label.startsWith('revise:')) {
    if (scenario.revise === 'dead') return null;
    return Object.assign({}, spec, {
      responses: [
        { lens: 'simpler', applied: false, note: 'the vendoring ADR backs it' },
        { lens: 'Scope', applied: true, note: 'REQ-2 dropped' },
      ],
    });
  }
  if (label.startsWith('challenge:')) {
    const key = label.split(':')[1];
    const answer = scenario[key] || 'ok';
    if (answer === 'dead') return null;
    if (answer === 'ok') return { satisfied: true, reason: 'checked' };
    return { satisfied: false, reason: key + ' proposal', suggestion: 'change', grounds: 'an ADR' };
  }
  if (label.startsWith('dev:')) return { worktreePath: '/wt', branch: 'b', specPath: 'p', commits: [] };
  if (label.startsWith('verify:')) {
    return { passed: true, output: 'green', notStarted: scenario.notStarted || [] };
  }
  return null;
}

// argv[4], when given, overrides the launch arguments. The default stack is a
// declared project with no type checker: lint and test, typecheck absent.
const overrides = process.argv[4] ? JSON.parse(process.argv[4]) : {};
const context = {
  args: Object.assign({
    taskId: 'DE-1', pluginRoot: '/plugin', baseBranch: 'origin/next',
    stack: { lint: 'make lint', typecheck: '', test: 'make test' },
  }, overrides),
  agent,
  parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
  phase() {},
  log() {},
};
vm.runInNewContext('(async () => {' + src.slice(meta[0].length) + '})()', context).then((out) => {
  console.log(JSON.stringify({
    status: out.status,
    stage: out.stage || '',
    agents: calls.length,
    reviews: calls.filter((l) => l.startsWith('challenge:')).length,
    revisions: calls.filter((l) => l.startsWith('revise:')).length,
    open: (out.openPoints || []).map((o) => o.lens).join(','),
    applied: (out.applied || []).map((o) => o.lens).join(','),
    answers: (out.openPoints || []).map((o) => o.answer).join('|'),
    unchecked: (out.unchecked || []).join(','),
    deviations: (out.deviations || []).length,
    grounds: (prompts['revise:DE-1'] || '').includes('grounds: an ADR'),
    devSees: (prompts['dev:DE-1'] || '').includes('the styling ADR forbids it'),
    devAbsent: /typecheck:\s+\(none\)/.test(prompts['dev:DE-1'] || '')
      && (prompts['dev:DE-1'] || '').includes('say so in `notes`'),
    precedence: Object.keys(prompts).filter((l) => /^(spec|challenge|revise):/.test(l))
      .every((l) => prompts[l].includes('settle it in this')),
    verified: calls.includes('verify:DE-1'),
    unverified: (out.unverified || []).map((u) => u.kind + '=' + u.command).join(','),
    unverifiedReason: (out.unverified || []).map((u) => u.reason).join('|'),
    devSkips: /lint:\s+make lint\s+\(NOT RUNNABLE HERE/.test(prompts['dev:DE-1'] || '')
      && (prompts['dev:DE-1'] || '').includes('php is 8.3'),
    verifySkips: /lint:\s+make lint\s+\(skip\)/.test(prompts['verify:DE-1'] || ''),
  }));
});
NODEJS

  sim() { node "$WORK_DIR/workflow-sim.cjs" "$AUTO_SDD" "$1" ${2:+"$2"} 2>&1; }
  field() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

  SIM=$(sim '{"simpler":"propose","scope":"propose","testable":"propose"}')
  assert_eq "three reviewers that all propose still reach the merge request" \
    "ready-for-mr" "$(field "$SIM" status)"
  assert_eq "the reviewers look once and the spec is revised once" \
    "3 1" "$(field "$SIM" reviews) $(field "$SIM" revisions)"
  assert_eq "the reviser reads what each proposal rests on" \
    "true" "$(field "$SIM" grounds)"
  assert_eq "an applied proposal is in the spec, not an open point" \
    "scope" "$(field "$SIM" applied)"
  assert_eq "a declined or unanswered proposal travels as an open point" \
    "simpler,testable" "$(field "$SIM" open)"
  assert_eq "with the author's answer next to it, empty when there was none" \
    "the vendoring ADR backs it|" "$(field "$SIM" answers)"
  assert_eq "the author, the reviewers and the reviser read the same precedence" \
    "true" "$(field "$SIM" precedence)"
  assert_eq "a departure from the task reaches the developer agent" \
    "true" "$(field "$SIM" devSees)"
  assert_eq "and travels in the outcome" "1" "$(field "$SIM" deviations)"

  SIM=$(sim '{}')
  assert_eq "three satisfied reviewers cost three agents and no revision" \
    "3 0 " "$(field "$SIM" reviews) $(field "$SIM" revisions) $(field "$SIM" open)"
  # The simulation's project declares no type checker, so typecheck prints as
  # (none): the dev agent has to be told to skip it and to say so in `notes`,
  # not to wait — and the run goes on with lint and test (DE-17535, REQ-3).
  assert_eq "a command declared absent: the dev agent is told to skip it and say so in notes" \
    "true" "$(field "$SIM" devAbsent)"
  assert_eq "and the run proceeds on the other two" "ready-for-mr" "$(field "$SIM" status)"

  # REQ-9: a run with no command at all could not verify anything, and the
  # outcome would be certain before the first agent. It ends at intake, free.
  SIM=$(sim '{}' '{"stack":null}')
  assert_eq "no stack at all ends at intake" "failed intake" \
    "$(field "$SIM" status) $(field "$SIM" stage)"
  assert_eq "without launching a single agent" "0" "$(field "$SIM" agents)"
  SIM=$(sim '{}' '{"stack":{"lint":"","typecheck":"","test":""}}')
  assert_eq "three empty commands, as a launcher passes them, end at intake" "failed intake" \
    "$(field "$SIM" status) $(field "$SIM" stage)"
  assert_eq "without launching a single agent either" "0" "$(field "$SIM" agents)"

  # REQ-17: a toolchain this environment lacks does not stop the run. The
  # commands it cannot start are never run, and they travel to the merge request.
  SIM=$(sim '{}' '{"unavailable":["lint","test"],"unavailableReason":"php is 8.3"}')
  assert_eq "every command unavailable: the run still reaches the merge request" \
    "ready-for-mr false" "$(field "$SIM" status) $(field "$SIM" verified)"
  assert_eq "with each command it could not run in unverified" \
    "lint=make lint,test=make test" "$(field "$SIM" unverified)"
  assert_eq "and the dev agent is told not to run them, and why" "true" "$(field "$SIM" devSkips)"
  SIM=$(sim '{}' '{"unavailable":["lint"],"unavailableReason":"php is 8.3"}')
  assert_eq "one command unavailable: Verify runs the others and skips it" \
    "ready-for-mr true true" "$(field "$SIM" status) $(field "$SIM" verified) $(field "$SIM" verifySkips)"
  assert_eq "and it is reported unverified" "lint=make lint" "$(field "$SIM" unverified)"
  SIM=$(sim '{"notStarted":["make test"]}')
  assert_eq "a command that did not start at Verify is unverified, not red" \
    "ready-for-mr test=make test" "$(field "$SIM" status) $(field "$SIM" unverified)"
  SIM=$(sim '{}' '{"unavailable":["typecheck","bogus"]}')
  assert_eq "an unavailable kind with no command, or no kind at all, is ignored" \
    "ready-for-mr  true" "$(field "$SIM" status) $(field "$SIM" unverified) $(field "$SIM" verified)"

  SIM=$(sim '{"simpler":"propose","revise":"dead"}')
  assert_eq "a reviser that returns nothing leaves every proposal open" \
    "ready-for-mr simpler" "$(field "$SIM" status) $(field "$SIM" open)"

  SIM=$(sim '{"scope":"dead"}')
  assert_eq "a reviewer that dies twice is reported, and the run goes on" \
    "ready-for-mr scope 4" "$(field "$SIM" status) $(field "$SIM" unchecked) $(field "$SIM" reviews)"
else
  printf '%s  skip%s  node not found: the Challenge simulation needs it\n' "$DIM" "$NC"
fi

if [ -f "$AUTO_SDD" ]; then
  assert_eq "no path of the workflow returns needs-human" "" \
    "$(grep -n "status: 'needs-human'" "$AUTO_SDD" || true)"
fi

echo ""
echo "── the launchers refuse before the board (DE-17535) ──"

# The check is worth something only where it stands: before anything a refused
# run would leave behind. So what is pinned is its position, on the extracted
# range, not merely its presence in the file.
line_of() { printf '%s\n' "$1" | grep -n -F -- "$2" | head -1 | cut -d: -f1; }
assert_before() {
  local label="$1" text="$2" first="$3" second="$4" a b
  a=$(line_of "$text" "$first")
  b=$(line_of "$text" "$second")
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
    pass "$label"
  else
    fail "$label" "expected '$first' (line ${a:-none}) before '$second' (line ${b:-none})"
  fi
}

AUTO_STEPS=$(sed -n '/^## 1\. /,/^## 3\. /p' "$SDD_DIR/auto-sdd/SKILL.md")
QP_CALL="quality-preflight.sh\" --require-declared"
for NEEDLE in 'BACKLOG' 'fork-point.md' 'status: IN PROGRESS' 'task-clock.sh'; do
  assert_before "auto-sdd checks its commands before: $NEEDLE" "$AUTO_STEPS" "$QP_CALL" "$NEEDLE"
done
assert_contains "and sends any non-zero exit to the outcomes contract" "$AUTO_STEPS" "run-outcomes.md"

OUTCOMES="$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md"
NOT_STARTED=$(sed -n '/^## When the run does not start/,$p' "$OUTCOMES")
assert_contains "the refusal of a SPRINT task is one BLOCKED bail-out" "$NOT_STARTED" "SPRINT → BLOCKED"
assert_contains "a BACKLOG task is left as found" "$NOT_STARTED" "left as found"
assert_contains "the refusal names the check" "$NOT_STARTED" "quality-preflight.sh"
assert_contains "auto-sdd lets an environment without the toolchain through" \
  "$AUTO_STEPS" "--allow-unavailable"
assert_contains "and passes what it cannot run to the workflow" \
  "$(cat "$SDD_DIR/auto-sdd/SKILL.md")" '"unavailable"'
assert_contains "multi-sdd does the same" "$(cat "$SDD_DIR/multi-sdd/reference/preflight.md")" "--allow-unavailable"
assert_contains "and its launch passes it on" \
  "$(cat "$SDD_DIR/multi-sdd/reference/fan-out.md")" '"unavailable"'
READY_SECTION=$(sed -n '/^## ready-for-mr/,/^## What a run leaves behind/p' "$OUTCOMES")
assert_contains "ready-for-mr carries the checks nobody ran" "$READY_SECTION" "unverified"
assert_contains "and the merge request opens with them" "$READY_SECTION" "**not verified**"

MULTI_PRE="$SDD_DIR/multi-sdd/reference/preflight.md"
MULTI_TEXT=$(cat "$MULTI_PRE")
assert_before "multi-sdd checks once, before the first task read" "$MULTI_TEXT" "$QP_CALL" "INTENT: read"
assert_before "and before the triage" "$MULTI_TEXT" "$QP_CALL" "## Triage"
assert_eq "and its refusal moves no task" "" "$(grep -n 'BLOCKED' "$MULTI_PRE" || true)"

# REQ-15: in an ephemeral session a failed run's work reaches origin, so it
# survives the session — and only pushed: the merge request is a decision. The
# board is the report (DE-17159 — the branch of a routine run was lost, and the
# BLOCKED comment was the only trace), so it says what is missing and why.
FAILED_SECTION=$(sed -n '/^## failed/,/^## ready-for-mr/p' "$OUTCOMES")
assert_contains "a failed run in a cloud session is keyed on CLAUDE_CODE_REMOTE" "$FAILED_SECTION" "CLAUDE_CODE_REMOTE"
assert_contains "it saves what the worktree holds through the one script past the gate" "$FAILED_SECTION" 'save-failed-run.sh'
assert_contains "and pushes the branch as it is" "$FAILED_SECTION" 'pushes the branch as it is'
assert_contains "the spec is saved when no branch holds it" "$FAILED_SECTION" '--spec-file'
assert_contains "a run that broke is saved the same way" "$FAILED_SECTION" 'stage `broken`'
assert_contains "and the launcher sends it there" "$(cat "$SDD_DIR/auto-sdd/SKILL.md")" 'stage `broken`'
assert_contains "even when it holds nothing" "$FAILED_SECTION" 'an empty commit when it'
assert_contains "with no merge request" "$FAILED_SECTION" "no merge request"
assert_contains "the dev agent's notes are read" "$FAILED_SECTION" '`notes`'
assert_contains "the BLOCKED note says what is missing" "$FAILED_SECTION" '**what is missing**'
assert_contains "and how to resume once the session is gone" "$FAILED_SECTION" '/dev-setup:sdd <taskId>'

# REQ-12: the interactive flows do not stop on it — a person is there — but
# they say it at the start, not in the closing summary.
QUICK_STEP1=$(sed -n '/^1\. \*\*The change\.\*\*/,/^2\. \*\*The branch\.\*\*/p' "$SDD_DIR/quick/SKILL.md")
assert_contains "quick says COMMANDS_SOURCE=none in its first step" "$QUICK_STEP1" "COMMANDS_SOURCE"
SDD_STEP4=$(sed -n '/^## 4\. /,$p' "$SDD_DIR/sdd/reference/intake.md")
assert_contains "sdd says it in its intake step 4" "$SDD_STEP4" "COMMANDS_SOURCE"
assert_contains "sdd-dev keeps skipping a command declared absent" \
  "$(cat "$SDD_DIR/sdd-dev/reference/methodologies.md")" "declared absent"

# REQ-13 and REQ-14: the setup writes the declaration and verifies it. The step
# is prose the model follows, so what is pinned is that it calls the scripts
# that do the deterministic part, and that a decline cannot go unreported.
SETUP_DIR="$REPO_ROOT/templates/dev-setup/setup"
QC_REF="$SETUP_DIR/reference/quality-commands.md"
assert_eq "step 3b has its reference" "true" "$([ -f "$QC_REF" ] && echo true || echo false)"
QC_TEXT=$(cat "$QC_REF" 2>/dev/null)
assert_contains "3b proposes the candidates the script finds" "$QC_TEXT" "quality-candidates.sh"
assert_contains "and asks in one AskUserQuestion call" "$QC_TEXT" "AskUserQuestion"
assert_contains "and runs every declared command once" "$QC_TEXT" 'quality-preflight.sh" --run'
assert_contains "and hands the declared commands to Steps 4 and 5" "$QC_TEXT" ".stack.json"
assert_contains "a kind with no candidate is still asked" "$QC_TEXT" "no candidate"
assert_contains "UPDATE proposes a declaration to a project that has none" "$QC_TEXT" "UPDATE"
assert_eq "a decline is a DECLINED summary line naming both launchers" "1" \
  "$(printf '%s\n' "$QC_TEXT" | grep 'DECLINED' | grep 'auto-sdd' | grep -c 'multi-sdd')"
assert_contains "the setup table routes step 3b to it" \
  "$(cat "$SETUP_DIR/SKILL.md")" "| 3b |"
assert_eq "the setup skill stays within its 500-word budget" "true" \
  "$([ "$(wc -w < "$SETUP_DIR/SKILL.md")" -le 500 ] && echo true || echo false)"
assert_eq "the manifest ships the reference" "true" \
  "$(jq '.setup_reference | index("quality-commands.md") != null' "$REPO_ROOT/templates/dev-setup/manifest.json")"
assert_eq "and the build does" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/skills/setup/reference/quality-commands.md" ] && echo true || echo false)"
for MODE_REF in existing.md greenfield.md; do
  assert_contains "the $MODE_REF summary collects 3b's line" \
    "$(sed -n '/^## Step 9/,$p' "$SETUP_DIR/reference/$MODE_REF")" "3b"
done
assert_contains "existing.md lists the new detect-stack keys" \
  "$(cat "$SETUP_DIR/reference/existing.md")" "COMMANDS_SOURCE"
# REQ-16: the declaration is documented where a developer and an upgrader look.
assert_contains "the developer guide documents the declaration" \
  "$(cat "$REPO_ROOT/docs/developer-guide.md")" ".claude/quality-commands.json"
assert_contains "and the launcher check" \
  "$(cat "$REPO_ROOT/docs/developer-guide.md")" "quality-preflight.sh"
assert_contains "the migration page records the contract change" \
  "$(cat "$REPO_ROOT/docs/migration-v2-to-v3.md")" "quality-commands.json"
for NEW_SCRIPT in quality-candidates.sh quality-preflight.sh; do
  assert_contains "AGENTS.md lists $NEW_SCRIPT" "$(cat "$REPO_ROOT/AGENTS.md")" "\`$NEW_SCRIPT"
done
assert_contains "AGENTS.md lists the new detect-stack keys" \
  "$(grep -F '`detect-stack.sh`' "$REPO_ROOT/AGENTS.md")" "COMMANDS_SOURCE"

assert_eq "check 16 finds every ask of 3b reported" "" \
  "$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict 2>&1 | grep 'SETUP_ASK_UNREPORTED' | grep 'quality-commands.md' || true)"

# ═══════════════════════════════════════════════════════════════════════════════
# 11. task-clock.sh: how long the task took
# ═══════════════════════════════════════════════════════════════════════════════
#
# The clock is stamped at the IN PROGRESS move and read back when the merge
# request opens. Two properties matter more than the arithmetic: the state
# cannot reach the working tree (the closure runs `git add -A` right before it),
# and a clock nobody started reports *nothing* rather than a plausible number.

echo ""
echo "── task-clock.sh (the work clock) ──"

CLOCK_REPO="$WORK_DIR/clock-repo"
mkdir -p "$CLOCK_REPO"
(
  cd "$CLOCK_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
) >/dev/null 2>&1

clock() { (cd "${CLOCK_CWD:-$CLOCK_REPO}" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --json "$@" 2>/dev/null); }
clock_exit() {
  (cd "${CLOCK_CWD:-$CLOCK_REPO}" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --json "$@") >/dev/null 2>&1
  printf '%s' "$?"
}

CLOCK_START=$(clock --task DE-700 --start)

# ClickUp's own format, and the one a human reads in the brief.
assert_eq "--start stamps a minute-precision local timestamp" "true" \
  "$(printf '%s' "$CLOCK_START" | jq -r '.STARTED_AT' \
     | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$' && echo true || echo false)"
assert_eq "and reports the clock as running" "true" \
  "$(printf '%s' "$CLOCK_START" | jq -r '.RUNNING')"

# A resumed task re-runs intake. The first stamp is the real start, so it stands:
# restarting it would silently discard the hours already spent.
CLOCK_AGAIN=$(clock --task DE-700 --start)
assert_eq "a second --start does not restart the clock" "already-running" \
  "$(printf '%s' "$CLOCK_AGAIN" | jq -r '.REASON')"
assert_eq "and keeps the first stamp" \
  "$(printf '%s' "$CLOCK_START" | jq -r '.STARTED_AT')" \
  "$(printf '%s' "$CLOCK_AGAIN" | jq -r '.STARTED_AT')"

# The state lives in the git directory, which `git add -A` cannot reach. The
# closure stages the whole tree one step before it stops the clock.
assert_eq "the clock leaves the working tree clean" "" \
  "$(cd "$CLOCK_REPO" && git status --porcelain)"
assert_eq "and keeps its state under the git directory" "true" \
  "$(printf '%s' "$CLOCK_START" | jq -r '.STATE_FILE' | grep -q '/\.git/dev-setup/task-clock/' \
     && echo true || echo false)"

CLOCK_STOP=$(clock --task DE-700 --stop)

# COMMENT is the whole contract with the board: the flows post it verbatim, so
# it has to arrive written, not as numbers for the model to phrase.
assert_contains "--stop returns the line to post" \
  "$(printf '%s' "$CLOCK_STOP" | jq -r '.COMMENT')" "Time in progress:"
assert_contains "and the line names both ends of the interval" \
  "$(printf '%s' "$CLOCK_STOP" | jq -r '.COMMENT')" \
  "$(printf '%s' "$CLOCK_START" | jq -r '.STARTED_AT')"
assert_eq "a closed interval is never reported as 0m" "false" \
  "$(printf '%s' "$CLOCK_STOP" | jq -r '.DURATION' | grep -qE '^0m$' && echo true || echo false)"

# Stopping twice is not a second measurement.
assert_eq "a second --stop measures nothing" "already-stopped" \
  "$(clock --task DE-700 --stop | jq -r '.REASON')"
assert_eq "and posts nothing" "" "$(clock --task DE-700 --stop | jq -r '.COMMENT')"

# The failure this guards is the one the contract forbids in prose: a flow that
# reaches the merge request with no start stamp must post no duration at all,
# because the only other option is an invented one.
NEVER_STARTED=$(clock --task DE-701 --stop)
assert_eq "a clock nobody started reports no-start-stamp" "no-start-stamp" \
  "$(printf '%s' "$NEVER_STARTED" | jq -r '.REASON')"
assert_eq "and offers no duration to post" "" \
  "$(printf '%s' "$NEVER_STARTED" | jq -r '.COMMENT')$(printf '%s' "$NEVER_STARTED" | jq -r '.DURATION')"
assert_eq "and exits zero — it is an answer, not a failure" "0" \
  "$(clock_exit --task DE-702 --stop)"

# Two sittings on one task: each interval is its own reading and the total adds
# up, so a task that goes BLOCKED and comes back is not counted twice or lost.
CLOCK_LOG="$CLOCK_REPO/.git/dev-setup/task-clock/DE-703.log"
mkdir -p "$(dirname "$CLOCK_LOG")"
CLOCK_NOW=$(date +%s)
{
  printf 'start\t%s\t%s\n' "$((CLOCK_NOW - 20000))" "2026-09-17 09:00"
  printf 'stop\t%s\t%s\t%s\n' "$((CLOCK_NOW - 11900))" "2026-09-17 11:15" "135"
  printf 'start\t%s\t%s\n' "$((CLOCK_NOW - 5400))" "2026-09-18 10:00"
} > "$CLOCK_LOG"
CLOCK_MULTI=$(clock --task DE-703 --stop)

assert_eq "the second interval measures itself" "1h 30m" \
  "$(printf '%s' "$CLOCK_MULTI" | jq -r '.DURATION')"
assert_eq "the total carries both sittings" "3h 45m" \
  "$(printf '%s' "$CLOCK_MULTI" | jq -r '.TOTAL_DURATION')"
assert_contains "and the line says it is a total over two sessions" \
  "$(printf '%s' "$CLOCK_MULTI" | jq -r '.COMMENT')" "total over 2 sessions"

# The task id reaches a file path here, exactly as it reaches a branch name in
# sdd-start.sh. Both refuse anything that is not a plain identifier.
assert_eq "a task id that would escape the state directory is refused" "1" \
  "$(clock_exit --task '../../hooks/pre-commit' --start)"
assert_eq "and so is one carrying a shell command" "1" \
  "$(clock_exit --task 'DE-1; rm -rf /' --stop)"
assert_eq "a call with neither --start nor --stop is a usage error" "1" \
  "$(clock_exit --task DE-700)"

# One clock per task, shared by every checkout of the repository: the
# interactive flow stamps the start inside its worktree, `auto-sdd` stamps it in
# the launcher's checkout, and the same task must not end up with two clocks.
if git -C "$CLOCK_REPO" worktree add -q "$WORK_DIR/clock-wt" -b clock-side >/dev/null 2>&1; then
  # Compared by suffix: on macOS $TMPDIR sits under /tmp, a symlink to
  # /private/tmp, and git reports the physical path from inside the worktree.
  assert_contains "a worktree reads the same clock as the main checkout" \
    "$(CLOCK_CWD="$WORK_DIR/clock-wt" clock --task DE-700 --stop | jq -r '.STATE_FILE')" \
    "/clock-repo/.git/dev-setup/task-clock/DE-700.log"
fi

assert_eq "the script ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/task-clock.sh" ] && echo true || echo false)"

# ── --status: the reader that consumes nothing ──
#
# The merge-request hook asks whether a task is still in progress here. Asking
# must not be answering: a --stop in its place would hand the measurement to a
# session that may never post it, and the flow's own --stop would then find an
# already-stopped clock with nothing to report.

CLOCK_OPEN=$(clock --task DE-704 --start)
CLOCK_LOG_704="$CLOCK_REPO/.git/dev-setup/task-clock/DE-704.log"
CLOCK_LINES_BEFORE=$(wc -l < "$CLOCK_LOG_704" | tr -d ' ')
CLOCK_STATUS=$(clock --task DE-704 --status)

assert_eq "--status sees the running clock" "true" \
  "$(printf '%s' "$CLOCK_STATUS" | jq -r '.RUNNING')"
assert_eq "and reports the stamp --start wrote" \
  "$(printf '%s' "$CLOCK_OPEN" | jq -r '.STARTED_AT')" \
  "$(printf '%s' "$CLOCK_STATUS" | jq -r '.STARTED_AT')"
assert_eq "and writes nothing" "$CLOCK_LINES_BEFORE" \
  "$(wc -l < "$CLOCK_LOG_704" | tr -d ' ')"

# Without --task it answers for the repository: which clocks are open at all.
# That is the question a caller who does not know the task id has to ask.
assert_eq "--status with no task lists what is open" "DE-704" \
  "$(clock --status | jq -r '.OPEN_TASKS')"
assert_eq "and counts it" "1" "$(clock --status | jq -r '.OPEN_COUNT')"

CLOCK_STATUS_STOPPED=$(clock --task DE-704 --stop >/dev/null && clock --task DE-704 --status)
assert_eq "a stopped clock is not running" "false" \
  "$(printf '%s' "$CLOCK_STATUS_STOPPED" | jq -r '.RUNNING')"
assert_eq "and leaves nothing open in the repository" "0" \
  "$(clock --status | jq -r '.OPEN_COUNT')"
assert_eq "--status still measures nothing on a clock nobody started" "no-start-stamp" \
  "$(clock --task DE-705 --status | jq -r '.REASON')"

# ── RECENT_TASKS: a clock stopped a moment ago is still the task in play (DE-17077) ──
#
# A failed run stops its clock and then asks for the BLOCKED move: the
# notification hook has to name that task for the few seconds in between, and
# it can only ask the reader that consumes nothing.
CLOCK_RECENT_REPO="$WORK_DIR/clock-recent-repo"
mkdir -p "$CLOCK_RECENT_REPO"
git_init "$CLOCK_RECENT_REPO" >/dev/null 2>&1
recent_clock() { (cd "$CLOCK_RECENT_REPO" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --json "$@" 2>/dev/null); }

recent_clock --task DE-710 --start >/dev/null
recent_clock --task DE-710 --stop >/dev/null
recent_clock --task DE-711 --start >/dev/null
CLOCK_RECENT_DIR="$CLOCK_RECENT_REPO/.git/dev-setup/task-clock"
CLOCK_AGED=$(date +%s)
{
  printf 'start\t%s\t%s\n' "$((CLOCK_AGED - 1200))" "2026-10-16 09:00"
  printf 'stop\t%s\t%s\t%s\n' "$((CLOCK_AGED - 600))" "2026-10-16 09:10" "10"
} > "$CLOCK_RECENT_DIR/DE-712.log"

CLOCK_RECENT=$(recent_clock --status)
assert_eq "a task stopped seconds ago is in RECENT_TASKS" "DE-710" \
  "$(printf '%s' "$CLOCK_RECENT" | jq -r '.RECENT_TASKS')"
assert_eq "and not in OPEN_TASKS, which holds only the open one" "DE-711" \
  "$(printf '%s' "$CLOCK_RECENT" | jq -r '.OPEN_TASKS')"
assert_eq "an open task is never recent, a stop 600 s old is not either" "false" \
  "$(printf '%s' "$CLOCK_RECENT" | jq -r '.RECENT_TASKS' | grep -qE 'DE-711|DE-712' && echo true || echo false)"
assert_eq "--status with a task reports the same RECENT_TASKS" "DE-710" \
  "$(recent_clock --task DE-711 --status | jq -r '.RECENT_TASKS')"

CLOCK_RECENT_BEFORE=$(cat "$CLOCK_RECENT_DIR"/*.log | cksum)
recent_clock --status >/dev/null
recent_clock --task DE-710 --status >/dev/null
assert_eq "and reading it leaves every log byte-identical" "$CLOCK_RECENT_BEFORE" \
  "$(cat "$CLOCK_RECENT_DIR"/*.log | cksum)"

# ── Both ends, in every flow ──
#
# A clock started and never read is a file nobody looks at; a clock read and
# never started is the no-start-stamp path on every task. Each flow has to call
# both sides, and the rule they all cite has to live in one place.
CLOCK_CONTRACT="$REPO_ROOT/templates/dev-setup/.claude/reference/clickup-contract.md"
assert_contains "the contract owns the clock rule" \
  "$(cat "$CLOCK_CONTRACT")" "## The work clock"
assert_contains "and forbids composing a duration" \
  "$(cat "$CLOCK_CONTRACT")" "Never write the duration yourself"

# sdd stamps at intake and reads at closure; quick does both in its SKILL.md;
# the launchers stamp at launch and read in the shared outcomes contract.
for CLOCK_SIDE in \
  "sdd/reference/intake.md=--start" \
  "sdd/reference/closure.md=--stop" \
  "quick/SKILL.md=stop the clock" \
  "auto-sdd/SKILL.md=--start" \
  "multi-sdd/reference/fan-out.md=--start"; do
  CLOCK_FILE="${CLOCK_SIDE%%=*}"
  CLOCK_NEEDLE="${CLOCK_SIDE#*=}"
  assert_contains "$CLOCK_FILE calls the clock" \
    "$(cat "$SDD_DIR/$CLOCK_FILE")" "task-clock.sh"
  assert_contains "$CLOCK_FILE names its side of it" \
    "$(cat "$SDD_DIR/$CLOCK_FILE")" "$CLOCK_NEEDLE"
done

# Both autonomous outcomes that close a task carry the reading: ready-for-mr on
# the CODE REVIEW move, failed on the BLOCKED one. Scoped per section, so the
# check cannot be satisfied by one of them mentioning it twice.
CLOCK_OUTCOMES="$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md"
for CLOCK_SECTION in failed ready-for-mr; do
  assert_contains "the $CLOCK_SECTION outcome closes the clock" \
    "$(awk -v s="^## $CLOCK_SECTION" '$0 ~ s { p = 1; next } /^## / { p = 0 } p' \
         "$CLOCK_OUTCOMES")" \
    "clock"
done

# ═══════════════════════════════════════════════════════════════════════════════
# 12. post-merge-request.sh: the closure that survives the flow
# ═══════════════════════════════════════════════════════════════════════════════
#
# The defect: on DE-16879 the push failed, the session was cleared, and the pull
# request was opened later through `vcs-ops` alone. The clock stop and the
# CODE REVIEW move live in the closure step of the skill that normally opens the
# merge request, so with that context gone nothing asked for them — the task sat
# in IN PROGRESS with its clock running and no one could tell.
#
# The hook carries the obligation on the event instead. What is tested here is
# when it speaks (an open clock and a merge request that exists) and when it
# stays quiet, because a hook that fires on every `gh` call would be turned off.

echo ""
echo "── post-merge-request.sh (the board is not closed by the flow) ──"

MR_REPO="$WORK_DIR/mr-repo"
mkdir -p "$MR_REPO"
(
  cd "$MR_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
  git checkout -q -b feat/DE-810-thing
) >/dev/null 2>&1

MR_URL_GH="https://github.com/acme/repo/pull/12"

# The handlers that mount the hook, read from the generated hooks.json: the
# `if` rules below are what the harness spawns it on (DE-17064).
MR_HANDLERS="$(jq -c '[.hooks.PostToolUse[] | select(.matcher == "Bash")
  | .hooks[] | select(.command | contains("/post-merge-request.sh\""))]' "$HOOKS_JSON")"
MR_RULES="$(printf '%s' "$MR_HANDLERS" | jq -r '.[].if // ""')"

# Feeds a PostToolUse payload to the hook and prints what it tells the model:
# the `additionalContext` of the JSON object on its stdout, which is the channel
# the hooks reference gives this event (DE-17064). Nothing on stdout, nothing
# printed.
mr_hook() {
  local command="$1" response="$2" out
  out=$(jq -n --arg c "$command" --arg r "$response" --arg cwd "$MR_REPO" \
    '{tool_name: "Bash", tool_input: {command: $c}, tool_response: $r, cwd: $cwd}' \
    | bash "$PLUGIN_HOOKS/post-merge-request.sh" 2>/dev/null)
  [ -n "$out" ] || return 0
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty'
}

# The raw run: stdout and stderr to files, the hook's exit code returned.
mr_hook_raw() {
  local command="$1" response="$2"
  jq -n --arg c "$command" --arg r "$response" --arg cwd "$MR_REPO" \
    '{tool_name: "Bash", tool_input: {command: $c}, tool_response: $r, cwd: $cwd}' \
    | bash "$PLUGIN_HOOKS/post-merge-request.sh" >"$WORK_DIR/mr-stdout" 2>"$WORK_DIR/mr-stderr"
}

mr_clock() { (cd "$MR_REPO" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --json "$@" 2>/dev/null); }

# ── Quiet by default ──
assert_eq "a merge request that was not created says nothing" "" \
  "$(mr_hook 'gh pr create --fill' 'error: pull request create failed')"

# No task in progress here — a project that does not use the board must never
# see this hook at all.
assert_eq "no open clock, no reminder" "" \
  "$(mr_hook 'gh pr create --fill' "$MR_URL_GH")"
mr_hook_raw 'gh pr create --fill' "$MR_URL_GH"
assert_eq "and the quiet path exits 0" "0" "$?"
assert_eq "with an empty stdout" "" "$(cat "$WORK_DIR/mr-stdout")"

# ── With a task in progress ──
mr_clock --task DE-810 --start >/dev/null

# The internal filter stays, for a client that ignores `if`, and it is asserted
# where an unfiltered hook would speak: the URL is in the response and DE-810's
# clock is open, so only the scan keeps these two quiet.
assert_eq "a command that is not a merge request is ignored" "" \
  "$(mr_hook 'git status' "$MR_URL_GH")"
assert_eq "a quoted mention of the command is not the command" "" \
  "$(mr_hook 'git commit -m "explain how gh pr create works"' "$MR_URL_GH")"
mr_hook_raw 'git status' "$MR_URL_GH"
assert_eq "and the filtered call exits 0" "0" "$?"
assert_eq "with an empty stdout" "" "$(cat "$WORK_DIR/mr-stdout")"

MR_FIRED=$(mr_hook 'gh pr create --title "feat: thing [DE-810]" --base next' "$MR_URL_GH")

assert_contains "an open clock turns the merge request into a reminder" \
  "$MR_FIRED" "DE-810 is still IN PROGRESS"
assert_contains "which quotes the merge request it is about" "$MR_FIRED" "$MR_URL_GH"
assert_contains "and asks for the clock" "$MR_FIRED" "--task DE-810 --stop --json"
assert_contains "and for the board" "$MR_FIRED" "CODE REVIEW"
assert_contains "citing the contract that holds the call" \
  "$MR_FIRED" "reference/clickup-contract.md"

# The reminder is additionalContext with exit 0: on PostToolUse that is the
# channel the hooks reference gives a hook with something to tell the model,
# and it arrives as context rather than as a hook error. The merge request was
# created either way: the hook reports, it does not undo.
mr_hook_raw 'gh pr create --fill' "$MR_URL_GH"
assert_eq "it reports through additionalContext and exits 0" "0" "$?"
assert_eq "stdout is one JSON object" "1" "$(jq -s 'length' "$WORK_DIR/mr-stdout" 2>/dev/null)"
assert_eq "naming the event" "PostToolUse" \
  "$(jq -r '.hookSpecificOutput.hookEventName // empty' "$WORK_DIR/mr-stdout" 2>/dev/null)"
assert_eq "and nothing goes to stderr" "" "$(cat "$WORK_DIR/mr-stderr")"

assert_contains "glab is the same event" \
  "$(mr_hook 'glab mr create --fill' 'https://gitlab.com/g/p/-/merge_requests/7')" \
  "DE-810 is still IN PROGRESS"

# Every shape the scan accepts is one a rule spawns: the hook speaks on it with
# the clock open, and at least one `if` rule matches it. A form the hook acts
# on that no rule started would be a silent gap — the rules read `*gh pr
# *create*`, not `gh pr create*`, for `--repo=` before the subcommand and the
# `env` prefix.
for CMD in 'gh pr create --fill' 'gh pr --repo=acme/repo create --fill' \
           'env GH_REPO=acme/repo gh pr create --fill' 'glab mr --repo=g/p create --fill'; do
  assert_contains "the hook acts on: $CMD" \
    "$(mr_hook "$CMD" "$MR_URL_GH")" "DE-810 is still IN PROGRESS"
  assert_eq "and a rule spawns it: $CMD" "true" \
    "$(rules_match "$MR_RULES" "$CMD" && echo true || echo false)"
done

# The measurement belongs to whoever posts it. A hook that stopped the clock
# would close the interval in a session that may never reach the board.
assert_eq "the hook does not stop the clock" "true" \
  "$(mr_clock --task DE-810 --status | jq -r '.RUNNING')"
assert_contains "so the flow's own --stop still has something to post" \
  "$(mr_clock --task DE-810 --stop | jq -r '.COMMENT')" "Time in progress:"

# ── A fan-out shares the git directory ──
#
# Five tasks can be open at once (multi-sdd's cap). Naming the wrong one moves
# the wrong task, so the id has to come from the branch or the title, and when
# it comes from neither the hook reports them all rather than choosing.
mr_clock --task DE-811 --start >/dev/null
mr_clock --task DE-812 --start >/dev/null

(cd "$MR_REPO" && git checkout -q -b feat/DE-812-other) >/dev/null 2>&1
assert_contains "the branch picks the task out of several open clocks" \
  "$(mr_hook 'gh pr create --fill' "$MR_URL_GH")" "DE-812 is still IN PROGRESS"

# The id is matched between delimiters. DE-81 is a prefix of DE-811, and a
# reminder that closed the wrong task would be worse than no reminder.
mr_clock --task DE-81 --start >/dev/null
assert_contains "a shorter id is not matched inside a longer one" \
  "$(mr_hook 'gh pr create --title "feat: x [DE-811]" --fill' "$MR_URL_GH")" \
  "DE-811 is still IN PROGRESS"
(cd "$MR_REPO" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --task DE-81 --stop --json) >/dev/null 2>&1

(cd "$MR_REPO" && git checkout -q -b chore/nothing-in-the-name) >/dev/null 2>&1
MR_AMBIGUOUS=$(mr_hook 'gh pr create --fill' "$MR_URL_GH")
assert_contains "with nothing naming one, every open task is reported" \
  "$MR_AMBIGUOUS" "DE-811 DE-812"
assert_contains "and the hook refuses to choose" "$MR_AMBIGUOUS" "Do not guess"

# ── It ships mounted ──
#
# The hooks reach a project through the plugin, not through its settings.json:
# hooks.json is generated from the template's `hooks` block. A hook that is
# built but not mounted runs nowhere.
assert_eq "the hook ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/hooks/scripts/post-merge-request.sh" ] && echo true || echo false)"
# One rule per handler, and `gh pr create` shares no literal with `glab mr
# create` that a single rule could hold — so two handlers, one host each
# (DE-17064). Read from the generated hooks.json: a builder that dropped the
# key would fail here.
assert_eq "and is mounted as a PostToolUse hook on Bash, one handler per host" "2" \
  "$(printf '%s' "$MR_HANDLERS" | jq 'length')"
# The harness deduplicates identical hook commands, and nothing says `if` is
# part of the key: two handlers with one command string could collapse into one
# and the GitLab creation would never spawn the hook. The trailing argument
# (`gh` / `glab`), which the script never reads, keeps them distinct.
assert_eq "with two distinct command strings, so neither is deduplicated away" "2" \
  "$(printf '%s' "$MR_HANDLERS" | jq '[.[].command] | unique | length')"
assert_eq "each spawning on one host's merge-request creation" \
  "Bash(*gh pr *create*) Bash(*glab mr *create*)" \
  "$(printf '%s\n' "$MR_RULES" | LC_ALL=C sort | paste -sd' ' -)"

for CMD in 'git status' 'gh pr view 12 --json body' 'glab mr list'; do
  assert_eq "no rule spawns: $CMD" "false" \
    "$(rules_match "$MR_RULES" "$CMD" && echo true || echo false)"
done
for CMD in 'gh pr create --fill' 'gh pr --repo=acme/repo create --fill' \
           'env GH_REPO=acme/repo gh pr create --fill' \
           'glab mr create --fill' 'glab mr --repo=g/p create --fill'; do
  assert_eq "a rule spawns: $CMD" "true" \
    "$(rules_match "$MR_RULES" "$CMD" && echo true || echo false)"
done

# The skill that actually opens a merge request is the one place the obligation
# is certain to be loaded when it happens.
assert_contains "vcs-ops says the merge request does not end the task" \
  "$(cat "$REPO_ROOT/shared/skills/vcs-ops/SKILL.md")" "does not end the task"
assert_contains "citing the contract that holds both calls" \
  "$(cat "$REPO_ROOT/shared/skills/vcs-ops/SKILL.md")" "reference/clickup-contract.md"

# ═══════════════════════════════════════════════════════════════════════════════
# 12b. post-edit.sh: the formatter's report arrives as context (DE-17064)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Same channel as the merge-request hook: a formatter that fails on the file
# just written is work still to do on it, and the model learns it from
# `additionalContext`, not from a hook error.

echo ""
echo "── post-edit.sh (the report is context, not an error) ──"

# A project whose prettier fails, and one whose prettier passes. The fake
# binaries are what find_bin walks up to — nothing is installed here, and a
# passing eslint keeps a developer's own copy higher up out of the answer. The
# failing one prints 45 numbered lines before its marker: the report keeps the
# last 40, as the gate's MAX_OUTPUT_LINES does.
make_edit_project() {
  local dir="$1" exit_code="$2"
  mkdir -p "$dir/node_modules/.bin"
  printf 'const a = 1\n' > "$dir/a.ts"
  printf '#!/bin/sh\nseq 1 45 | sed "s/^/LINE_/"\necho PRETTIER_MARKER\nexit %s\n' "$exit_code" \
    > "$dir/node_modules/.bin/prettier"
  printf '#!/bin/sh\nexit 0\n' > "$dir/node_modules/.bin/eslint"
  chmod +x "$dir/node_modules/.bin/prettier" "$dir/node_modules/.bin/eslint"
}

# Feeds an Edit payload for the project's a.ts: stdout and stderr to files, the
# hook's exit code returned.
edit_hook_raw() {
  local dir="$1"
  jq -n --arg f "$dir/a.ts" '{tool_name: "Edit", tool_input: {file_path: $f}}' \
    | bash "$PLUGIN_HOOKS/post-edit.sh" >"$WORK_DIR/edit-stdout" 2>"$WORK_DIR/edit-stderr"
}

EDIT_RED="$WORK_DIR/post-edit-red"
make_edit_project "$EDIT_RED" 1
edit_hook_raw "$EDIT_RED"
assert_eq "a failing formatter still exits 0" "0" "$?"
assert_eq "and reports through one JSON object" "1" \
  "$(jq -s 'length' "$WORK_DIR/edit-stdout" 2>/dev/null)"
assert_eq "naming the event" "PostToolUse" \
  "$(jq -r '.hookSpecificOutput.hookEventName // empty' "$WORK_DIR/edit-stdout" 2>/dev/null)"
EDIT_CONTEXT="$(jq -r '.hookSpecificOutput.additionalContext // empty' "$WORK_DIR/edit-stdout" 2>/dev/null)"
assert_contains "whose context says what failed" "$EDIT_CONTEXT" "prettier failed on"
assert_contains "with the tool's own output" "$EDIT_CONTEXT" "PRETTIER_MARKER"
assert_eq "and nothing on stderr" "" "$(cat "$WORK_DIR/edit-stderr")"
# 46 lines of output, 40 kept: LINE_7 is the first that survives the tail.
assert_contains "the tail of the output is kept" "$EDIT_CONTEXT" "LINE_7"
assert_eq "and the head is not" "false" \
  "$(printf '%s\n' "$EDIT_CONTEXT" | grep -qx 'LINE_6' && echo true || echo false)"

EDIT_GREEN="$WORK_DIR/post-edit-green"
make_edit_project "$EDIT_GREEN" 0
edit_hook_raw "$EDIT_GREEN"
assert_eq "a passing formatter exits 0" "0" "$?"
assert_eq "and says nothing" "" "$(cat "$WORK_DIR/edit-stdout")"

# ── No hook exits 2 ──
#
# A hook that reports uses additionalContext; a hook that refuses uses the
# PreToolUse decision object. A comment may still name the old channel, code
# may not: the grep reads each line up to its first `#`.
assert_eq "no hook script exits 2 in code" "" \
  "$(grep -lE '^[^#]*(^|[^[:alnum:]_])exit[[:space:]]+2([^[:digit:]]|$)' "$PLUGIN_HOOKS"/*.sh \
     | sed "s|^$REPO_ROOT/||")"

# ═══════════════════════════════════════════════════════════════════════════════
# 12c. notify.sh: the developer is called back with the task id (DE-17077)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Claude Code's own notification says "Claude needs your permission", not for
# which task. The hook adds one that names it — and only when a task of this
# plugin is in play here (an open or just-stopped clock): a hook that speaks on
# every prompt would be switched off within the week. The notifiers and `uname`
# are stubs, so both delivery paths are asserted on any host.

echo ""
echo "── notify.sh (a permission prompt names its task) ──"

NOTIFY_BIN="$WORK_DIR/notify-bin"
NOTIFY_CALLS="$WORK_DIR/notify-calls"
export NOTIFY_CALLS
mkdir -p "$NOTIFY_BIN"
cat > "$NOTIFY_BIN/uname" <<'STUB'
#!/bin/sh
printf '%s\n' "${STUB_OS:-Linux}"
STUB
# One line per call: the notifier's name, then each argument after a tab.
for NOTIFIER in osascript notify-send; do
  cat > "$NOTIFY_BIN/$NOTIFIER" <<'STUB'
#!/bin/sh
{ printf '%s' "$(basename "$0")"; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$NOTIFY_CALLS"
exit "${STUB_NOTIFY_EXIT:-0}"
STUB
done
chmod +x "$NOTIFY_BIN"/*

NT_REPO="$WORK_DIR/notify-repo"
mkdir -p "$NT_REPO"
(
  cd "$NT_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
  git checkout -q -b chore/no-task
) >/dev/null 2>&1

NT_MESSAGE="Claude needs your permission to use Bash"

# Feeds a Notification payload to the hook with the stubs first on PATH: stdout
# and stderr to files, the calls to $NOTIFY_CALLS, the hook's exit code returned.
notify_hook_raw() {
  local type="$1" message="$2" cwd="${3:-$NT_REPO}"
  : > "$NOTIFY_CALLS"
  jq -n --arg t "$type" --arg m "$message" --arg cwd "$cwd" \
    '{hook_event_name: "Notification", notification_type: $t, message: $m, cwd: $cwd}' \
    | PATH="$NOTIFY_BIN:$PATH" bash "$PLUGIN_HOOKS/notify.sh" \
      >"$WORK_DIR/notify-stdout" 2>"$WORK_DIR/notify-stderr"
}
notify_count() { grep -c . "$NOTIFY_CALLS" 2>/dev/null || true; }
# The title is the first argument of either notifier: notify-send's first,
# osascript's first after the script.
notify_title() { awk -F'\t' '{ print ($1 == "osascript") ? $(NF-1) : $2 }' "$NOTIFY_CALLS"; }
nt_clock() { (cd "${NT_CLOCK_CWD:-$NT_REPO}" && bash "$PLUGIN_SCRIPTS/task-clock.sh" --json "$@" 2>/dev/null); }

# ── Test 2 (REQ-2): nothing in play, nothing said ──
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "no task branch and no clock: exit 0" "0" "$?"
assert_eq "and no notifier is invoked" "0" "$(notify_count)"
assert_eq "with an empty stdout" "" "$(cat "$WORK_DIR/notify-stdout")"

(cd "$NT_REPO" && git checkout -q -b feat/DE-900_thing) >/dev/null 2>&1
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "a task branch with no clock is not a signal" "0" "$(notify_count)"

# ── Test 1 (REQ-1): a permission prompt with a task in play ──
nt_clock --task DE-900 --start >/dev/null

STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "an open clock makes a permission prompt one notification" "1" "$(notify_count)"
assert_eq "through notify-send on Linux" "notify-send" "$(cut -f1 "$NOTIFY_CALLS")"
assert_eq "titled with the task" "dev-setup · DE-900" "$(cut -f2 "$NOTIFY_CALLS")"
assert_eq "with the prompt's message as the body" "$NT_MESSAGE" "$(cut -f3 "$NOTIFY_CALLS")"
assert_eq "and stdout stays empty" "" "$(cat "$WORK_DIR/notify-stdout")"

STUB_OS=Darwin notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "on Darwin it is one osascript call" "osascript" \
  "$(cut -f1 "$NOTIFY_CALLS")$( [ "$(notify_count)" = 1 ] || echo ' (not one call)')"
assert_eq "whose argv carries the title as its own argument" "dev-setup · DE-900" \
  "$(awk -F'\t' '{ print $(NF-1) }' "$NOTIFY_CALLS")"
assert_eq "and the body as the next one" "$NT_MESSAGE" \
  "$(awk -F'\t' '{ print $NF }' "$NOTIFY_CALLS")"
assert_eq "never interpolated into the script" "false" \
  "$(awk -F'\t' '{ for (i = 2; i < NF - 1; i++) print $i }' "$NOTIFY_CALLS" \
     | grep -q 'DE-900' && echo true || echo false)"

NT_QUOTED="Claude needs \"your\" permission to use Bash's tool"
STUB_OS=Darwin notify_hook_raw permission_prompt "$NT_QUOTED"
assert_eq "a message with quotes arrives verbatim in argv" "$NT_QUOTED" \
  "$(awk -F'\t' '{ print $NF }' "$NOTIFY_CALLS")"

# ── Test 2 (REQ-2): every other notification type is left alone ──
for NT_TYPE in idle_prompt auth_success agent_needs_input agent_completed; do
  STUB_OS=Linux notify_hook_raw "$NT_TYPE" "$NT_MESSAGE"
  assert_eq "$NT_TYPE says nothing, even with a task open" "0:" \
    "$(notify_count):$(cat "$WORK_DIR/notify-stdout")"
done

# ── Test 3 (REQ-3): it fails open ──
NOJQ_BIN="$WORK_DIR/notify-nojq-bin"
mkdir -p "$NOJQ_BIN"
for NT_TOOL in bash git sed grep cat dirname head tr; do
  ln -sf "$(command -v "$NT_TOOL")" "$NOJQ_BIN/$NT_TOOL"
done
ln -sf "$NOTIFY_BIN/uname" "$NOJQ_BIN/uname"
ln -sf "$NOTIFY_BIN/notify-send" "$NOJQ_BIN/notify-send"
NT_PAYLOAD=$(jq -n --arg cwd "$NT_REPO" --arg m "$NT_MESSAGE" \
  '{hook_event_name: "Notification", notification_type: "permission_prompt", message: $m, cwd: $cwd}')
: > "$NOTIFY_CALLS"
printf '%s' "$NT_PAYLOAD" | STUB_OS=Linux PATH="$NOJQ_BIN" "$NOJQ_BIN/bash" "$PLUGIN_HOOKS/notify.sh" \
  >"$WORK_DIR/notify-stdout" 2>/dev/null
assert_eq "without jq it exits 0" "0" "$?"
assert_eq "with an empty stdout and no call" "0:" \
  "$(notify_count):$(cat "$WORK_DIR/notify-stdout")"

NT_LONELY="$WORK_DIR/notify-lonely/hooks"
mkdir -p "$NT_LONELY"
cp "$PLUGIN_HOOKS/notify.sh" "$NT_LONELY/notify.sh"
: > "$NOTIFY_CALLS"
printf '%s' "$NT_PAYLOAD" | STUB_OS=Linux PATH="$NOTIFY_BIN:$PATH" env -u CLAUDE_PLUGIN_ROOT \
  bash "$NT_LONELY/notify.sh" >"$WORK_DIR/notify-stdout" 2>/dev/null
assert_eq "without the plugin scripts it exits 0" "0" "$?"
assert_eq "and invokes nothing" "0:" "$(notify_count):$(cat "$WORK_DIR/notify-stdout")"

STUB_OS=Plan9 notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "an unsupported OS exits 0" "0" "$?"
assert_eq "and invokes nothing" "0:" "$(notify_count):$(cat "$WORK_DIR/notify-stdout")"

mkdir -p "$WORK_DIR/notify-not-a-repo"
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$WORK_DIR/notify-not-a-repo"
assert_eq "a cwd outside a repository exits 0" "0" "$?"
assert_eq "and invokes nothing" "0" "$(notify_count)"

STUB_OS=Linux STUB_NOTIFY_EXIT=1 notify_hook_raw permission_prompt "$NT_MESSAGE"
assert_eq "a failing notifier still exits 0" "0" "$?"
assert_eq "with an empty stdout" "" "$(cat "$WORK_DIR/notify-stdout")"
nt_clock --task DE-900 --stop >/dev/null

# ── Test 4 (REQ-4): the launcher's order, replayed on its checkout ──
#
# An autonomous run is launched from the developer checkout, on a branch with
# no task id. ready-for-mr asks for the merge request with the clock still
# open; failed stops the clock and then asks for the BLOCKED move.
NT4_REPO="$WORK_DIR/notify-launcher-repo"
mkdir -p "$NT4_REPO"
(
  cd "$NT4_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
  git checkout -q -b next
) >/dev/null 2>&1

NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-901 --start >/dev/null
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$NT4_REPO"
assert_eq "ready-for-mr: the open clock names the run from a branch with no id" \
  "1:dev-setup · DE-901" "$(notify_count):$(notify_title)"

NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-902 --start >/dev/null
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$NT4_REPO"
assert_eq "two runs in flight, nothing narrowing: both are named" \
  "1:dev-setup · DE-901 DE-902" "$(notify_count):$(notify_title)"
assert_eq "and the hook stops neither clock" "true true" \
  "$(NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-901 --status | jq -r '.RUNNING') $(NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-902 --status | jq -r '.RUNNING')"

(cd "$NT4_REPO" && git checkout -q -b feat/DE-901_thing) >/dev/null 2>&1
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$NT4_REPO"
assert_eq "a branch naming one of them narrows to it" \
  "1:dev-setup · DE-901" "$(notify_count):$(notify_title)"
(cd "$NT4_REPO" && git checkout -q next) >/dev/null 2>&1

NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-901 --stop >/dev/null
NT_CLOCK_CWD="$NT4_REPO" nt_clock --task DE-902 --stop >/dev/null
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$NT4_REPO"
assert_eq "failed: the BLOCKED prompt after --stop still names them" \
  "1:dev-setup · DE-901 DE-902" "$(notify_count):$(notify_title)"

NT4_CLOCKS="$NT4_REPO/.git/dev-setup/task-clock"
NT4_NOW=$(date +%s)
for NT_TASK in DE-901 DE-902; do
  {
    printf 'start\t%s\t%s\n' "$((NT4_NOW - 1200))" "2026-10-16 09:00"
    printf 'stop\t%s\t%s\t%s\n' "$((NT4_NOW - 600))" "2026-10-16 09:10" "10"
  } > "$NT4_CLOCKS/$NT_TASK.log"
done
STUB_OS=Linux notify_hook_raw permission_prompt "$NT_MESSAGE" "$NT4_REPO"
assert_eq "a stop 600 s old is no longer in play: exit 0" "0" "$?"
assert_eq "no call, empty stdout" "0:" "$(notify_count):$(cat "$WORK_DIR/notify-stdout")"

# The two halves rest on the order of run-outcomes.md: ready-for-mr opens the
# merge request before it stops the clock, failed stops it before the BLOCKED
# move. Reordering either changes which half the clocks name, silently.
NT_OUTCOMES="$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md"
NT_READY=$(awk '/^## ready-for-mr/ { p = 1; next } /^## / { p = 0 } p' "$NT_OUTCOMES")
NT_VCS_LINE=$(printf '%s\n' "$NT_READY" | grep -n 'Then invoke `vcs-ops`' | head -1 | cut -d: -f1)
NT_STOP_LINE=$(printf '%s\n' "$NT_READY" | grep -n -- '--task <taskId> --stop' | head -1 | cut -d: -f1)
assert_eq "ready-for-mr invokes vcs-ops before it stops the clock" "true" \
  "$([ -n "$NT_VCS_LINE" ] && [ -n "$NT_STOP_LINE" ] && [ "$NT_VCS_LINE" -lt "$NT_STOP_LINE" ] \
     && echo true || echo false)"
assert_eq "failed stops the clock before the BLOCKED move" "true" \
  "$(awk '/^## failed/ { p = 1; next } /^## / { p = 0 } p' "$NT_OUTCOMES" \
     | grep -qE '^4\. Stop the clock, then move the task to `BLOCKED`' && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# 12d. session-title.sh: the session is named after its task (DE-17077)
# ═══════════════════════════════════════════════════════════════════════════════
#
# `claude --resume` lists sessions by their first prompt. The hook answers
# `sessionTitle: "<TASK_ID> <slug>"` from the branch at SessionStart, and from
# the launch prompt of a single-task flow at UserPromptSubmit — and never over a
# title the developer chose.

echo ""
echo "── session-title.sh (the session carries the task's name) ──"

ST_REPO="$WORK_DIR/title-repo"
mkdir -p "$ST_REPO"
(
  cd "$ST_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
  git checkout -q -b feat/DE-123_add-user-auth
) >/dev/null 2>&1

# Feeds a payload to the hook: stdout and stderr to files, exit code returned.
# The payload is built by the caller, as jq arguments for the fields it sets.
title_hook_raw() {
  local filter="$1"; shift
  jq -n --arg cwd "${ST_CWD:-$ST_REPO}" "$@" "$filter" \
    | bash "$PLUGIN_HOOKS/session-title.sh" >"$WORK_DIR/title-stdout" 2>"$WORK_DIR/title-stderr"
}
title_start() {
  title_hook_raw '{hook_event_name: "SessionStart", source: $src, session_title: $t, cwd: $cwd}' \
    --arg src "${1:-startup}" --arg t "${2:-}"
}
title_prompt() {
  title_hook_raw '{hook_event_name: "UserPromptSubmit", prompt: $p, session_title: $t, cwd: $cwd}' \
    --arg p "$1" --arg t "${2:-}"
}
title_of() { jq -r '.hookSpecificOutput.sessionTitle // empty' "$WORK_DIR/title-stdout" 2>/dev/null; }
title_event() { jq -r '.hookSpecificOutput.hookEventName // empty' "$WORK_DIR/title-stdout" 2>/dev/null; }
st_checkout() { (cd "$ST_REPO" && git checkout -q -B "$1") >/dev/null 2>&1; }

# ── Test 5 (REQ-5): the title comes from the branch ──
title_start startup
assert_eq "SessionStart on a task branch exits 0" "0" "$?"
assert_eq "with one JSON object on stdout" "1" "$(jq -s 'length' "$WORK_DIR/title-stdout" 2>/dev/null)"
assert_eq "naming the event" "SessionStart" "$(title_event)"
assert_eq "and the task with its slug" "DE-123 add-user-auth" "$(title_of)"

title_start resume
assert_eq "a resumed session gets the same title" "DE-123 add-user-auth" "$(title_of)"

st_checkout 'feat(auth)/DE-123_add-user-auth'
title_start startup
assert_eq "a branch with a context gives the same title" "DE-123 add-user-auth" "$(title_of)"

st_checkout feat/DE-124-add-x
title_start startup
assert_eq "the legacy dash delimiter gives the slug after it" "DE-124 add-x" "$(title_of)"
st_checkout feat/DE-123_add-user-auth

# ── Test 6 (REQ-6): a title the developer chose is kept ──
title_start startup "my refactor"
assert_eq "a title of the developer's own is never replaced" "" "$(cat "$WORK_DIR/title-stdout")"
title_start startup "DE-99 old-thing"
assert_eq "an earlier task title is the hook's own and is replaced" "DE-123 add-user-auth" "$(title_of)"
title_start startup "DE-123 add-user-auth"
assert_eq "a title already right is left alone" "" "$(cat "$WORK_DIR/title-stdout")"

# ── Test 7 (REQ-7): the launch prompt names a session opened on next ──
(cd "$ST_REPO" && git branch -q feat/DE-125_fix-login && git checkout -q -B next) >/dev/null 2>&1
title_prompt "/dev-setup:sdd DE-125"
assert_eq "/dev-setup:sdd <id> titles the session from its local branch" "DE-125 fix-login" "$(title_of)"
assert_eq "naming the event" "UserPromptSubmit" "$(title_event)"
title_prompt "/dev-setup:quick DE-126"
assert_eq "with no branch for the id, the title is the id" "DE-126" "$(title_of)"
title_prompt "/dev-setup:auto-sdd DE-125 --stop review"
assert_eq "auto-sdd launches one task too" "DE-125 fix-login" "$(title_of)"
for ST_PROMPT in "/dev-setup:multi-sdd DE-1 DE-2" "explain DE-125" "/dev-setup:sdd" \
                 "/dev-setup:sdd DE-125x"; do
  title_prompt "$ST_PROMPT"
  assert_eq "silent on: $ST_PROMPT" "0:" "$?:$(cat "$WORK_DIR/title-stdout")"
done
title_prompt "/dev-setup:sdd DE-125" "my refactor"
assert_eq "the launch prompt keeps a title of the developer's own" "" "$(cat "$WORK_DIR/title-stdout")"
title_prompt "/dev-setup:sdd DE-125" "DE-125 fix-login"
assert_eq "and says nothing when the title is already right" "" "$(cat "$WORK_DIR/title-stdout")"

# ── Test 8 (REQ-8): silent off a task branch, open when something is missing ──
st_checkout chore/no-task
title_start startup
assert_eq "a branch with no task id says nothing" "0:" "$?:$(cat "$WORK_DIR/title-stdout")"
title_hook_raw '{hook_event_name: "SessionStart", source: "compact", cwd: $cwd}'
assert_eq "and so does a compact SessionStart" "" "$(cat "$WORK_DIR/title-stdout")"
st_checkout feat/DE-123_add-user-auth

ST_PAYLOAD=$(jq -n --arg cwd "$ST_REPO" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}')
printf '%s' "$ST_PAYLOAD" | PATH="$NOJQ_BIN" "$NOJQ_BIN/bash" "$PLUGIN_HOOKS/session-title.sh" \
  >"$WORK_DIR/title-stdout" 2>/dev/null
assert_eq "without jq it exits 0 with an empty stdout" "0:" "$?:$(cat "$WORK_DIR/title-stdout")"

mkdir -p "$WORK_DIR/title-not-a-repo"
ST_CWD="$WORK_DIR/title-not-a-repo" title_start startup
assert_eq "a cwd outside a repository exits 0 with an empty stdout" "0:" \
  "$?:$(cat "$WORK_DIR/title-stdout")"

ST_LONELY="$WORK_DIR/title-lonely/hooks"
mkdir -p "$ST_LONELY"
cp "$PLUGIN_HOOKS/session-title.sh" "$ST_LONELY/session-title.sh"
printf '%s' "$ST_PAYLOAD" | env -u CLAUDE_PLUGIN_ROOT bash "$ST_LONELY/session-title.sh" \
  >"$WORK_DIR/title-stdout" 2>/dev/null
assert_eq "without the plugin scripts it exits 0 with an empty stdout" "0:" \
  "$?:$(cat "$WORK_DIR/title-stdout")"

# ── Test 9 (REQ-9): both hooks ship mounted ──
#
# Read from the generated hooks.json: a hook that is built but not mounted runs
# nowhere, and one mounted on the wrong matcher speaks on the wrong event.
assert_eq "notify.sh is mounted on Notification, matcher permission_prompt" "permission_prompt" \
  "$(jq -r '[.hooks.Notification[]? | select(any(.hooks[]; .command | endswith("/notify.sh\"")))
            | .matcher] | join(",")' "$HOOKS_JSON")"
assert_eq "session-title.sh is mounted on SessionStart startup|resume" "startup|resume" \
  "$(jq -r '[.hooks.SessionStart[]? | select(any(.hooks[]; .command | endswith("/session-title.sh\"")))
            | .matcher] | join(",")' "$HOOKS_JSON")"
assert_eq "and the compact handler is still on-compact.sh, alone" "1" \
  "$(jq '[.hooks.SessionStart[]? | select(.matcher == "compact")
          | select(any(.hooks[]; .command | endswith("/on-compact.sh\"")))] | length' "$HOOKS_JSON")"
assert_eq "session-title.sh is mounted on UserPromptSubmit" "1" \
  "$(jq '[.hooks.UserPromptSubmit[]? | .hooks[] | select(.command | endswith("/session-title.sh\""))]
         | length' "$HOOKS_JSON")"
for ST_HOOK in notify.sh session-title.sh; do
  assert_eq "$ST_HOOK ships in the built plugin" "true" \
    "$([ -x "$REPO_ROOT/dist/dev-setup/hooks/scripts/$ST_HOOK" ] && echo true || echo false)"
  assert_eq "and the manifest lists it" "true" \
    "$(jq -e --arg h "$ST_HOOK" '.hooks | index($h) != null' \
         "$REPO_ROOT/templates/dev-setup/manifest.json" >/dev/null && echo true || echo false)"
done

# ═══════════════════════════════════════════════════════════════════════════════
# 13. review-package.sh: the diff verify and review read, built once (DE-17080)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The closure used to build the diff twice — once per agent. The package is one
# file both agents read. Three properties matter: it holds the working tree
# (staged and unstaged, because nothing is committed at closure time), EMPTY is
# decided by the diff and never by the commits, and an invalid range fails
# without leaving a package behind.

echo ""
echo "── review-package.sh (the review diff, built once) ──"

RP_ERR_FILE="$WORK_DIR/review-package.stderr"
# Runs the script in a directory; sets RP_OUT, RP_ERR and RP_EXIT.
rp_run() {
  local dir="$1"
  shift
  RP_OUT=$(cd "$dir" && bash "$PLUGIN_SCRIPTS/review-package.sh" "$@" 2>"$RP_ERR_FILE")
  RP_EXIT=$?
  RP_ERR=$(cat "$RP_ERR_FILE" 2>/dev/null)
}
rp_key() { printf '%s' "$RP_OUT" | jq -r --arg k "$1" '.[$k]'; }
# The physical path of a directory, or nothing: /tmp is a symlink on macOS.
phys_dir() { (cd "$1" 2>/dev/null && pwd -P); }

RP_REPO="$WORK_DIR/review-package-repo"
mkdir -p "$RP_REPO"
(
  cd "$RP_REPO" || exit 1
  git_init .
  git symbolic-ref HEAD refs/heads/main
  git config user.email "test@example.com"
  git config user.name "Test"

  echo "base" > base.txt
  for i in $(seq -w 1 30); do echo "row-$i"; done > data.txt
  git add . && git commit --quiet -m "chore: base"

  git checkout --quiet -b next
  for i in 1 2 3; do
    echo "next change $i" > "next-$i.txt"
    git add . && git commit --quiet -m "feat: next change $i"
  done

  git checkout --quiet -b 'feat(x)/DE-999_work'
  sed 's/^row-15$/row-15 changed by the branch/' data.txt > data.tmp && mv data.tmp data.txt
  git add data.txt && git commit --quiet -m "feat: branch work on data"

  # The closure's own state: one new file staged, one tracked file edited after
  # the staging (what simplify leaves behind), nothing of it committed.
  echo "staged content" > staged.txt
  git add staged.txt
  echo "appended-unstaged" >> base.txt
) >/dev/null 2>&1

RP_BASE=$(cd "$RP_REPO" && git merge-base HEAD next)
RP_STATUS_BEFORE=$(cd "$RP_REPO" && git status --porcelain)

# ── Test 1 (REQ-1): what the package holds ──
rp_run "$RP_REPO" --base "$RP_BASE" --json
RP_JSON_1="$RP_OUT"
RP_PKG_1=$(rp_key PACKAGE)
assert_eq "review-package: a branch with work exits 0" "0" "$RP_EXIT"
assert_eq "and is not empty" "false" "$(rp_key EMPTY)"
assert_eq "the package lives under the common git directory" \
  "$(phys_dir "$RP_REPO/.git")/dev-setup/review-package" \
  "$(phys_dir "$(dirname "$RP_PKG_1")")"
assert_eq "and is named after the slugified branch" "true" \
  "$(basename "$RP_PKG_1" | grep -q '^feat-x-de-999-work' && echo true || echo false)"
assert_eq "the script stages nothing" "$RP_STATUS_BEFORE" \
  "$(cd "$RP_REPO" && git status --porcelain)"

RP_CONTENT=$(cat "$RP_PKG_1" 2>/dev/null)
assert_contains "the package lists the branch's commit" "$RP_CONTENT" "feat: branch work on data"
assert_eq "and none of the base branch's" "false" \
  "$(printf '%s' "$RP_CONTENT" | grep -q 'next change' && echo true || echo false)"
assert_contains "it carries the stat" "$RP_CONTENT" "3 files changed"
assert_contains "it carries the staged new file" "$RP_CONTENT" "+staged content"
assert_contains "and the unstaged edit to a tracked file" "$RP_CONTENT" "+appended-unstaged"
assert_eq "ten lines of context reach row 5" "true" \
  "$(printf '%s\n' "$RP_CONTENT" | grep -qx ' row-05' && echo true || echo false)"
assert_eq "and stop before row 4" "false" \
  "$(printf '%s\n' "$RP_CONTENT" | grep -qx ' row-04' && echo true || echo false)"
assert_eq "COMMITS counts the branch's own commits" "1" "$(rp_key COMMITS)"
assert_eq "FILES counts the changed files" "3" "$(rp_key FILES)"
assert_eq "CHANGED_LINES is insertions plus deletions" \
  "$(cd "$RP_REPO" && git diff --numstat "$RP_BASE" | awk '{ s += $1 + $2 } END { print s }')" \
  "$(rp_key CHANGED_LINES)"
assert_eq "a few lines in three files are small" "small" "$(rp_key SIZE)"

# ── Test 5 (REQ-1): the script contract ──
assert_eq "the keys are exactly the documented ones" \
  "PACKAGE,MERGE_BASE,EMPTY,COMMITS,FILES,CHANGED_LINES,SIZE" \
  "$(printf '%s' "$RP_JSON_1" | jq -r 'keys_unsorted | join(",")')"
assert_eq "and every value is a string" "string" \
  "$(printf '%s' "$RP_JSON_1" | jq -r '[.[] | type] | unique | join(",")')"
assert_eq "MERGE_BASE is the resolved --base" \
  "$(cd "$RP_REPO" && git rev-parse "$RP_BASE")" \
  "$(printf '%s' "$RP_JSON_1" | jq -r '.MERGE_BASE')"

# A second run on the same branch overwrites the package with what is there now.
(cd "$RP_REPO" && sed 's/^row-20$/row-20 first edit/' data.txt > data.tmp && mv data.tmp data.txt)
rp_run "$RP_REPO" --base "$RP_BASE" --json
(cd "$RP_REPO" && sed 's/^row-20 first edit$/row-20 second edit/' data.txt > data.tmp && mv data.tmp data.txt)
rp_run "$RP_REPO" --base "$RP_BASE" --json
assert_eq "a rerun returns the same package" "$RP_PKG_1" "$(rp_key PACKAGE)"
RP_CONTENT=$(cat "$RP_PKG_1" 2>/dev/null)
assert_contains "and the package holds the current change" "$RP_CONTENT" "+row-20 second edit"
assert_eq "not the one before it" "false" \
  "$(printf '%s' "$RP_CONTENT" | grep -q 'row-20 first edit' && echo true || echo false)"

# Two branches — two worktrees — get two packages.
(cd "$RP_REPO" && git checkout --quiet -b 'feat(y)/DE-998_other') >/dev/null 2>&1
rp_run "$RP_REPO" --base "$RP_BASE" --json
RP_PKG_OTHER=$(rp_key PACKAGE)
assert_eq "another branch gets another package" "true" \
  "$([ -n "$RP_PKG_OTHER" ] && [ "$RP_PKG_OTHER" != "$RP_PKG_1" ] && echo true || echo false)"
assert_eq "and the first branch's package stays" "true" \
  "$([ -f "$RP_PKG_1" ] && echo true || echo false)"

# ── Test 2 (REQ-2): no change, no package ──
(
  cd "$RP_REPO" || exit 1
  git checkout --quiet 'feat(x)/DE-999_work'
  git add -A && git commit --quiet -m "feat: the rest of the work"
) >/dev/null 2>&1
rp_run "$RP_REPO" --base HEAD --json
assert_eq "a clean tree against HEAD exits 0" "0" "$RP_EXIT"
assert_eq "and is empty" "true" "$(rp_key EMPTY)"
assert_eq "with no package" "" "$(rp_key PACKAGE)"
assert_eq "no size" "" "$(rp_key SIZE)"
assert_eq "no file" "0" "$(rp_key FILES)"
assert_eq "and no changed line" "0" "$(rp_key CHANGED_LINES)"
assert_eq "the stale package of the branch is removed" "false" \
  "$([ -e "$RP_PKG_1" ] && echo true || echo false)"
assert_eq "another branch's package is left alone" "true" \
  "$([ -f "$RP_PKG_OTHER" ] && echo true || echo false)"

# ── Test 2b (REQ-2): staged work and no commit is the closure's state ──
(
  cd "$RP_REPO" || exit 1
  git checkout --quiet -b 'feat/DE-997_staged'
  echo "only staged" > only-staged.txt
  git add only-staged.txt
) >/dev/null 2>&1
rp_run "$RP_REPO" --base HEAD --json
assert_eq "staged work with no commit is not empty" "false" "$(rp_key EMPTY)"
assert_eq "COMMITS is reported, not used to decide" "0" "$(rp_key COMMITS)"
assert_eq "the staged file is counted" "1" "$(rp_key FILES)"
assert_contains "and is in the package" "$(cat "$(rp_key PACKAGE)" 2>/dev/null)" "+only staged"

# ── Test 2c (REQ-2): a commit and its revert change nothing ──
(
  cd "$RP_REPO" || exit 1
  git commit --quiet -m "feat: staged work"
  git checkout --quiet -b 'feat/DE-996_revert'
) >/dev/null 2>&1
RP_BEFORE=$(cd "$RP_REPO" && git rev-parse HEAD)
(
  cd "$RP_REPO" || exit 1
  echo "short-lived" > short-lived.txt
  git add short-lived.txt && git commit --quiet -m "feat: short-lived"
  git revert --no-edit HEAD
) >/dev/null 2>&1
rp_run "$RP_REPO" --base "$RP_BEFORE" --json
assert_eq "commits whose sum is nothing are empty" "true" "$(rp_key EMPTY)"
assert_eq "and leave no package file" "" \
  "$(find "$(cd "$RP_REPO" && phys_dir "$(git rev-parse --git-common-dir)")/dev-setup/review-package" \
       -name 'feat-de-996-revert*' 2>/dev/null)"

# ── Test 3 (REQ-3): an invalid range fails without a package ──
RP_PKG_DIR="$(phys_dir "$RP_REPO/.git")/dev-setup/review-package"
RP_LISTING_BEFORE=$(ls -1 "$RP_PKG_DIR" 2>/dev/null)
(cd "$RP_REPO" && echo "pending" > pending.txt && git add pending.txt) >/dev/null 2>&1

rp_run "$RP_REPO" --base does-not-exist --json
assert_eq "an unknown --base exits non-zero" "true" "$([ "$RP_EXIT" -ne 0 ] && echo true || echo false)"
assert_eq "and prints nothing on stdout" "" "$RP_OUT"
assert_contains "and names the ref" "$RP_ERR" "does-not-exist"

rp_run "$RP_REPO" --json
assert_eq "a missing --base exits non-zero" "true" "$([ "$RP_EXIT" -ne 0 ] && echo true || echo false)"
assert_eq "and prints nothing on stdout" "" "$RP_OUT"
assert_contains "and names --base" "$RP_ERR" "--base"

rp_run "$RP_REPO" --base HEAD --bogus
assert_eq "an unknown argument exits non-zero" "true" "$([ "$RP_EXIT" -ne 0 ] && echo true || echo false)"
assert_eq "and prints nothing on stdout" "" "$RP_OUT"
assert_contains "and names it" "$RP_ERR" "--bogus"

RP_NOT_A_REPO="$WORK_DIR/review-package-not-a-repo"
mkdir -p "$RP_NOT_A_REPO"
rp_run "$RP_NOT_A_REPO" --base HEAD --json
assert_eq "a run outside a repository exits non-zero" "true" "$([ "$RP_EXIT" -ne 0 ] && echo true || echo false)"
assert_eq "and prints nothing on stdout" "" "$RP_OUT"
assert_contains "and names git" "$RP_ERR" "git"

assert_eq "no invalid run wrote a package" "$RP_LISTING_BEFORE" "$(ls -1 "$RP_PKG_DIR" 2>/dev/null)"

# ── Test 4 (REQ-4): the size thresholds ──
RP_SIZE_REPO="$WORK_DIR/review-package-size"
mkdir -p "$RP_SIZE_REPO"
(
  cd "$RP_SIZE_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "base" > base.txt
  git add . && git commit --quiet -m "chore: base"
) >/dev/null 2>&1

# Stages a fresh change of $1 lines in one file, or one line in each of $2 files.
rp_size_of() {
  (
    cd "$RP_SIZE_REPO" || exit 1
    git reset --quiet --hard HEAD
    if [ "$1" -gt 0 ]; then
      seq 1 "$1" > lines.txt
    else
      for i in $(seq 1 "$2"); do echo "one" > "file-$i.txt"; done
    fi
    git add -A
  ) >/dev/null 2>&1
  rp_run "$RP_SIZE_REPO" --base HEAD --json
  rp_key SIZE
}
assert_eq "300 changed lines are small" "small" "$(rp_size_of 300 0)"
assert_eq "301 changed lines are large" "large" "$(rp_size_of 301 0)"
assert_eq "10 files are small" "small" "$(rp_size_of 0 10)"
assert_eq "11 files are large" "large" "$(rp_size_of 0 11)"
assert_contains "the line threshold is a named constant" \
  "$(cat "$PLUGIN_SCRIPTS/review-package.sh")" "LARGE_CHANGED_LINES=300"
assert_contains "the file threshold is a named constant" \
  "$(cat "$PLUGIN_SCRIPTS/review-package.sh")" "LARGE_FILES=10"

# ── Test 6 (REQ-12): it ships ──
assert_eq "the manifest lists review-package.sh" "true" \
  "$(jq -e '.plugin_scripts | index("review-package.sh") != null' \
       "$REPO_ROOT/templates/dev-setup/manifest.json" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "review-package.sh ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/review-package.sh" ] && echo true || echo false)"
assert_eq "the AGENTS.md script table names it with its keys" "true" \
  "$(grep -E '^\| `review-package\.sh' "$REPO_ROOT/AGENTS.md" | grep -q 'CHANGED_LINES' && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# 14. verify and review: one package, short answers (DE-17080)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The agents read the package and cannot rebuild the diff: the proof is that
# they have no Bash, not a sentence asking them not to. Both answer short — the
# problems, never the list of what is fine.

echo ""
echo "── verify and review read one package and answer short ──"

AGENTS_SRC="$REPO_ROOT/templates/dev-setup/.claude/agents"
SKILLS_SRC="$REPO_ROOT/templates/dev-setup/.claude/skills"

# ── Test 7 (REQ-5): no agent can regenerate the diff ──
assert_eq "no agent runs git diff" "" \
  "$(grep -l 'git diff' "$AGENTS_SRC"/*.md 2>/dev/null)"
for AGENT_FILE in verify.md review.md; do
  assert_eq "$AGENT_FILE has no Bash in its tools" "false" \
    "$(frontmatter_of "$AGENTS_SRC/$AGENT_FILE" | grep '^tools:' | grep -q 'Bash' && echo true || echo false)"
  assert_contains "$AGENT_FILE takes PACKAGE as input" \
    "$(cat "$AGENTS_SRC/$AGENT_FILE")" "- **PACKAGE**"
done

# ── Test 9 (REQ-8, REQ-9): the reviewer's model and its short contract ──
REVIEW_FM="$(frontmatter_of "$AGENTS_SRC/review.md")"
VERIFY_FM="$(frontmatter_of "$AGENTS_SRC/verify.md")"
assert_contains "code-reviewer defaults to opus" "$REVIEW_FM" "model: opus"
assert_contains "at high effort" "$REVIEW_FM" "effort: high"
assert_eq "and never max" "false" \
  "$(printf '%s' "$REVIEW_FM" | grep -q 'effort: max' && echo true || echo false)"
assert_contains "spec-verifier stays on opus" "$VERIFY_FM" "model: opus"
assert_contains "at high effort" "$VERIFY_FM" "effort: high"
REVIEW_AGENT="$(cat "$AGENTS_SRC/review.md")"
assert_contains "the review contract caps warnings at 5" "$REVIEW_AGENT" "at most 5"
assert_contains "a violation carries file, line and proof" "$REVIEW_AGENT" \
  "] <file>:<line> — <why it blocks> — proof: <how to show it>"
assert_contains "a warning carries file and line" "$REVIEW_AGENT" \
  "  - <file>:<line> — <suggestion>"
assert_contains "a remark with no file and line is not reported" "$REVIEW_AGENT" \
  "cannot be tied to a file and line is not reported"
assert_contains "the answer never lists what is fine" "$REVIEW_AGENT" "never lists what is fine"

# ── Test 14 (REQ-13): the verify answer is counts plus gaps ──
CHECKS_MD="$(cat "$SKILLS_SRC/verify/reference/checks.md")"
assert_contains "the verify block counts" "$CHECKS_MD" \
  "COUNTS: requirements <covered>/<total> · tests <found>/<total> · decisions <followed>/<total> · Impact files <touched>/<total>"
assert_contains "and lists the gaps" "$CHECKS_MD" "GAPS:"
assert_eq "the per-item COMPLETENESS list is gone" "false" \
  "$(printf '%s' "$CHECKS_MD" | grep -q 'COMPLETENESS:' && echo true || echo false)"
assert_contains "what matches is not listed" "$CHECKS_MD" \
  "Covered requirements, found tests and followed decisions are not listed"
assert_eq "the verify skill no longer promises a list of what matches" "false" \
  "$(grep -q 'an explicit list of what matches' "$SKILLS_SRC/verify/SKILL.md" && echo true || echo false)"

# ── Test 9 (REQ-8): only a large change is promoted ──
REVIEW_SKILL="$(cat "$SKILLS_SRC/review/SKILL.md")"
assert_eq "the review skill passes model: fable on a large SIZE" "true" \
  "$(printf '%s\n' "$REVIEW_SKILL" | grep 'model: fable' | grep -q '`large`' && echo true || echo false)"

# ── Test 10 (REQ-10, REQ-12): the validator exists and ships ──
VALIDATOR="$AGENTS_SRC/validate-findings.md"
VALIDATOR_FM="$(frontmatter_of "$VALIDATOR" 2>/dev/null)"
assert_contains "the validator is named finding-validator" "$VALIDATOR_FM" "name: finding-validator"
assert_contains "it runs on sonnet" "$VALIDATOR_FM" "model: sonnet"
assert_contains "at medium effort" "$VALIDATOR_FM" "effort: medium"
assert_eq "and has no Bash either" "false" \
  "$(printf '%s\n' "$VALIDATOR_FM" | grep '^tools:' | grep -q 'Bash' && echo true || echo false)"
VALIDATOR_BODY="$(cat "$VALIDATOR" 2>/dev/null)"
for NEEDLE in "---VALIDATION-RESULT---" "CONFIRMED:" "DISCARDED:"; do
  assert_contains "the validator returns $NEEDLE" "$VALIDATOR_BODY" "$NEEDLE"
done
assert_contains "the review skill launches the validator" "$REVIEW_SKILL" \
  'Launch the `finding-validator` agent'
assert_contains "the final report counts the discarded findings" \
  "$(cat "$SKILLS_SRC/review/reference/registry-updates.md")" "Discarded: <count>"
assert_eq "the manifest lists validate-findings.md" "true" \
  "$(jq -e '.template_agents | index("validate-findings.md") != null' \
       "$REPO_ROOT/templates/dev-setup/manifest.json" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "the validator ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/agents/validate-findings.md" ] && echo true || echo false)"

# ── Test 11 (REQ-10): what counts, and what an error means ──
assert_contains "an entry without file:line is discarded" "$VALIDATOR_BODY" \
  'An entry without `file:line` is discarded'
assert_contains "the review status is decided on CONFIRMED" "$REVIEW_SKILL" \
  'The status is decided on `CONFIRMED`'
assert_contains "with no validation block every violation stands" "$REVIEW_SKILL" \
  'no `---VALIDATION-RESULT---` block, every violation stands'
assert_contains "and the validator is not launched for nothing" "$REVIEW_SKILL" \
  'With no violations, the validator is not launched'

# ── Test 8 (REQ-5, REQ-6): the closure packages once and runs both checks ──
CLOSURE="$SKILLS_SRC/sdd/reference/closure.md"
assert_eq "the closure builds the package exactly once" "1" \
  "$(grep -o 'review-package\.sh' "$CLOSURE" | wc -l | tr -d ' ')"
# Step 3 is the block between its heading and step 4's.
CLOSURE_STEP3="$(sed -n '/^## 3\. /,/^## 4\. /p' "$CLOSURE")"
line_of() { printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1; }
STAGE_AT="$(line_of "$CLOSURE_STEP3" 'git add -A')"
PACKAGE_AT="$(line_of "$CLOSURE_STEP3" 'review-package.sh')"
assert_eq "step 3 stages before it packages" "true" \
  "$([ -n "$STAGE_AT" ] && [ -n "$PACKAGE_AT" ] && [ "$STAGE_AT" -lt "$PACKAGE_AT" ] && echo true || echo false)"
CLOSURE_MD="$(cat "$CLOSURE")"
assert_contains "both skills get the one package" "$CLOSURE_MD" \
  'Invoke the `verify` and `review` skills in the same turn, each with `PACKAGE` and `SIZE`'
assert_contains "and both agents launch in one message" "$CLOSURE_MD" \
  'launch `spec-verifier` and `code-reviewer` in one message'
assert_contains "an empty change stops the closure" "$CLOSURE_MD" \
  '`EMPTY=true` stops the closure: nothing to verify or review'
OUTCOME_1="$(line_of "$CLOSURE_MD" '1. **verify fail** → back to development')"
OUTCOME_2="$(line_of "$CLOSURE_MD" '2. otherwise **review fail** → fix the `CONFIRMED` violations and rerun from step 3')"
OUTCOME_3="$(line_of "$CLOSURE_MD" '3. otherwise **verify pass-with-warnings** → show the warnings and ask')"
OUTCOME_4="$(line_of "$CLOSURE_MD" '4. otherwise → step 5')"
assert_eq "the two results are read in one order" "true" \
  "$([ -n "$OUTCOME_1" ] && [ -n "$OUTCOME_2" ] && [ -n "$OUTCOME_3" ] && [ -n "$OUTCOME_4" ] \
       && [ "$OUTCOME_1" -lt "$OUTCOME_2" ] && [ "$OUTCOME_2" -lt "$OUTCOME_3" ] \
       && [ "$OUTCOME_3" -lt "$OUTCOME_4" ] && echo true || echo false)"
assert_contains "the developer guide runs the two checks in parallel" \
  "$(cat "$REPO_ROOT/docs/developer-guide.md")" "verify ∥ review"

# ── Test 12 (REQ-7): invoked on their own, the skills build the package ──
for SKILL_NAME in verify review; do
  SKILL_BODY="$(cat "$SKILLS_SRC/$SKILL_NAME/SKILL.md")"
  assert_contains "$SKILL_NAME accepts a PACKAGE from its caller" "$SKILL_BODY" 'With a `PACKAGE` given'
  assert_contains "$SKILL_NAME builds one otherwise" "$SKILL_BODY" \
    'review-package.sh" --base <MERGE_BASE> --json'
  assert_contains "$SKILL_NAME launches no agent on an empty change" "$SKILL_BODY" \
    '`EMPTY=true` means there is nothing to'
done
bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict >/dev/null 2>&1
assert_eq "the static checks pass, word budgets included" "0" "$?"

echo ""
echo "══ DE-16488 — the documentation cannot go stale in silence ══"

# The four pages the refactor owes its readers. Each one has a distinct job, and
# a missing one is not covered by any other check.
for DOC in onboarding.md developer-guide.md migration-v2-to-v3.md training.md workflow.md; do
  assert_eq "docs/$DOC exists" "true" \
    "$([ -f "$REPO_ROOT/docs/$DOC" ] && echo true || echo false)"
done

# The onboarding page is the one with a size contract: it replaces a document
# that grew into an architecture description nobody read to the end.
ONBOARDING_LINES=$(wc -l < "$REPO_ROOT/docs/onboarding.md" | tr -d ' ')
if [ "$ONBOARDING_LINES" -le 120 ]; then
  pass "the onboarding page is still one page ($ONBOARDING_LINES lines)"
else
  fail "the onboarding page is still one page" "grew to $ONBOARDING_LINES lines (cap 120)"
fi

# Checks 14 and 15 are the anti-drift gate. On the repo as committed they must
# be silent — a finding here means a doc names something that does not exist.
DOC_FINDINGS="$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict --json 2>/dev/null \
  | jq -r '[.FINDINGS[]? | select(.CHECK_ID == "DOC_REFERENCE" or .CHECK_ID == "DOC_COMMAND_COVERAGE")
            | "\(.FILE): \(.MESSAGE)"] | join("\n")')"
assert_eq "no doc cites a command, script or path that does not exist" "" "$DOC_FINDINGS"

# And the gate has to actually bite: a page naming a retired command, a deleted
# script and a rule no template generates must come back with findings. Without
# this the check could silently match nothing and still report success.
PROBE="$REPO_ROOT/docs/zz-drift-probe.md"
# The probe names nothing check 12 also looks for: this file lives under
# scripts/, which check 12 greps for the removed runtimes, and a fixture that
# trips a second check would have to be excluded from it.
cat > "$PROBE" <<'PROBE_EOF'
# drift probe (temporary — removed by test-plugin-scripts.sh)
Run `/dev-setup:tdd`, then `/project:release-plugin`.
The script `retired-builder.sh` is at `scripts/builders/retired-builder.sh`.
See `${CLAUDE_PLUGIN_ROOT}/scripts/nope.sh` and the rule `dev-setup-constitution.md`.
Follow [the gone page](./no-such-page.md).
PROBE_EOF
PROBE_KEYS="$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict --json 2>/dev/null \
  | jq -r '[.FINDINGS[]? | select(.CHECK_ID == "DOC_REFERENCE" and (.FILE | test("zz-drift-probe")))
            | .MESSAGE] | join("\n")')"
rm -f "$PROBE"

for NEEDLE in \
  "/dev-setup:tdd" \
  "/project:release-plugin" \
  "retired-builder.sh" \
  'scripts/nope.sh' \
  "dev-setup-constitution.md" \
  "no-such-page.md"
do
  assert_contains "the drift check catches $NEEDLE" "$PROBE_KEYS" "$NEEDLE"
done

# The migration page is the one exclusion, and it has to stay a *deliberate*
# one: it is the only document whose subject is the things that were removed.
assert_contains "the migration page is the check's single exclusion" \
  "$(cat "$REPO_ROOT/scripts/validate-plugin.sh")" \
  'DOC_DRIFT_EXCLUDE="docs/migration-v2-to-v3.md"'
assert_eq "and it is genuinely full of dead references" "false" \
  "$(grep -qE '/dev-setup:(tdd|bdd)|protect-files\.sh' \
       "$REPO_ROOT/docs/migration-v2-to-v3.md" && echo false || echo true)"

# The public surface and the guide agree in both directions. Check 15 covers
# guide-is-missing-a-command; this covers the reverse — the guide's command
# table must not have grown a command the plugin does not expose.
GUIDE_CMDS="$(grep -o '/dev-setup:[a-z][a-z0-9-]*' "$REPO_ROOT/docs/developer-guide.md" \
  | sed 's|/dev-setup:||' | LC_ALL=C sort -u)"
PUBLIC_CMDS="$(for S in "$REPO_ROOT"/dist/dev-setup/skills/*/SKILL.md; do
    sed -n '2,/^---$/p' "$S" | grep -q '^user-invocable: true' \
      && basename "$(dirname "$S")"
  done | LC_ALL=C sort -u)"
assert_eq "the guide documents exactly the public commands" "$PUBLIC_CMDS" "$GUIDE_CMDS"

echo ""
echo "══ check 16 — a setup step that asks reports what it answered ══"

# On the repo as committed the check is silent. A finding here means a setup step
# can ask the developer something and leave no trace of the answer.
ASK_FINDINGS="$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict --json 2>/dev/null \
  | jq -r '[.FINDINGS[]? | select(.CHECK_ID == "SETUP_ASK_UNREPORTED")
            | "\(.FILE): \(.MESSAGE)"] | join("\n")')"
assert_eq "no setup step asks without reporting or defaulting" "" "$ASK_FINDINGS"

# And it has to bite. Three blocks: the defect, and the two shapes that are
# deliberately exempt — an ask whose default decides for the developer, and an
# ask whose outcome reaches the summary.
ASK_PROBE="$REPO_ROOT/templates/dev-setup/setup/reference/zz-ask-probe.md"
cat > "$ASK_PROBE" <<'ASK_EOF'
# ask probe (temporary — removed by test-plugin-scripts.sh)

## 9.1 — Unreported

Ask: "Do you want the probe?" If yes, run the probe.

## 9.2 — Defaulted

Otherwise → ask the developer (default: **no**).

## 9.3 — Reported

Ask: "Do you want the other probe?" Close with one line for the summary:
`probe registered` or `probe declined`.
ASK_EOF
ASK_PROBE_KEYS="$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict --json 2>/dev/null \
  | jq -r '[.FINDINGS[]? | select(.CHECK_ID == "SETUP_ASK_UNREPORTED" and (.FILE | test("zz-ask-probe")))
            | .KEY] | join("\n")')"
rm -f "$ASK_PROBE"

assert_contains "the check catches an unreported ask" "$ASK_PROBE_KEYS" "9.1 — Unreported"
assert_eq "an ask with a declared default is exempt" "false" \
  "$(printf '%s' "$ASK_PROBE_KEYS" | grep -q '9.2' && echo true || echo false)"
assert_eq "an ask that reaches the summary is exempt" "false" \
  "$(printf '%s' "$ASK_PROBE_KEYS" | grep -q '9.3' && echo true || echo false)"

# The step the check was written for, pinned on the shipped artefact: 6.3 offers
# the Figma MCP and says what it contributes to the summary.
assert_contains "6.3 states the line it contributes to the summary" \
  "$(cat "$REPO_ROOT/dist/dev-setup/skills/setup/reference/mcp-env.md")" \
  "Figma MCP registered"

# `--type url` is not a transport: a server added that way is discarded without a
# word. It is how 2.3.1 registered Figma, and no setup reference may go back to it.
assert_eq "no setup reference registers an MCP server with --type url" "false" \
  "$(grep -rq -- '--type url' "$REPO_ROOT/templates/dev-setup/setup" \
       "$REPO_ROOT/dist/dev-setup/skills/setup" && echo true || echo false)"

# The asks in the setup are real AskUserQuestion calls — `install.md` alone
# instructs three of them — so nothing may take that tool away. The documented
# rule: `allowed-tools` only pre-approves the tools it lists and restricts none;
# `disallowed-tools` is the one field that removes a tool, until the developer's
# next message. So the setup declares the tools it does not need there, and
# AskUserQuestion is callable because that line does not name it. No `model:`
# either: an override either lasts one turn of a multi-turn setup, paying two
# cache re-keys, or silently moves the rest of the session to another model.
SETUP_FM="$(sed -n '2,/^---$/p' "$REPO_ROOT/dist/dev-setup/skills/setup/SKILL.md")"
SETUP_DISALLOWED="$(printf '%s\n' "$SETUP_FM" | grep '^disallowed-tools:')"
assert_eq "the setup declares no allowed-tools, which would restrict nothing" "" \
  "$(printf '%s\n' "$SETUP_FM" | grep '^allowed-tools:')"
assert_eq "the setup does not switch the session model" "" \
  "$(printf '%s\n' "$SETUP_FM" | grep '^model:')"
for TOOL in Agent WebFetch WebSearch; do
  assert_contains "the setup removes $TOOL through disallowed-tools" "$SETUP_DISALLOWED" "$TOOL"
done
assert_eq "and leaves AskUserQuestion callable" "false" \
  "$(printf '%s' "$SETUP_DISALLOWED" | grep -q 'AskUserQuestion' && echo true || echo false)"

echo ""
echo "══ DE-17061 — what the claude.dev analysis found ══"

# REQ-3. `gh *` / `glab *` in excludedCommands only helps a call that has no
# `$(…)`, no subshell, no `cd` and no redirect: any of them keeps the whole call
# sandboxed, where on macOS it fails TLS verification. So every merge-request
# form in the references passes literal values, single-quoted — never a
# substitution and never a double-quoted string a filled title could turn into
# one. Pinned on the source and on the shipped copy.
for VCS_DIR in "$REPO_ROOT/shared/skills/vcs-ops/reference" \
               "$REPO_ROOT/dist/dev-setup/skills/vcs-ops/reference"; do
  WHERE="${VCS_DIR#"$REPO_ROOT"/}"
  assert_eq "$WHERE: no merge-request row carries a \$ or a double-quoted value" "" \
    "$(grep -hE '^\|' "$VCS_DIR/github.md" "$VCS_DIR/gitlab.md" \
         | grep -E 'gh pr create|glab mr create|--description' | grep -E '[$"]')"
  assert_eq "$WHERE: gitlab.md suggests no \$(cat body.md) and no double-quoted description" "" \
    "$(grep -nF -e '$(cat body.md)' -e '--description "' "$VCS_DIR/gitlab.md")"
  for NEEDLE in "--base '<BASE_BRANCH>'" "--head '<BRANCH>'" "--title '<TITLE>'" "'\\''"; do
    assert_contains "$WHERE: github.md passes $NEEDLE" "$(cat "$VCS_DIR/github.md")" "$NEEDLE"
  done
  for NEEDLE in "--source-branch '<BRANCH>'" "--target-branch '<BASE_BRANCH>'" "--title '<TITLE>'" "'\\''"; do
    assert_contains "$WHERE: gitlab.md passes $NEEDLE" "$(cat "$VCS_DIR/gitlab.md")" "$NEEDLE"
  done
done

# REQ-4. A `userConfig` value reaches a plugin in two ways only: substituted as
# `${user_config.KEY}` in the body of a skill or an agent, and exported to hooks
# as CLAUDE_PLUGIN_OPTION_<KEY>. Bash and Read see neither, so the contract may
# not send a flow to "read the plugin's userConfig" — the clickup skill states
# the value, and the contract points there.
for F in "templates/dev-setup/.claude/reference/clickup-contract.md" \
         "templates/dev-setup/setup/reference/mcp-env.md" \
         "dist/dev-setup/reference/clickup-contract.md" \
         "dist/dev-setup/skills/setup/reference/mcp-env.md"; do
  assert_eq "$F does not send a flow to read the plugin's userConfig" "false" \
    "$(grep -qF "plugin's \`userConfig\`" "$REPO_ROOT/$F" && echo true || echo false)"
done
for F in "shared/skills/clickup/SKILL.md" "dist/dev-setup/skills/clickup/SKILL.md"; do
  assert_contains "$F states the install-time list id" \
    "$(cat "$REPO_ROOT/$F")" '${user_config.CLICKUP_SETUP_LIST_ID}'
done
assert_contains "the contract resolves the list id through the clickup skill" \
  "$(cat "$REPO_ROOT/templates/dev-setup/.claude/reference/clickup-contract.md")" \
  "list configured at install time"

# A placeholder naming a key the manifest does not declare is never substituted:
# the model would read the literal text. Every one must name a declared key.
undeclared_user_config() {
  local declared
  declared="$(jq -r '.userConfig // {} | keys[]' "$REPO_ROOT/dist/dev-setup/.claude-plugin/plugin.json")"
  grep -rhoE '\$\{user_config\.[A-Za-z0-9_]+\}' "$@" 2>/dev/null \
    | sed -E 's/^\$\{user_config\.//; s/\}$//' | LC_ALL=C sort -u \
    | while IFS= read -r KEY; do
        printf '%s\n' "$declared" | grep -qxF "$KEY" || printf '%s\n' "$KEY"
      done
}
assert_eq "every \${user_config.KEY} in a shipped skill or agent is declared" "" \
  "$(undeclared_user_config "$REPO_ROOT/dist/dev-setup/skills" "$REPO_ROOT/dist/dev-setup/agents")"
UC_PROBE="$WORK_DIR/user-config-probe"
mkdir -p "$UC_PROBE"
printf 'List: ${user_config.CLICKUP_SETUP_LIST_ID}, team: ${user_config.NOT_DECLARED}\n' \
  > "$UC_PROBE/SKILL.md"
assert_eq "and the check catches an undeclared key" "NOT_DECLARED" \
  "$(undeclared_user_config "$UC_PROBE")"

# REQ-6. AGENTS.md is the ground truth for an agent, so it may not credit the
# setup with a boundary its frontmatter does not draw.
AGENTS_MD="$(cat "$REPO_ROOT/AGENTS.md")"
assert_eq "AGENTS.md no longer says allowed-tools denies the agent launcher" "false" \
  "$(printf '%s' "$AGENTS_MD" | grep -q 'denies the agent launcher and the network' && echo true || echo false)"
assert_contains "AGENTS.md describes the setup's disallowed-tools" "$AGENTS_MD" "disallowed-tools"
assert_eq "the AGENTS.md version footer moved past 2.25.0" "false" \
  "$(printf '%s' "$AGENTS_MD" | grep -q '^\*Version: 2\.25\.0 ' && echo true || echo false)"

# DE-17064. The hooks changed channel and filter, and the two pages that
# describe them have to say so: AGENTS.md is the ground truth for an agent, the
# developer guide is what a person reads when the gate or the reminder behaves
# differently from what they expected.
assert_eq "AGENTS.md no longer calls exit 2 the channel" "false" \
  "$(printf '%s' "$AGENTS_MD" | grep -q 'Exit 2 is the channel' && echo true || echo false)"
assert_contains "AGENTS.md names additionalContext as the channel" "$AGENTS_MD" "additionalContext"
assert_contains "and the gate's if rule" "$AGENTS_MD" 'Bash(*git *commit*)'
DEV_GUIDE_MD="$(cat "$REPO_ROOT/docs/developer-guide.md")"
assert_contains "the developer guide names the gate's if rule" "$DEV_GUIDE_MD" 'Bash(*git *commit*)'
assert_contains "and says the reminder arrives as context" "$DEV_GUIDE_MD" "additionalContext"

# REQ-8. A skill launches an agent by its frontmatter `name:`, not by its file
# name: review.md is `code-reviewer`, verify.md is `spec-verifier`. A name that
# resolves to no agent sends the launcher looking for one that does not exist.
AGENT_NAMES="$SHIPPED_AGENTS"
UNKNOWN_AGENTS="$(grep -rhoE 'Launch the `[^`]+` agent' \
    "$REPO_ROOT/templates/dev-setup/.claude/skills" "$REPO_ROOT/shared/skills" \
  | sed -E 's/^Launch the `//; s/` agent$//' | LC_ALL=C sort -u \
  | while IFS= read -r NAME; do
      printf '%s\n' "$AGENT_NAMES" | grep -qxF "$NAME" || printf '%s\n' "$NAME"
    done)"
assert_eq "every \"Launch the \`<name>\` agent\" names an agent's frontmatter name" "" "$UNKNOWN_AGENTS"

# ═══════════════════════════════════════════════════════════════════════════════
# 15. instruction-files.sh: which instruction file Claude Code reads (DE-17167)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Claude Code reads AGENTS.md only when no CLAUDE.md, .claude/CLAUDE.md or
# CLAUDE.local.md sits in the directory or above it. Telling the one-line shim
# the setup used to write from a CLAUDE.md the team wrote is the step that can
# destroy instructions, so it is a script with fixtures, not prose.

echo ""
echo "── instruction-files.sh (which instruction file Claude Code reads) ──"

IF_SCRIPT="$PLUGIN_SCRIPTS/instruction-files.sh"

# One `<key>` of the JSON object, as lines.
if_key() { printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // "<missing>"'; }

# Every file under a tree with its checksum, plus every path: a run that wrote,
# removed or created anything changes it.
if_tree_sum() {
  (cd "$1" && { find . -print | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; })
}

# ── Test 1 (REQ-2): shims, custom files, local files ──
IF_TREE="$WORK_DIR/if-scan"
mkdir -p "$IF_TREE/apps/web" "$IF_TREE/apps/api" "$IF_TREE/apps/admin/.claude" \
  "$IF_TREE/libs/ui" "$IF_TREE/apps/x" "$IF_TREE/node_modules/pkg" \
  "$IF_TREE/.claude/worktrees/DE-1"
for D in "" apps/web apps/api apps/admin apps/x node_modules/pkg .claude/worktrees/DE-1; do
  printf '# Agents\n' > "$IF_TREE/${D:+$D/}AGENTS.md"
done
printf '@AGENTS.md\n' > "$IF_TREE/CLAUDE.md"
printf '@AGENTS.md  \r\n\n' > "$IF_TREE/apps/web/CLAUDE.md"
printf '@AGENTS.md\nUse pnpm.' > "$IF_TREE/apps/api/CLAUDE.md"
printf 'Be terse.' > "$IF_TREE/apps/admin/.claude/CLAUDE.md"
printf 'Notes' > "$IF_TREE/libs/ui/CLAUDE.md"
printf '\n@AGENTS.md' > "$IF_TREE/apps/x/CLAUDE.md"
printf 'my local notes\n' > "$IF_TREE/CLAUDE.local.md"
printf '@AGENTS.md\n' > "$IF_TREE/node_modules/pkg/CLAUDE.md"
printf '@AGENTS.md\n' > "$IF_TREE/.claude/worktrees/DE-1/CLAUDE.md"

IF_SUM_BEFORE="$(if_tree_sum "$IF_TREE")"
IF_OUT="$(bash "$IF_SCRIPT" --json --dir "$IF_TREE" 2>/dev/null)"
IF_ALL="$(for K in SHIMS CUSTOM UNIMPORTED LOCAL; do if_key "$IF_OUT" "$K"; echo; done)"

assert_eq "SHIMS is exactly the files that hold only @AGENTS.md" \
  "CLAUDE.md
apps/web/CLAUDE.md" "$(if_key "$IF_OUT" SHIMS)"
assert_eq "CUSTOM is every other CLAUDE.md that shadows an AGENTS.md" \
  "apps/admin/.claude/CLAUDE.md
apps/api/CLAUDE.md
apps/x/CLAUDE.md" "$(if_key "$IF_OUT" CUSTOM)"
assert_eq "UNIMPORTED is the custom file with no @AGENTS.md line" \
  "apps/admin/.claude/CLAUDE.md" "$(if_key "$IF_OUT" UNIMPORTED)"
assert_eq "LOCAL is the CLAUDE.local.md" "CLAUDE.local.md" "$(if_key "$IF_OUT" LOCAL)"
assert_eq "nothing under node_modules/ or .claude/worktrees/ is listed" "false" \
  "$(printf '%s' "$IF_ALL" | grep -q 'node_modules\|worktrees' && echo true || echo false)"
assert_eq "a CLAUDE.md with no AGENTS.md beside it is in no list" "false" \
  "$(printf '%s' "$IF_ALL" | grep -q 'libs/ui' && echo true || echo false)"

# ── Test 2 (REQ-3): the files above the project ──
# Only the lines under the fixture base are asserted: in CI the meta-repo's own
# CLAUDE.md sits above the repo-local work directory.
IF_BASE="$WORK_DIR/if-above"
mkdir -p "$IF_BASE/parent/proj" "$IF_BASE/.claude"
printf '# Agents\n' > "$IF_BASE/parent/proj/AGENTS.md"
printf 'local\n' > "$IF_BASE/parent/CLAUDE.local.md"
printf 'above\n' > "$IF_BASE/CLAUDE.md"
printf 'user\n' > "$IF_BASE/.claude/CLAUDE.md"
IF_ABOVE="$(HOME="$IF_BASE" bash "$IF_SCRIPT" --json --dir "$IF_BASE/parent/proj" 2>/dev/null \
  | jq -r '.ABOVE')"
# The lines of stdin under the directory $1. A function, not a `case` inside
# `$(…)`: bash 3.2 misparses the pattern's `)` there.
if_lines_under() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "$1"/*) printf '%s\n' "$line" ;;
    esac
  done
}
IF_ABOVE_UNDER="$(printf '%s\n' "$IF_ABOVE" | if_lines_under "$IF_BASE" | LC_ALL=C sort)"
assert_eq "ABOVE lists the CLAUDE.md and CLAUDE.local.md above the project" \
  "$(printf '%s\n%s' "$IF_BASE/CLAUDE.md" "$IF_BASE/parent/CLAUDE.local.md" | LC_ALL=C sort)" \
  "$IF_ABOVE_UNDER"
assert_eq "ABOVE never lists the user's ~/.claude/CLAUDE.md" "false" \
  "$(printf '%s\n' "$IF_ABOVE" | grep -qxF "$IF_BASE/.claude/CLAUDE.md" && echo true || echo false)"

IF_BASE2="$WORK_DIR/if-above2"
mkdir -p "$IF_BASE2/proj"
IF_ABOVE2="$(bash "$IF_SCRIPT" --json --dir "$IF_BASE2/proj" 2>/dev/null | jq -r '.ABOVE')"
assert_eq "with no instruction file above, ABOVE names nothing there" "false" \
  "$(printf '%s\n' "$IF_ABOVE2" | grep -q "^$IF_BASE2/" && echo true || echo false)"

# ── Test 3 (REQ-4): the client version, compared per component ──
IF_BIN="$WORK_DIR/if-bin"
mkdir -p "$IF_BIN"
# shellcheck disable=SC2016
printf '#!/bin/sh\ncat "$(dirname "$0")/version.txt"\n' > "$IF_BIN/claude"
chmod +x "$IF_BIN/claude"
if_version_ok() {
  printf '%s\n' "$1" > "$IF_BIN/version.txt"
  PATH="$IF_BIN:$PATH" bash "$IF_SCRIPT" --json --dir "$IF_TREE" 2>/dev/null \
    | jq -r '"\(.VERSION_OK)|\(.CLAUDE_VERSION)|\(.MIN_CLAUDE_VERSION)"'
}
for V in 2.1.281 2.1.300 2.2.0 2.1.1000; do
  assert_eq "claude $V is at or above the floor" "true|$V|2.1.281" \
    "$(if_version_ok "$V (Claude Code)")"
done
assert_eq "claude 2.1.280 is below the floor" "false|2.1.280|2.1.281" "$(if_version_ok "2.1.280")"
for V in 2.1.28 2.1.29 2.1.99; do
  assert_eq "claude $V is below the floor (numeric, not string, comparison)" \
    "false|$V|2.1.281" "$(if_version_ok "$V (Claude Code)")"
done
assert_eq "an output with no version leaves VERSION_OK empty" "||2.1.281" "$(if_version_ok "garbage")"

# No claude at all: a PATH of the system directories plus the two programs the
# script needs that may live elsewhere.
IF_NOBIN="$WORK_DIR/if-nobin"
mkdir -p "$IF_NOBIN"
for P in jq git; do
  ln -sf "$(command -v "$P")" "$IF_NOBIN/$P"
done
if [ -x /usr/bin/claude ] || [ -x /bin/claude ]; then
  pass "no claude on PATH: skipped, a claude is installed in a system directory"
else
  assert_eq "no claude on PATH leaves VERSION_OK and CLAUDE_VERSION empty" "||2.1.281" \
    "$(PATH="$IF_NOBIN:/usr/bin:/bin" "$BASH" "$IF_SCRIPT" --json --dir "$IF_TREE" 2>/dev/null \
      | jq -r '"\(.VERSION_OK)|\(.CLAUDE_VERSION)|\(.MIN_CLAUDE_VERSION)"')"
fi

# ── Test 4 (REQ-5): the script contract ──
assert_eq "--json prints exactly the eight keys" \
  "ABOVE,CLAUDE_VERSION,CUSTOM,LOCAL,MIN_CLAUDE_VERSION,SHIMS,UNIMPORTED,VERSION_OK" \
  "$(printf '%s' "$IF_OUT" | jq -r 'keys | join(",")' 2>/dev/null)"
assert_eq "every value is a string" "true" \
  "$(printf '%s' "$IF_OUT" | jq -r '[.[] | type] | unique == ["string"]' 2>/dev/null)"
assert_eq "stdout holds the object and nothing else" "1" \
  "$(printf '%s' "$IF_OUT" | jq -s 'length' 2>/dev/null)"
IF_MISSING_OUT="$(bash "$IF_SCRIPT" --json --dir "$WORK_DIR/if-does-not-exist" 2>"$WORK_DIR/if-err")"
IF_MISSING_RC=$?
assert_eq "a --dir that does not exist exits non-zero" "true" \
  "$([ "$IF_MISSING_RC" -ne 0 ] && echo true || echo false)"
assert_eq "with nothing on stdout" "" "$IF_MISSING_OUT"
assert_eq "and says why on stderr" "true" "$([ -s "$WORK_DIR/if-err" ] && echo true || echo false)"
assert_eq "a run leaves the scanned tree byte-identical" "$IF_SUM_BEFORE" "$(if_tree_sum "$IF_TREE")"

# ── Test 8b (REQ-8): --merge moves a custom CLAUDE.md into its AGENTS.md ──
IF_MERGE="$WORK_DIR/if-merge"
mkdir -p "$IF_MERGE/apps/api" "$IF_MERGE/apps/admin/.claude" "$IF_MERGE/apps/team" \
  "$IF_MERGE/apps/x" "$IF_MERGE/libs/ui"
cp "$REPO_ROOT/templates/dev-setup/AGENTS.template.md" "$IF_MERGE/AGENTS.md"
printf 'Be terse.\n' > "$IF_MERGE/CLAUDE.md"
cp "$REPO_ROOT/templates/dev-setup/AGENTS.project-template.md" "$IF_MERGE/apps/api/AGENTS.md"
printf '@AGENTS.md\nUse pnpm.' > "$IF_MERGE/apps/api/CLAUDE.md"
printf '# Admin\n\nAdmin rules.\n' > "$IF_MERGE/apps/admin/AGENTS.md"
printf '\nKeep it short.\n\n' > "$IF_MERGE/apps/admin/.claude/CLAUDE.md"
printf '# Team\n\nWritten by the team, no footer.' > "$IF_MERGE/apps/team/AGENTS.md"
printf 'Team note.\n' > "$IF_MERGE/apps/team/CLAUDE.md"
printf '# X\n' > "$IF_MERGE/apps/x/AGENTS.md"
printf '\n@AGENTS.md' > "$IF_MERGE/apps/x/CLAUDE.md"
printf 'Notes' > "$IF_MERGE/libs/ui/CLAUDE.md"
IF_MERGE_SUM="$(if_tree_sum "$IF_MERGE")"

# Writes the merge of <path> to <out>; prints the exit status.
if_merge() {
  bash "$IF_SCRIPT" --merge "$1" --dir "$IF_MERGE" > "$2" 2>/dev/null
  echo $?
}
# True when <out> starts with <agents> byte for byte.
if_has_prefix() {
  local n
  n=$(wc -c < "$1" | tr -d ' ')
  head -c "$n" "$2" | cmp -s - "$1" && echo true || echo false
}
if_line_of() { grep -nF "$1" "$2" | tail -1 | cut -d: -f1; }
IF_HEADING="## Instructions moved from CLAUDE.md"

# A sub-project file: the section goes after the footer, so the tail the UPDATE
# offer compares — `## Project registry` to the footer — is unchanged.
IF_M="$WORK_DIR/if-merge-api.md"
assert_eq "--merge on a custom CLAUDE.md exits 0" "0" "$(if_merge apps/api/CLAUDE.md "$IF_M")"
assert_eq "the output starts with the sub-project AGENTS.md byte for byte" "true" \
  "$(if_has_prefix "$IF_MERGE/apps/api/AGENTS.md" "$IF_M")"
assert_eq "the moved section comes after the *Generated by: footer" "true" \
  "$([ "$(if_line_of "$IF_HEADING" "$IF_M")" -gt "$(if_line_of '*Generated by:' "$IF_M")" ] \
     && echo true || echo false)"
assert_eq "the CLAUDE.md content follows the heading" "Use pnpm." \
  "$(awk -v h="$IF_HEADING" '$0 == h { f = 1; next } f && NF { print; exit }' "$IF_M")"
assert_eq "no @AGENTS.md line is moved" "0" "$(grep -cx '@AGENTS.md' "$IF_M")"
assert_eq "the sub-project tail is unchanged" \
  "$(sed -n '/^## Project registry/,/^\*Generated by:/p' "$IF_MERGE/apps/api/AGENTS.md")" \
  "$(sed -n '/^## Project registry/,/^\*Generated by:/p' "$IF_M")"

IF_M="$WORK_DIR/if-merge-root.md"
assert_eq "--merge on the root CLAUDE.md exits 0" "0" "$(if_merge CLAUDE.md "$IF_M")"
assert_eq "the output starts with the root AGENTS.md byte for byte" "true" \
  "$(if_has_prefix "$IF_MERGE/AGENTS.md" "$IF_M")"
assert_eq "the root tail is unchanged" \
  "$(sed -n '/^## Available agents/,/^\*Generated by:/p' "$IF_MERGE/AGENTS.md")" \
  "$(sed -n '/^## Available agents/,/^\*Generated by:/p' "$IF_M")"
assert_contains "and the root content is moved" "$(cat "$IF_M")" "$IF_HEADING

Be terse."

IF_M="$WORK_DIR/if-merge-admin.md"
assert_eq "--merge on a .claude/CLAUDE.md exits 0" "0" "$(if_merge apps/admin/.claude/CLAUDE.md "$IF_M")"
assert_eq "it is built from the AGENTS.md of the parent of .claude/" "true" \
  "$(if_has_prefix "$IF_MERGE/apps/admin/AGENTS.md" "$IF_M")"
assert_eq "edge blank lines are dropped" "# Admin

Admin rules.

$IF_HEADING

Keep it short." "$(cat "$IF_M")"

IF_M="$WORK_DIR/if-merge-team.md"
assert_eq "--merge beside a team AGENTS.md with no footer exits 0" "0" \
  "$(if_merge apps/team/CLAUDE.md "$IF_M")"
assert_eq "the team file comes first byte for byte" "true" \
  "$(if_has_prefix "$IF_MERGE/apps/team/AGENTS.md" "$IF_M")"
assert_eq "the section comes after its last line" "true" \
  "$([ "$(if_line_of "$IF_HEADING" "$IF_M")" -gt "$(if_line_of 'no footer.' "$IF_M")" ] \
     && echo true || echo false)"

IF_M="$WORK_DIR/if-merge-x.md"
assert_eq "--merge on a file holding only an import exits 0" "0" "$(if_merge apps/x/CLAUDE.md "$IF_M")"
assert_eq "and leaves the AGENTS.md unchanged" "true" \
  "$(cmp -s "$IF_MERGE/apps/x/AGENTS.md" "$IF_M" && echo true || echo false)"

IF_M="$WORK_DIR/if-merge-ui.md"
assert_eq "--merge on a path not in CUSTOM exits non-zero" "true" \
  "$([ "$(if_merge libs/ui/CLAUDE.md "$IF_M")" -ne 0 ] && echo true || echo false)"
assert_eq "with nothing on stdout" "true" "$([ -s "$IF_M" ] && echo false || echo true)"

assert_eq "--merge writes nothing into the tree" "$IF_MERGE_SUM" "$(if_tree_sum "$IF_MERGE")"

# ── Test 5 (REQ-12): it ships ──
assert_eq "the manifest lists instruction-files.sh" "true" \
  "$(jq -e '.plugin_scripts | index("instruction-files.sh") != null' \
       "$REPO_ROOT/templates/dev-setup/manifest.json" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "instruction-files.sh ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/scripts/instruction-files.sh" ] && echo true || echo false)"

# ── Test 6 (REQ-1): no setup mode generates a CLAUDE.md ──
# Every needle is a line the setup held while it still wrote the shim.
IF_SETUP_DOCS=()
for F in "$TEMPLATE_ROOT/setup/SKILL.md" "$TEMPLATE_ROOT"/setup/reference/*.md \
         "$TEMPLATE_ROOT/profiles/nextjs.md" \
         "$REPO_ROOT/dist/dev-setup/skills/setup/SKILL.md" \
         "$REPO_ROOT"/dist/dev-setup/skills/setup/reference/*.md \
         "$REPO_ROOT/dist/dev-setup/skills/setup/templates/profiles/nextjs.md"; do
  [ -f "$F" ] && IF_SETUP_DOCS+=("$F")
done
assert_eq "the setup docs and their built copies are all there" "18" "${#IF_SETUP_DOCS[@]}"
while IFS= read -r NEEDLE; do
  [ -n "$NEEDLE" ] || continue
  assert_eq "no setup doc says: $NEEDLE" "" \
    "$(grep -lF -- "$NEEDLE" "${IF_SETUP_DOCS[@]}" | sed "s#^$REPO_ROOT/##")"
done <<'EOF'
Generate AGENTS.md and CLAUDE.md
Generate CLAUDE.md
`CLAUDE.md` is the one-line entry
AGENTS.md / CLAUDE.md / REGISTRY.md
generate a `CLAUDE.md`
generate `AGENTS.md`, `CLAUDE.md`
**`CLAUDE.md`** — the import shim
EOF
assert_eq "no setup summary lists a CLAUDE.md row" "" \
  "$(grep -lE '^ *- `?CLAUDE\.md`? ' "${IF_SETUP_DOCS[@]}" | sed "s#^$REPO_ROOT/##")"

# ── Test 7 (REQ-6): the version gate comes first ──
IF_SETUP_MD="$TEMPLATE_ROOT/setup/SKILL.md"
IF_STEP1="$(awk '/^## Step 1/ { f = 1; print; next } f && /^## / { exit } f' "$IF_SETUP_MD" \
  | tr '\n' ' ' | tr -s ' ')"
assert_contains "Step 1 runs instruction-files.sh" "$IF_STEP1" "instruction-files.sh --json"
assert_contains "and acts on VERSION_OK=false" "$IF_STEP1" "VERSION_OK=false"
assert_contains "by stopping before any write" "$IF_STEP1" "stop before any write"
assert_contains "naming both versions" "$IF_STEP1" '`CLAUDE_VERSION` and `MIN_CLAUDE_VERSION`'
assert_eq "the check runs before the mode is reported" "true" \
  "$([ "$(grep -n 'instruction-files.sh --json' "$IF_SETUP_MD" | head -1 | cut -d: -f1)" \
       -lt "$(grep -n 'Report the mode' "$IF_SETUP_MD" | head -1 | cut -d: -f1)" ] \
     && echo true || echo false)"
assert_contains "an unknown version is reported, not refused" "$(cat "$AGENTS_GEN")" \
  "Claude Code version not verified — AGENTS.md needs <MIN_CLAUDE_VERSION> or later"
assert_eq "the setup SKILL.md stays within 500 words" "true" \
  "$([ "$(wc -w < "$IF_SETUP_MD" | tr -d ' ')" -le 500 ] && echo true || echo false)"

# ── Test 8 (REQ-7, REQ-8): Step 5b removes the shims and moves the rest ──
IF_STEP5B="$(awk '/^## Step 5b/ { f = 1; print; next } f && /^## / { exit } f' "$AGENTS_GEN")"
for KEY in SHIMS CUSTOM UNIMPORTED; do
  assert_contains "Step 5b reads $KEY" "$IF_STEP5B" "\`$KEY\`"
done
assert_contains "it reports the removed shims" "$IF_STEP5B" \
  "CLAUDE.md shim removed (AGENTS.md is read directly): <paths>"
assert_contains "it reports a move" "$IF_STEP5B" "<path> moved into <AGENTS.md path> and removed"
assert_contains "it reports a declined move that imports AGENTS.md" "$IF_STEP5B" \
  "<path> kept: Claude Code reads it, and AGENTS.md only through its @AGENTS.md import"
assert_contains "and one that does not" "$IF_STEP5B" \
  "<path> kept: Claude Code reads it and does NOT read <AGENTS.md path>"
assert_contains "the merged file comes from the script" "$IF_STEP5B" "instruction-files.sh --merge"
assert_contains "after the footer" "$IF_STEP5B" '`*Generated by:`'
assert_eq "not under the root file's tail heading" "false" \
  "$(printf '%s' "$IF_STEP5B" | grep -q '## Available agents' && echo true || echo false)"
assert_eq "check 16 finds every ask of the instruction-files step reported" "" \
  "$(bash "$REPO_ROOT/scripts/validate-plugin.sh" --strict 2>&1 | grep 'SETUP_ASK_UNREPORTED' \
     | grep 'agents-generation.md' || true)"

# ── Test 9 (REQ-9): the files the setup does not own ──
for WORD in '`LOCAL`' '`ABOVE`' 'claude-md-and-agents-md' 'cc-plugin-agents-md@builtin'; do
  assert_contains "Step 5b names $WORD" "$IF_STEP5B" "$WORD"
done
assert_eq "Step 5b never writes the user's settings" "" \
  "$(printf '%s\n' "$IF_STEP5B" | grep -E '(>|mv |cp |tee ).*~/\.claude/settings\.json' || true)"
for F in "$TEMPLATE_ROOT/.claude/settings.json" "$TEMPLATE_ROOT/.claude/settings.user.json" \
         "$REPO_ROOT/dist/dev-setup/skills/setup/templates/settings.json" \
         "$REPO_ROOT/dist/dev-setup/skills/setup/templates/settings.user.json"; do
  assert_eq "${F#"$REPO_ROOT"/} carries no pluginConfigs" "true" \
    "$(jq -e 'has("pluginConfigs") | not' "$F" >/dev/null 2>&1 && echo true || echo false)"
done

# ── Test 11 (REQ-11): every shipped agent keeps the project instructions ──
assert_eq "no shipped agent sets omitClaudeMd" "" \
  "$(grep -l omitClaudeMd "$TEMPLATE_ROOT"/.claude/agents/*.md "$REPO_ROOT"/shared/agents/*.md || true)"

# ── Test 10 (REQ-10): the floor is declared where the requirements are ──
IF_MIN="$(bash "$IF_SCRIPT" --json --dir "$IF_TREE" 2>/dev/null | jq -r '.MIN_CLAUDE_VERSION')"
# The paragraph that opens with $1, on one line.
if_paragraph() {
  awk -v start="$1" 'index($0, start) == 1 { f = 1 } f && /^$/ { exit } f' "$2" | tr '\n' ' ' | tr -s ' '
}
IF_README_REQ="$(if_paragraph '**Prerequisites**' "$REPO_ROOT/README.md")"
IF_ONBOARDING_REQ="$(if_paragraph '**You need**' "$REPO_ROOT/docs/onboarding.md")"
for PAIR in "README.md|$IF_README_REQ" "docs/onboarding.md|$IF_ONBOARDING_REQ"; do
  assert_eq "${PAIR%%|*} names the floor instruction-files.sh enforces" "$IF_MIN" \
    "$(printf '%s' "${PAIR#*|}" | grep -oE 'Claude Code [0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^Claude Code //')"
  assert_contains "${PAIR%%|*} applies it on every machine and runner" "${PAIR#*|}" \
    "on every machine and runner"
done

# ── Test 12 (REQ-12): the docs no longer list a CLAUDE.md the setup writes ──
for DOC in README.md docs/onboarding.md docs/developer-guide.md; do
  assert_eq "$DOC lists no CLAUDE.md beside AGENTS.md" "" \
    "$(grep -nF -e '`AGENTS.md`, `CLAUDE.md`' -e 'AGENTS.md, CLAUDE.md' "$REPO_ROOT/$DOC" || true)"
done
IF_MIGRATION="$REPO_ROOT/docs/migration-v2-to-v3.md"
assert_eq "the migration guide has the CLAUDE.md section" "1" \
  "$(grep -c '^## 12\. CLAUDE\.md is gone' "$IF_MIGRATION")"
assert_eq "and its index entry" "1" \
  "$(grep -c '^- \[12\. CLAUDE\.md is gone.*\](#12-' "$IF_MIGRATION")"
assert_eq "the AGENTS.md script table lists instruction-files.sh with its keys" "true" \
  "$(grep -E '^\| `instruction-files\.sh' "$REPO_ROOT/AGENTS.md" | grep -q 'VERSION_OK' && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# 16. The flow shows where it is, and what comes next (DE-17077)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The phases of an `sdd` were only in the skill's table, and the reports a flow
# closes on ended in different ways. Prose assertions, read flattened so that a
# wrapped sentence still counts. The word budgets these edits must respect are
# the `validate-plugin.sh --strict` assertion of section 14.

echo ""
echo "── DE-17077 — the phases on screen, the next command on the last line ──"

PV_INTAKE="$SDD_DIR/sdd/reference/intake.md"
PV_INTAKE_FLAT="$(flat "$PV_INTAKE")"

# ── Test 10 (REQ-10): the phase list is published at intake ──
for PV_NEEDLE in TaskCreate TaskUpdate TodoWrite; do
  assert_contains "intake names the task-list tool $PV_NEEDLE" "$PV_INTAKE_FLAT" "\`$PV_NEEDLE\`"
done
for PV_PHASE in Intake Discovery Spec Approval Development Gates; do
  assert_eq "the phase list holds $PV_PHASE" "1" \
    "$(grep -cE "^\| $PV_PHASE \| " "$PV_INTAKE")"
done
for PV_ROW in '`spec`=Approval — nothing past it' '`development`=Development' \
              '`review`=Gates — nothing past it' '`commit`=Commit' \
              '`push`=Commit and push' '`merge-request`=Commit and merge request'; do
  assert_eq "stop point ${PV_ROW%%=*} ends the list on: ${PV_ROW#*=}" "1" \
    "$(grep -cxF "| ${PV_ROW%%=*} | ${PV_ROW#*=} |" "$PV_INTAKE")"
done
assert_contains "a resume creates the phases already passed completed" "$PV_INTAKE_FLAT" \
  "On a resume, the phases already passed are created completed"
assert_contains "each phase is marked in progress, then completed" "$PV_INTAKE_FLAT" \
  "Mark each phase in progress when it starts and completed when it ends"
assert_contains "and the chat carries one line between calls at most" "$PV_INTAKE_FLAT" \
  "Between tool calls, write at most one line of commentary"

# ── Test 12 (REQ-12): the brief routes to quick, the flow never switches down ──
assert_contains "the brief template carries the Route line" \
  "$(grep -E '^Route:' "$PV_INTAKE" | tr -s ' ')" "Route: looks like quick — /dev-setup:quick"
assert_contains "the rule gives the exact line" "$PV_INTAKE_FLAT" \
  "\`Route: looks like quick — /dev-setup:quick <custom_id>\`"
assert_contains "and the flow goes on in sdd" "$PV_INTAKE_FLAT" "Then the flow goes on in \`sdd\`"
assert_contains "never moving itself to a lighter flow" "$PV_INTAKE_FLAT" \
  "it never moves itself to a lighter flow"

# ── Test 11 (REQ-11): every closing report ends on the next command ──
PV_STOP="$SDD_DIR/sdd/reference/stop-point.md"
PV_STOP_BLOCK="$(awk '/^## Ending at a stop point/ { p = 1; next } /^## / { p = 0 } p' "$PV_STOP")"
PV_STOP_FENCE="$(printf '%s\n' "$PV_STOP_BLOCK" | awk '/^```/ { n++; next } n == 1')"
assert_contains "the stop-point report's last line is the next command" \
  "$(printf '%s\n' "$PV_STOP_FENCE" | grep -v '^[[:space:]]*$' | tail -1 | tr -s ' ')" \
  "Next: /dev-setup:sdd"
assert_eq "and Resume: is gone from it" "" \
  "$(printf '%s\n' "$PV_STOP_BLOCK" | grep -F 'Resume:' || true)"

assert_eq "the GitHub reference has the follow-its-CI row" "1" \
  "$(grep -cF '| Follow its CI | `gh pr checks <n> --watch` |' \
       "$REPO_ROOT/shared/skills/vcs-ops/reference/github.md")"
assert_eq "the GitLab one names the branch explicitly" "1" \
  "$(grep -cF "| Follow its pipeline | \`glab ci status --live --branch '<BRANCH>'\`" \
       "$REPO_ROOT/shared/skills/vcs-ops/reference/gitlab.md")"

PV_CLOSURE="$SDD_DIR/sdd/reference/closure.md"
PV_QUICK="$SDD_DIR/quick/SKILL.md"
PV_OUTCOMES="$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md"
for PV_FILE in "$PV_CLOSURE" "$PV_QUICK" "$PV_OUTCOMES"; do
  PV_NAME="${PV_FILE#"$REPO_ROOT"/templates/dev-setup/.claude/}"
  assert_contains "$PV_NAME ends on Next: and the host reference's CI command" \
    "$(flat "$PV_FILE")" "follow-its-CI command"
  assert_contains "$PV_NAME points at the host reference for it" "$(flat "$PV_FILE")" "host reference"
  assert_eq "$PV_NAME names no host CI command of its own" "" \
    "$(grep -nE 'gh pr checks|glab ci' "$PV_FILE" || true)"
done
assert_contains "a declined merge request in sdd ends on the resume" \
  "$(flat "$PV_CLOSURE")" "Declined means declined: report it, leave the branch pushed, and end on \`Next: /dev-setup:sdd <custom_id>\`"
assert_contains "in quick, on the host reference's open command" \
  "$(flat "$PV_QUICK")" "(declined: its open command)"
assert_contains "and in ready-for-mr too" \
  "$(flat "$PV_OUTCOMES")" "end on \`Next:\` and the host reference's open command"

PV_FAILED="$(awk '/^## failed/ { p = 1; next } /^## / { p = 0 } p' "$PV_OUTCOMES" | tr '\n' ' ' | tr -s ' ')"
for PV_FORM in '`verify` → `Next: cd "<worktreePath>" && <the command that failed>`' \
               '`dev` → `Next: cd "<worktreePath>"`' \
               '`spec` → `Next: /dev-setup:sdd <taskId>`' \
               '`intake` → `Next: /dev-setup:auto-sdd <taskId>`'; do
  assert_contains "failed ends on: ${PV_FORM%% →*}" "$PV_FAILED" "$PV_FORM"
done
assert_eq "quick/SKILL.md stays within 500 words" "true" \
  "$([ "$(wc -w < "$PV_QUICK" | tr -d ' ')" -le 500 ] && echo true || echo false)"

# ── Test 13 (REQ-13): the docs say it ──
#
# The onboarding cap, checks 14–15 and the "no hook exits 2" grep are asserted
# where they always were; these are the sentences this task owes the reader.
PV_ONBOARDING="$(flat "$REPO_ROOT/docs/onboarding.md")"
for PV_NEEDLE in preferredNotifChannel terminal_bell footerLinksRegexes; do
  assert_contains "onboarding documents $PV_NEEDLE" "$PV_ONBOARDING" "$PV_NEEDLE"
done
assert_contains "as user settings, never the project's" "$PV_ONBOARDING" \
  "never the project's \`.claude/settings.json\`"
PV_GUIDE="$(flat "$REPO_ROOT/docs/developer-guide.md")"
for PV_NEEDLE in notify.sh session-title.sh; do
  assert_contains "the developer guide names $PV_NEEDLE" "$PV_GUIDE" "\`$PV_NEEDLE\`"
done
assert_contains "AGENTS.md lists RECENT_TASKS" "$(cat "$REPO_ROOT/AGENTS.md")" "\`RECENT_TASKS\`"

# ═══════════════════════════════════════════════════════════════════════════════
# 17. save-failed-run.sh: a failed run's work, past the gates
# ═══════════════════════════════════════════════════════════════════════════════
#
# A failed run in a cloud session loses its work with the session, and the
# project's gates refuse the commit and the push that would save it — the red
# commands are why the run failed. So the script commits and pushes past the
# hooks. What is tested is that it saves whatever exists — a worktree, a bare
# branch, or only the spec — and how narrow it stays: it refuses outside a
# cloud session and off the task's own branch, never commits without a reason,
# never forces, and its commit says the hooks were skipped.

echo ""
echo "── save-failed-run.sh (a failed run's work, past the gates) ──"

SFR_REMOTE="$WORK_DIR/save-failed-run-remote.git"
SFR_REPO="$WORK_DIR/save-failed-run-repo"
SFR_BRANCH="feat(notes)/DE-900_unread-filter"
mkdir -p "$SFR_REPO"
git init --quiet --bare --template="$EMPTY_GIT_TEMPLATE" "$SFR_REMOTE" >/dev/null 2>&1
(
  cd "$SFR_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  git remote add origin "$SFR_REMOTE"
  echo "base" > base.txt
  printf '.hooks/\n' > .gitignore
  git add . && git commit --quiet -m "chore: base"
  # A project whose every hook refuses — pre-commit, commit-msg and pre-push —
  # behind a custom hooks path, as husky sets one.
  mkdir -p .hooks
  for HOOK in pre-commit commit-msg pre-push; do
    printf '#!/bin/sh\necho "%s refused" >&2\nexit 1\n' "$HOOK" > ".hooks/$HOOK"
    chmod +x ".hooks/$HOOK"
  done
  git config core.hooksPath "$SFR_REPO/.hooks"
) >/dev/null 2>&1
# The run's worktree, on the task's branch, as the dev agent leaves it.
SFR_TREE="$WORK_DIR/save-failed-run-tree"
git -C "$SFR_REPO" worktree add --quiet -b "$SFR_BRANCH" "$SFR_TREE" >/dev/null 2>&1

SFR_REASON="$WORK_DIR/save-failed-run-reason.txt"
printf 'Blocked on the backend: GET /notes has no unread filter yet.\n' > "$SFR_REASON"

sfr() { (cd "$SFR_REPO" && bash "$PLUGIN_SCRIPTS/save-failed-run.sh" --json "$@" 2>/dev/null); }
sfr_exit() {
  (cd "$SFR_REPO" && bash "$PLUGIN_SCRIPTS/save-failed-run.sh" --json "$@") >/dev/null 2>&1
  printf '%s' "$?"
}
sfr_tip() { git -C "$SFR_REPO" rev-parse --verify --quiet "refs/heads/$1"; }
sfr_remote_tip() { git -C "$SFR_REMOTE" rev-parse --verify --quiet "refs/heads/$1"; }

assert_eq "the project's own hooks refuse an ordinary commit" "1" \
  "$(cd "$SFR_TREE" && echo wip > wip.txt && git add wip.txt && git commit --quiet -m 'wip' >/dev/null 2>&1; echo $?; git reset --quiet; rm -f wip.txt)"

# Outside a cloud session the worktree survives, so the gates stay.
SFR_BEFORE="$(sfr_tip "$SFR_BRANCH")"
SFR_LOCAL="$(env -u CLAUDE_CODE_REMOTE bash -c 'cd "$1" && bash "$2" --json --task DE-900 --stage verify --reason-file "$3" 2>/dev/null' _ \
  "$SFR_REPO" "$PLUGIN_SCRIPTS/save-failed-run.sh" "$SFR_REASON")"
assert_eq "it refuses outside a cloud session" "false" "$(printf '%s' "$SFR_LOCAL" | jq -r '.SAVED')"
assert_contains "and says why" "$(printf '%s' "$SFR_LOCAL" | jq -r '.REASON')" "CLAUDE_CODE_REMOTE"
assert_eq "with exit 3" "3" "$(env -u CLAUDE_CODE_REMOTE bash -c \
  'cd "$1" && bash "$2" --json --task DE-900 --stage verify --reason-file "$3" >/dev/null 2>&1; echo $?' _ \
  "$SFR_REPO" "$PLUGIN_SCRIPTS/save-failed-run.sh" "$SFR_REASON")"
assert_eq "and commits nothing" "$SFR_BEFORE" "$(sfr_tip "$SFR_BRANCH")"

export CLAUDE_CODE_REMOTE=true

# Only the task's own branch.
assert_eq "it refuses a worktree on another task's branch" "3" \
  "$(sfr_exit --task DE-901 --stage verify --reason-file "$SFR_REASON" --dir "$SFR_TREE")"
assert_eq "and with nothing that carries the task, nothing to save" "3" \
  "$(sfr_exit --task DE-901 --stage verify --reason-file "$SFR_REASON")"
assert_contains "it says so" \
  "$(sfr --task DE-901 --stage verify --reason-file "$SFR_REASON" | jq -r '.REASON')" "nothing to save"

# No reason, no commit: a skipped gate has to say why.
: > "$WORK_DIR/save-failed-run-empty.txt"
assert_eq "an empty reason is a usage error" "1" \
  "$(sfr_exit --task DE-900 --stage verify --reason-file "$WORK_DIR/save-failed-run-empty.txt")"
assert_eq "an unknown stage is a usage error" "1" \
  "$(sfr_exit --task DE-900 --stage closure --reason-file "$SFR_REASON")"
assert_eq "and neither commits" "$SFR_BEFORE" "$(sfr_tip "$SFR_BRANCH")"

# 1 — the run's worktree, found from the task id: uncommitted and untracked
# work, every hook red, pushed as it is.
(cd "$SFR_TREE" && echo "changed" >> base.txt && echo "new" > notes_filter.dart)
SFR_SAVED="$(sfr --task DE-900 --stage verify --reason-file "$SFR_REASON")"
assert_eq "in a cloud session it commits past the red hooks" "true" "$(printf '%s' "$SFR_SAVED" | jq -r '.SAVED')"
assert_eq "finding the worktree from the task id" "$(cd "$SFR_TREE" && pwd -P)" \
  "$(cd "$(printf '%s' "$SFR_SAVED" | jq -r '.WORKTREE')" && pwd -P)"
assert_eq "everything the worktree held" "2" "$(printf '%s' "$SFR_SAVED" | jq -r '.FILES')"
assert_eq "leaving it clean" "" "$(git -C "$SFR_TREE" status --porcelain)"
assert_eq "and pushes past the red pre-push hook" "true" "$(printf '%s' "$SFR_SAVED" | jq -r '.PUSHED')"
assert_eq "the remote has the commit" "$(printf '%s' "$SFR_SAVED" | jq -r '.COMMIT')" "$(sfr_remote_tip "$SFR_BRANCH")"
SFR_MESSAGE="$(git -C "$SFR_REPO" log -1 --format=%B "refs/heads/$SFR_BRANCH")"
assert_eq "the subject is fixed and carries the task" \
  "chore: save the unfinished work of a failed run [DE-900]" "$(printf '%s\n' "$SFR_MESSAGE" | head -1)"
assert_contains "the body names the stage" "$SFR_MESSAGE" "failed at the verify stage"
assert_contains "says the hooks were skipped" "$SFR_MESSAGE" "skipped the project's hooks"
assert_contains "and carries the reason verbatim" "$SFR_MESSAGE" "GET /notes has no unread filter yet"

# Nothing left uncommitted: an empty commit, so the pushed branch still says why.
SFR_EMPTY="$(printf 'Nothing to save: the dev agent stopped at step 1.\n' \
  | (cd "$SFR_REPO" && bash "$PLUGIN_SCRIPTS/save-failed-run.sh" --json --task DE-900 --stage dev \
       --dir "$SFR_TREE" --reason-file - 2>/dev/null))"
assert_eq "a clean worktree still gets the commit" "0" "$(printf '%s' "$SFR_EMPTY" | jq -r '.FILES')"
assert_contains "carrying the reason read from stdin" \
  "$(git -C "$SFR_REPO" log -1 --format=%B "refs/heads/$SFR_BRANCH")" "the dev agent stopped at step 1"

# A remote branch that moved on is reported, never overwritten: the remote is
# moved to a commit of its own, written with plumbing on the bare repository.
# The bare repository has no identity of its own, and a CI runner has none to
# guess (macOS derives one from the account): without it commit-tree fails, the
# remote never diverges and the push succeeds — so the identity is given here,
# and an empty commit is a failure of the setup, not a pass.
SFR_OTHER="$(git -C "$SFR_REMOTE" -c user.name=Test -c user.email=test@example.com \
  commit-tree "$SFR_BEFORE^{tree}" -p "$SFR_BEFORE" -m "other")"
assert_eq "the remote is moved on by a commit of its own" "true" "$([ -n "$SFR_OTHER" ] && echo true || echo false)"
git -C "$SFR_REMOTE" update-ref "refs/heads/$SFR_BRANCH" "$SFR_OTHER"
SFR_REJECTED="$(sfr --task DE-900 --stage verify --reason-file "$SFR_REASON")"
assert_eq "a diverged remote is not forced: exit 4" "4" \
  "$(sfr_exit --task DE-900 --stage verify --reason-file "$SFR_REASON")"
assert_eq "the commit is still saved" "true" "$(printf '%s' "$SFR_REJECTED" | jq -r '.SAVED')"
assert_eq "not pushed" "false" "$(printf '%s' "$SFR_REJECTED" | jq -r '.PUSHED')"
assert_eq "with the push's own error" "true" \
  "$([ -n "$(printf '%s' "$SFR_REJECTED" | jq -r '.PUSH_ERROR')" ] && echo true || echo false)"
assert_eq "and the remote untouched" "$SFR_OTHER" "$(sfr_remote_tip "$SFR_BRANCH")"

# 2 — a branch with no worktree (the run broke after the dev agent's worktree
# was removed): an empty commit without a checkout.
SFR_BARE_BRANCH="feat/DE-910_bare-branch"
git -C "$SFR_REPO" branch "$SFR_BARE_BRANCH" "$SFR_BEFORE"
SFR_CHECKOUT_BEFORE="$(git -C "$SFR_REPO" symbolic-ref --short HEAD)"
SFR_BARE="$(sfr --task DE-910 --stage broken --reason-file "$SFR_REASON")"
assert_eq "a branch with no worktree is saved" "true" "$(printf '%s' "$SFR_BARE" | jq -r '.SAVED')"
assert_eq "with no worktree named" "" "$(printf '%s' "$SFR_BARE" | jq -r '.WORKTREE')"
assert_eq "on top of the branch" "$SFR_BEFORE" "$(git -C "$SFR_REPO" rev-parse "refs/heads/$SFR_BARE_BRANCH^")"
assert_eq "the session's checkout never moves" "$SFR_CHECKOUT_BEFORE" "$(git -C "$SFR_REPO" symbolic-ref --short HEAD)"
assert_eq "and it is pushed" "true" "$(printf '%s' "$SFR_BARE" | jq -r '.PUSHED')"
assert_contains "a broken run says so" "$(git -C "$SFR_REPO" log -1 --format=%B "refs/heads/$SFR_BARE_BRANCH")" \
  "failed at the broken stage"

# 3 — no branch at all, only the spec the run wrote: a branch of its own.
SFR_SPEC="$WORK_DIR/save-failed-run-spec.md"
printf '# DE-920 spec\n\n- REQ-1: the filter shows unread notes only.\n' > "$SFR_SPEC"
SFR_FROM_SPEC="$(TMPDIR="$WORK_DIR" sfr --task DE-920 --stage dev --reason-file "$SFR_REASON" \
  --spec-file "$SFR_SPEC" --spec-path .specs/DE-920-unread-filter.md --base "$SFR_BEFORE" \
  --title "unread filter" --type feat)"
SFR_SPEC_BRANCH="$(printf '%s' "$SFR_FROM_SPEC" | jq -r '.BRANCH')"
assert_eq "with only a spec, a branch is created" "true" "$(printf '%s' "$SFR_FROM_SPEC" | jq -r '.CREATED')"
assert_contains "named for the task" "$SFR_SPEC_BRANCH" "DE-920"
assert_eq "holding the spec" "$(cat "$SFR_SPEC")" \
  "$(git -C "$SFR_REPO" show "refs/heads/$SFR_SPEC_BRANCH:.specs/DE-920-unread-filter.md" 2>/dev/null)"
assert_eq "forked from --base" "$SFR_BEFORE" "$(git -C "$SFR_REPO" rev-parse "refs/heads/$SFR_SPEC_BRANCH^")"
assert_eq "and pushed" "true" "$(printf '%s' "$SFR_FROM_SPEC" | jq -r '.PUSHED')"
assert_eq "the session's checkout still never moved" "$SFR_CHECKOUT_BEFORE" "$(git -C "$SFR_REPO" symbolic-ref --short HEAD)"
assert_eq "a spec path outside the repository is a usage error" "1" \
  "$(sfr_exit --task DE-921 --stage dev --reason-file "$SFR_REASON" --spec-file "$SFR_SPEC" \
     --spec-path ../escape.md --base "$SFR_BEFORE" --title "x")"

unset CLAUDE_CODE_REMOTE

# The exception lives in the script only: the gate still refuses the bypass
# when a model types it.
assert_contains "the settings template still denies --no-verify" \
  "$(cat "$REPO_ROOT/templates/dev-setup/.claude/settings.json")" '"Bash(git commit *--no-verify*)"'
SFR_OUTCOMES=$(sed -n '/^## failed/,/^## ready-for-mr/p' "$REPO_ROOT/templates/dev-setup/.claude/reference/run-outcomes.md")
assert_contains "a failed cloud run is saved through it" "$SFR_OUTCOMES" "save-failed-run.sh"
assert_contains "and its push result reaches the board" "$SFR_OUTCOMES" "PUSH_ERROR"
assert_contains "the workflow hands a branchless spec over" \
  "$(cat "$REPO_ROOT/templates/dev-setup/.claude/workflows/auto-sdd-run.js")" "markdown: draft.specMarkdown"
assert_eq "the manifest ships it" "true" \
  "$(jq -r '.plugin_scripts | index("save-failed-run.sh") != null' "$REPO_ROOT/templates/dev-setup/manifest.json")"
assert_eq "the AGENTS.md script table lists it with its keys" "true" \
  "$(grep -E '^\| `save-failed-run\.sh' "$REPO_ROOT/AGENTS.md" | grep -q 'PUSHED' && echo true || echo false)"

echo ""
echo "── frontmatter parseability ──"

# A `: ` inside an unquoted YAML scalar does not parse, and the failure is
# silent in the worst way: the skill loads with *empty* metadata, so
# `user-invocable`, `disable-model-invocation` and `allowed-tools` are all
# dropped and nothing says so. `claude plugin validate` catches it on dist/,
# but only on a recent enough CLI and never on the meta-repo's own skills —
# so it is pinned here, where a plain grep is enough.
FM_COLON=""
while IFS= read -r SKILL_MD; do
  [ -f "$SKILL_MD" ] || continue
  [ "$(head -1 "$SKILL_MD")" = "---" ] || continue
  if sed -n '2,/^---$/p' "$SKILL_MD" \
     | grep -qE '^[a-zA-Z_-]+:[[:space:]]+[^"'"'"'|>].*:[[:space:]]'; then
    FM_COLON="$FM_COLON ${SKILL_MD#"$REPO_ROOT"/}"
  fi
done <<EOF
$(find "$REPO_ROOT/templates" "$REPO_ROOT/shared" "$REPO_ROOT/.claude" \
    -name 'SKILL.md' -o -name '*.md' -path '*/agents/*' 2>/dev/null | LC_ALL=C sort)
EOF
assert_eq "no unquoted colon breaks a frontmatter scalar" "" "${FM_COLON# }"

# ═══════════════════════════════════════════════════════════════════════════════
# 18. auto-dev: the headless run — its workflow and its four scripts
# ═══════════════════════════════════════════════════════════════════════════════
#
# auto-dev is auto-sdd with the cost taken out, for a run nobody watches. What
# is pinned is where the cost went: which agents a run launches on which model
# and effort, when the Challenge is skipped, that the reviewer and the
# developer start from the context pack, and that the scripts that replace the
# model around the run — the arguments, the board, the report, the repository
# choice — decide the same way every time. No network: curl is a stub.

echo ""
echo "── auto-dev-run.js (the headless workflow) ──"

AUTO_DEV="$REPO_ROOT/templates/dev-setup/.claude/workflows/auto-dev-run.js"

if [ ! -f "$AUTO_DEV" ]; then
  fail "the auto-dev workflow script exists" "$AUTO_DEV not found"
elif command -v node >/dev/null 2>&1 && [ -f "$WORK_DIR/workflow-parse.cjs" ]; then
  if WF_META="$(node "$WORK_DIR/workflow-parse.cjs" "$AUTO_DEV" 2>&1)"; then
    pass "the script compiles the way the harness compiles it"
    assert_eq "meta.name is the name the launcher calls" \
      "auto-dev-run" "$(printf '%s' "$WF_META" | jq -r '.name')"
    assert_contains "and the launcher calls exactly that name" \
      "$(cat "$TEMPLATE_ROOT/.claude/skills/auto-dev/SKILL.md")" '"name": "dev-setup:auto-dev-run"'
    assert_eq "the four phases are declared in order" \
      "Spec Challenge Dev Verify" "$(printf '%s' "$WF_META" | jq -r '.phases | join(" ")')"
  else
    fail "the script compiles the way the harness compiles it" "$WF_META"
  fi

  cat > "$WORK_DIR/auto-dev-sim.cjs" <<'NODEJS'
// Runs auto-dev-run.js with stubbed agents. argv[3] is the scenario: the spec's
// size (`reqs`, `steps`) and what the reviewer does (`review`: ok, propose,
// dead). argv[4] overrides the launch arguments.
const fs = require('fs');
const vm = require('vm');

const src = fs.readFileSync(process.argv[2], 'utf8');
const meta = src.match(/^export const meta = \{[\s\S]*?\n\}\n/);
const scenario = JSON.parse(process.argv[3] || '{}');
const overrides = process.argv[4] ? JSON.parse(process.argv[4]) : {};
const calls = [];
const opts = {};
const prompts = {};
const reqs = Array.from({ length: scenario.reqs || 1 }, (_, i) => ({ id: 'REQ-' + (i + 1), statement: 's', test: 't' }));
const spec = {
  slug: 'sim', specMarkdown: '# spec', reqs, planSteps: Array(scenario.steps || 1).fill('a step'),
  contextPack: [{ path: 'src/greeting.ts', kind: 'file', why: 'the component' }],
  deviations: [], toConfirm: [],
};

async function agent(prompt, o) {
  calls.push(o.label);
  opts[o.label] = o;
  prompts[o.label.split(':')[0]] = prompt;
  if (o.label.startsWith('spec:')) return spec;
  if (o.label.startsWith('challenge:')) {
    if (scenario.review === 'dead') return null;
    if (scenario.review === 'propose') {
      return { lenses: [
        { lens: 'simpler', satisfied: false, reason: 'r', suggestion: 's', grounds: 'an ADR' },
        { lens: 'scope', satisfied: true, reason: 'checked' },
      ] };
    }
    return { lenses: ['simpler', 'scope', 'testable'].map((lens) => ({ lens, satisfied: true, reason: 'checked' })) };
  }
  if (o.label.startsWith('revise:')) {
    return Object.assign({}, spec, { responses: [{ lens: 'simpler', applied: true, note: 'done' }] });
  }
  if (o.label.startsWith('dev:')) {
    return { repoPath: '/repo', branch: 'feat/DE-1_x', specPath: '.specs/DE-1-sim.md', commits: ['feat: x [DE-1]'],
      mr: { summary: 's', description: 'd', howToTest: { terminal: [], app: [] } } };
  }
  if (o.label.startsWith('verify:')) {
    return scenario.verify || { done: true, lint: 'passed', typecheck: 'absent', test: 'passed', output: 'green', reason: '' };
  }
  return null;
}

const context = {
  args: Object.assign({
    taskId: 'DE-1', title: 'T', taskFile: '/out/task.md', pluginRoot: '/plugin', baseBranch: 'origin/next',
    stack: { lint: 'make lint', typecheck: '', test: 'make test' },
  }, overrides),
  agent,
  parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
  phase() {},
  log() {},
};
vm.runInNewContext('(async () => {' + src.slice(meta[0].length) + '})()', context).then((out) => {
  console.log(JSON.stringify({
    status: out.status,
    stage: out.stage || '',
    agents: calls.map((l) => l.split(':')[0]).join(','),
    models: calls.map((l) => opts[l].model).join(','),
    efforts: calls.map((l) => opts[l].effort).join(','),
    isolated: calls.some((l) => opts[l].isolation),
    skipped: out.challenge ? out.challenge.skipped : '',
    unchecked: (out.unchecked || []).join(','),
    applied: (out.applied || []).map((a) => a.lens).join(','),
    reviewerPack: (prompts.challenge || '').includes('src/greeting.ts')
      && (prompts.challenge || '').includes('Do not search the repository'),
    devPack: (prompts.dev || '').includes('src/greeting.ts'),
    devOneCommit: (prompts.dev || '').includes('one commit'),
    devCommitScript: (prompts.dev || '').includes('/scripts/auto-dev-commit.sh'),
    devNoWorktree: !(prompts.dev || '').includes('worktree'),
    taskFile: (prompts.spec || '').includes('/out/task.md'),
    mr: Boolean(out.mr),
    verifyWaits: (prompts.verify || '').includes('/plugin/scripts/auto-dev-checks.sh" --task DE-1 --json --wait'),
    reason: out.reason || '',
    ran: (out.ran || []).map((r) => r.command + '=' + r.ok).join(','),
    unverified: (out.unverified || []).map((u) => u.kind).join(','),
  }));
});
NODEJS

  dsim() { node "$WORK_DIR/auto-dev-sim.cjs" "$AUTO_DEV" "$1" ${2:+"$2"} 2>&1; }
  dfield() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

  SIM=$(dsim '{}')
  assert_eq "a small task goes from the spec to Dev: no reviewer, no revision" \
    "ready-for-mr spec,dev,verify" "$(dfield "$SIM" status) $(dfield "$SIM" agents)"
  assert_contains "and the result says why the Challenge was skipped" "$(dfield "$SIM" skipped)" "small task"
  assert_eq "the spec agent reads the task from its file" "true" "$(dfield "$SIM" taskFile)"
  assert_eq "Dev works in the checkout, never in a worktree" "false true" \
    "$(dfield "$SIM" isolated) $(dfield "$SIM" devNoWorktree)"
  assert_eq "Dev starts from the context pack and commits once" "true true" \
    "$(dfield "$SIM" devPack) $(dfield "$SIM" devOneCommit)"
  assert_eq "the outcome carries the merge request text" "true" "$(dfield "$SIM" mr)"
  assert_eq "with every command runnable, Dev commits with git and the gate runs" "false" \
    "$(dfield "$SIM" devCommitScript)"
  SIM=$(dsim '{}' '{"unavailable":["test"],"unavailableReason":"test: `make` is not installed"}')
  assert_eq "with one unavailable, Dev commits through auto-dev-commit.sh: the gate would run it" "true" \
    "$(dfield "$SIM" devCommitScript)"

  # Verify copies what auto-dev-checks.sh answers, and the workflow decides: a
  # check with no verdict is never a pass (DE-17941: a 13-minute suite moved to
  # the background was reported red a minute later).
  SIM=$(dsim '{}')
  assert_eq "Verify starts the checks through the script and waits on its --wait call" "true" \
    "$(dfield "$SIM" verifyWaits)"
  assert_eq "a green verdict lists what ran" "make lint=true,make test=true" "$(dfield "$SIM" ran)"
  SIM=$(dsim '{"verify":{"done":false,"lint":"passed","typecheck":"absent","test":"running","output":"","reason":""}}')
  assert_eq "an answer before the end is no verdict: failed at verify" "failed verify" \
    "$(dfield "$SIM" status) $(dfield "$SIM" stage)"
  assert_contains "naming the check still running" "$(dfield "$SIM" reason)" "test running"
  SIM=$(dsim '{"verify":{"done":true,"lint":"passed","typecheck":"absent","test":"stopped","output":"","reason":"the run stopped before its end"}}')
  assert_contains "a stopped run fails with the script's reason" "$(dfield "$SIM" reason)" "stopped before its end"
  SIM=$(dsim '{"verify":{"done":true,"lint":"failed","typecheck":"absent","test":"passed","output":"lint red","reason":""}}')
  assert_eq "a red command fails the run, with what ran" "failed make lint=false,make test=true" \
    "$(dfield "$SIM" status) $(dfield "$SIM" ran)"
  SIM=$(dsim '{"verify":{"done":true,"lint":"passed","typecheck":"absent","test":"not-found","output":"","reason":""}}')
  assert_eq "a command that could not start is unverified, not red" "ready-for-mr test" \
    "$(dfield "$SIM" status) $(dfield "$SIM" unverified)"

  SIM=$(dsim '{"reqs":4,"steps":2}')
  assert_eq "over the threshold, one reviewer looks at the spec" \
    "spec,challenge,dev,verify" "$(dfield "$SIM" agents)"
  assert_eq "it reads only the spec and the context pack" "true" "$(dfield "$SIM" reviewerPack)"
  SIM=$(dsim '{"reqs":3,"steps":4}')
  assert_eq "more steps than the threshold is enough to review" \
    "spec,challenge,dev,verify" "$(dfield "$SIM" agents)"
  SIM=$(dsim '{}' '{"challenge":"always"}')
  assert_eq "challenge: always reviews a small task too" "spec,challenge,dev,verify" "$(dfield "$SIM" agents)"
  SIM=$(dsim '{"reqs":9,"steps":9}' '{"challenge":"never"}')
  assert_eq "challenge: never skips a large one" "spec,dev,verify challenge: never" \
    "$(dfield "$SIM" agents) $(dfield "$SIM" skipped)"

  SIM=$(dsim '{"reqs":4,"review":"propose"}')
  assert_eq "a proposal earns one revision" "spec,challenge,revise,dev,verify" "$(dfield "$SIM" agents)"
  assert_eq "opus writes, reviews, revises and develops; haiku runs the commands" \
    "opus,opus,opus,opus,haiku" "$(dfield "$SIM" models)"
  assert_eq "high on spec and dev, medium on the Challenge, low on Verify" \
    "high,medium,medium,high,low" "$(dfield "$SIM" efforts)"
  assert_eq "an applied proposal is reported as applied" "simpler" "$(dfield "$SIM" applied)"
  assert_eq "a focus the reviewer did not answer is unchecked" "testable" "$(dfield "$SIM" unchecked)"

  SIM=$(dsim '{"reqs":4,"review":"dead"}')
  assert_eq "a reviewer that dies twice leaves every focus unchecked, and the run goes on" \
    "ready-for-mr spec,challenge,challenge,dev,verify simpler,scope,testable" \
    "$(dfield "$SIM" status) $(dfield "$SIM" agents) $(dfield "$SIM" unchecked)"

  SIM=$(dsim '{}' '{"taskFile":""}')
  assert_eq "no task file ends at intake, before any agent" "failed intake " \
    "$(dfield "$SIM" status) $(dfield "$SIM" stage) $(dfield "$SIM" agents)"
  SIM=$(dsim '{}' '{"challenge":"sometimes"}')
  assert_eq "an unknown challenge mode ends at intake" "failed intake" \
    "$(dfield "$SIM" status) $(dfield "$SIM" stage)"
else
  printf '%s  skip%s  node not found: the auto-dev workflow tests need it\n' "$DIM" "$NC"
fi

if [ -f "$AUTO_DEV" ]; then
  assert_eq "the headless workflow pushes nothing, opens nothing, touches no board" "" \
    "$(grep -n -E "git push|gh pr create|glab mr create|mcp__clickup" "$AUTO_DEV" || true)"
  assert_eq "nothing in it goes above high effort" "0" "$(grep -cE "effort: '(xhigh|max)'" "$AUTO_DEV")"
  assert_contains "the task id is validated before it reaches a prompt" "$(cat "$AUTO_DEV")" "TASK_ID_SHAPE"
  assert_contains "the Challenge threshold is a constant" "$(cat "$AUTO_DEV")" "SMALL_TASK = { reqs: 3, steps: 3 }"
fi

echo ""
echo "── auto-dev scripts (arguments, board, report, selection) ──"

AD_DIR="$WORK_DIR/auto-dev"
AD_REPO="$AD_DIR/repo"
AD_OUT="$AD_DIR/out"
AD_BIN="$AD_DIR/bin"
AD_LOG="$AD_DIR/curl.log"
mkdir -p "$AD_REPO" "$AD_OUT" "$AD_BIN"
(
  cd "$AD_REPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p .claude .github
  echo '{"lint":"make lint","typecheck":null,"test":"make test"}' > .claude/quality-commands.json
  cp "$REPO_ROOT/templates/dev-setup/boilerplate/merge-request.json" .claude/merge-request.json
  printf '## Description\n\n<!-- what -->\n\n## Screenshots\n\nkeep me\n\n## How was it tested?\n\n- [ ] Test A\n\n## Checklist:\n\n- [ ] done\n' \
    > .github/PULL_REQUEST_TEMPLATE.md
  jq '.language = "en"' .claude/merge-request.json > .claude/mr.tmp && mv .claude/mr.tmp .claude/merge-request.json
  git add -A && git commit --quiet -m init && git branch -M main && git branch next
) >/dev/null 2>&1

# The ClickUp API, stubbed: it logs every call with whether the token came in
# through the config on stdin, and whether it leaked into the arguments. DE-8
# is in BACKLOG; a list with no CODE REVIEW refuses that status.
cat > "$AD_BIN/curl" <<'STUB'
#!/usr/bin/env bash
cfg=$(cat)
url="${*: -1}"; method=GET; prev=""; body=""
for a in "$@"; do
  [ "$prev" = "--request" ] && method="$a"
  [ "$prev" = "--data-binary" ] && body="$(tr '\n' ' ' < "${a#@}")"
  prev="$a"
done
leak=no; case "$*" in *pk_secret*) leak=yes ;; esac
printf '%s %s stdin-token=%s argv-token=%s body=%s\n' "$method" "$url" \
  "$(printf '%s' "$cfg" | grep -c 'Authorization: pk_secret')" "$leak" "$body" >> "$CURL_LOG"
task() { printf '{"id":"86x%s","custom_id":"%s","name":"Add a greeting","markdown_description":"Say hello","status":{"status":"%s"},"priority":{"priority":"high"},"url":"https://app.clickup.com/t/86x","team_id":"42"}\n200' "$1" "$1" "$2"; }
case "$method $url" in
  "GET "*/task/DE-7*) task DE-7 sprint ;;
  "GET "*/task/DE-8*) task DE-8 backlog ;;
  "PUT "*)
    if [ -n "${NO_CODE_REVIEW:-}" ] && printf '%s' "$body" | grep -q 'CODE REVIEW'; then
      printf '{"err":"Status not found"}\n400'
    else
      printf '{}\n200'
    fi ;;
  "POST "*) printf '{}\n200' ;;
  *) printf '{"err":"not found"}\n404' ;;
esac
STUB
chmod +x "$AD_BIN/curl"

ad() {
  local script="$1"; shift
  (cd "$AD_REPO" && PATH="$AD_BIN:$PATH" CURL_LOG="$AD_LOG" CLICKUP_API_TOKEN=pk_secret CLICKUP_TEAM_ID=42 \
    CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${AD_CEILING-0}" bash "$PLUGIN_SCRIPTS/$script" "$@" --json 2>/dev/null)
}

jq -n --arg o "$AD_OUT" '{taskId: "DE-7", baseBranch: "next", outputDir: $o, runId: "r1",
  tracker: "none", task: {title: "Add a greeting", description: "Say \"hello\"\nTwo lines.", priority: "high"},
  stack: {lint: "make lint", typecheck: "", test: "make test"}}' > "$AD_DIR/args.json"
OUT="$(ad auto-dev-args.sh --args "$AD_DIR/args.json")"
assert_eq "auto-dev-args accepts a complete args file" "true" "$(printf '%s' "$OUT" | jq -r .ACCEPTED)"
assert_eq "it writes the task text verbatim to the file the agents read" \
  "$(printf '# Add a greeting\n\nSay "hello"\nTwo lines.')" "$(cat "$AD_OUT/task.md")"
assert_eq "the workflow arguments carry the file, not the text" "$AD_OUT/task.md false" \
  "$(jq -r '.taskFile + " " + (has("description") | tostring)' "$AD_OUT/workflow-args.json")"
assert_eq "and the merge request language from mr-meta" "en" "$(jq -r .language "$AD_OUT/workflow-args.json")"

jq --arg o "$AD_REPO/out" '.outputDir = $o' "$AD_DIR/args.json" > "$AD_DIR/args-inside.json"
OUT="$(ad auto-dev-args.sh --args "$AD_DIR/args-inside.json")"
assert_contains "an output directory inside the repository is refused: the commit would carry it" \
  "$(printf '%s' "$OUT" | jq -r .REASON)" "inside the repository"
jq 'del(.baseBranch)' "$AD_DIR/args.json" > "$AD_DIR/args-nobase.json"
OUT="$(ad auto-dev-args.sh --args "$AD_DIR/args-nobase.json")"
assert_contains "no base and no selection: refused, never guessed" "$(printf '%s' "$OUT" | jq -r .REASON)" "no base branch"
assert_eq "and the refusal is a result the runner reads" "failed intake" \
  "$(jq -r '.status + " " + .stage' "$AD_OUT/result.json")"
OUT="$(AD_CEILING="" ad auto-dev-args.sh --args "$AD_DIR/args.json")"
assert_contains "without the background-wait ceiling lifted, the run is refused at intake" \
  "$(printf '%s' "$OUT" | jq -r .REASON)" "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS is not set"
assert_eq "and the runner reads it as a failed intake" "failed intake" \
  "$(jq -r '.status + " " + .stage' "$AD_OUT/result.json")"
OUT="$(AD_CEILING="forever" ad auto-dev-args.sh --args "$AD_DIR/args.json")"
assert_contains "a ceiling that is not milliseconds is refused too" "$(printf '%s' "$OUT" | jq -r .REASON)" "it takes milliseconds"
OUT="$(ad auto-dev-args.sh --args "$AD_DIR/args.json")"
assert_eq "with it set, the same args are accepted again" "true" "$(printf '%s' "$OUT" | jq -r .ACCEPTED)"

: > "$AD_LOG"
OUT="$(ad auto-dev-clickup.sh --task DE-7 --read)"
assert_eq "the board read returns the task" "Add a greeting|Say hello|SPRINT|high" \
  "$(printf '%s' "$OUT" | jq -r '[.NAME, .DESCRIPTION, .STATUS, .PRIORITY] | join("|")')"
assert_eq "a custom id is resolved within the workspace" "1" \
  "$(grep -c 'custom_task_ids=true&team_id=42' "$AD_LOG")"
OUT="$(ad auto-dev-clickup.sh --task DE-8 --start)"
assert_contains "a BACKLOG task is refused before the board moves" "$(printf '%s' "$OUT" | jq -r .REASON)" "BACKLOG"
assert_eq "no PUT reached the board for it" "0" "$(grep -c '^PUT' "$AD_LOG")"
OUT="$(ad auto-dev-clickup.sh --task DE-7 --start)"
assert_eq "a SPRINT task moves to IN PROGRESS" "IN PROGRESS" "$(printf '%s' "$OUT" | jq -r .MOVED_TO)"
assert_eq "the token travels on stdin, every call" "$(grep -c . "$AD_LOG")" "$(grep -c 'stdin-token=1' "$AD_LOG")"
assert_eq "and never in curl's arguments" "0" "$(grep -c 'argv-token=yes' "$AD_LOG")"
OUT="$(cd "$AD_REPO" && PATH="$AD_BIN:$PATH" bash "$PLUGIN_SCRIPTS/auto-dev-clickup.sh" --task DE-7 --read --json 2>/dev/null)"
assert_contains "no token in the environment: refused" "$(printf '%s' "$OUT" | jq -r .REASON)" "CLICKUP_API_TOKEN"

# The report, on a ready-for-mr outcome as the launcher saves it.
(
  cd "$AD_REPO" || exit 1
  git checkout --quiet -b "feat/DE-7_add-a-greeting"
  echo 'export const greeting = "hello"' > greeting.ts
  git add -A && git commit --quiet -m "feat(greet): the commit git holds [DE-7]"
) >/dev/null 2>&1
cat > "$AD_OUT/outcome.json" <<'JSON'
{"status":"ready-for-mr","taskId":"DE-7","branch":"feat/DE-7_add-a-greeting","baseBranch":"next",
 "repoPath":"/repo","spec":{"path":".specs/DE-7-greeting.md","reqs":[{"id":"REQ-1","statement":"s","test":"t"}]},
 "contextPack":[],"challenge":{"mode":"auto","ran":true,"skipped":"","applied":1,"open":1},
 "commits":["feat(greet): add a greeting [DE-7]"],"filesChanged":["src/greeting.ts"],
 "mr":{"summary":"Add a greeting","description":"Adds the greeting.","howToTest":{"terminal":["make test"],"app":["Open /hello"]}},
 "openPoints":[{"lens":"scope","reason":"too wide","suggestion":"drop REQ-2","grounds":"the task","answer":""}],
 "applied":[{"lens":"simpler"}],"deviations":[],"toConfirm":["the greeting is in English"],"unchecked":[],
 "notes":"","output":"3 passed","ran":[{"command":"make test","ok":true}],"absent":["typecheck"],
 "unverified":[{"kind":"lint","command":"make lint","reason":"no make here"}]}
JSON
OUT="$(ad auto-dev-report.sh --outcome "$AD_OUT/outcome.json" --launch "$AD_OUT/launch.json")"
assert_eq "the report titles the merge request through mr-meta" "Feat: Add a greeting [DE-7]" \
  "$(jq -r .mr.title "$AD_OUT/result.json")"
assert_eq "with its labels" "Type: Feature,Priority: High,State: Pending" \
  "$(jq -r '.mr.labels | join(",")' "$AD_OUT/result.json")"
assert_eq "result.json carries the checks and the run's identity" "3 passed r1 DE-7" \
  "$(jq -r '[.checks.output, .runId, .taskId] | join(" ")' "$AD_OUT/result.json")"
BODY="$(cat "$AD_OUT/pr-body.md")"
assert_eq "what nobody verified or confirmed opens the body" "## Not verified" "$(head -1 "$AD_OUT/pr-body.md")"
for PART in "## To confirm" "## Open points" "proposals applied to the spec: 1" "keep me" "- [ ] done" \
            "Adds the greeting." "**Spec:** \`.specs/DE-7-greeting.md\`" "make test" "1. Open /hello" "3 passed"; do
  assert_contains "the body carries: $PART" "$BODY" "$PART"
done
assert_eq "the template's own test placeholder is replaced, not kept" "false" \
  "$(printf '%s' "$BODY" | grep -q 'Test A' && echo true || echo false)"
assert_eq "the commits are the ones git holds, not the ones the agent reported" \
  '["feat(greet): the commit git holds [DE-7]"]' "$(jq -c .commits "$AD_OUT/result.json")"

# The commit gate ran out of time on this branch: its note opens the body.
AD_NOTE="$(cd "$AD_REPO" && . "$PLUGIN_SCRIPTS/common.sh" && gate_note_file "feat/DE-7_add-a-greeting")"
mkdir -p "$(dirname "$AD_NOTE")"
printf '%s\n' '2026-10-28T15:35:06Z — tests (`make test`, stopped): not finished in 19 min' > "$AD_NOTE"
ad auto-dev-report.sh --outcome "$AD_OUT/outcome.json" --launch "$AD_OUT/launch.json" >/dev/null
assert_eq "a commit the gate let through unchecked opens the body" "## Tests not completed at commit" \
  "$(head -1 "$AD_OUT/pr-body.md")"
assert_contains "with the gate's note" "$(cat "$AD_OUT/pr-body.md")" "not finished in 19 min"
assert_eq "and result.json carries it" "1" "$(jq '.mr.uncheckedAtCommit | length' "$AD_OUT/result.json")"
rm -f "$AD_NOTE"

printf 'not json at all' > "$AD_OUT/broken.json"
ad auto-dev-report.sh --outcome "$AD_OUT/broken.json" --launch "$AD_OUT/launch.json" >/dev/null
assert_eq "an outcome that is neither is a run that broke" "failed broken" \
  "$(jq -r '.status + " " + .stage' "$AD_OUT/result.json")"
assert_eq "a failed run on a clean checkout leaves no patch" "" "$(jq -r .patchFile "$AD_OUT/result.json")"

# ad-dry-10281136: the gate refused the commit, the work stayed staged, and the
# outcome still said ready-for-mr.
(
  cd "$AD_REPO" || exit 1
  git checkout --quiet -b "feat/DE-9_not-committed" next
  echo 'staged' > staged.ts && git add staged.ts
  echo 'untracked' > untracked.ts
) >/dev/null 2>&1
jq '.branch = "feat/DE-9_not-committed" | .taskId = "DE-9"' "$AD_OUT/outcome.json" > "$AD_DIR/uncommitted.json"
mkdir -p "$AD_DIR/uncommitted" && cp "$AD_DIR/uncommitted.json" "$AD_DIR/uncommitted/outcome.json"
OUT="$(ad auto-dev-report.sh --outcome "$AD_DIR/uncommitted/outcome.json" --launch "$AD_OUT/launch.json")"
assert_eq "ready-for-mr with no commit over the base is a failed run at dev" "failed dev" \
  "$(jq -r '.status + " " + .stage' "$AD_DIR/uncommitted/result.json")"
assert_contains "saying the work was not committed" "$(jq -r .reason "$AD_DIR/uncommitted/result.json")" \
  "holds no commit over next"
assert_eq "and no merge request body is written for it" "" "$(printf '%s' "$OUT" | jq -r .BODY_FILE)"
assert_eq "its work, staged and untracked, is saved as a patch" "staged.ts untracked.ts" \
  "$(grep '^diff --git' "$AD_DIR/uncommitted/changes.patch" | sed 's#.* b/##' | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "which applies on the commit result.json names" "$(cd "$AD_REPO" && git rev-parse next)" \
  "$(jq -r .patchBase "$AD_DIR/uncommitted/result.json")"
assert_eq "and the checkout is left as the run left it" "A  staged.ts|?? untracked.ts" \
  "$(cd "$AD_REPO" && git status --porcelain | tr '\n' '|' | sed 's/|$//')"
(
  cd "$AD_REPO" || exit 1
  git reset --quiet && rm -f staged.ts untracked.ts
  git checkout --quiet "feat/DE-7_add-a-greeting"
) >/dev/null 2>&1

# Usage from transcripts, then reconciled with claude -p's per-model totals.
AD_CFG="$AD_DIR/claude"
mkdir -p "$AD_CFG/projects/p/sid-1/subagents"
cat > "$AD_CFG/projects/p/sid-1.jsonl" <<'JSONL'
{"type":"user","message":{"content":"/dev-setup:auto-dev --args x"}}
{"type":"assistant","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":2}}}
{"type":"assistant","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":7}}}
JSONL
cat > "$AD_CFG/projects/p/sid-1/subagents/agent-a.jsonl" <<'JSONL'
{"type":"user","message":{"content":[{"type":"text","text":"You are writing the technical spec for one task"}]}}
{"type":"assistant","message":{"id":"s1","model":"claude-opus-5-5","usage":{"input_tokens":3,"cache_creation_input_tokens":50,"cache_read_input_tokens":500,"output_tokens":10}}}
{"type":"assistant","message":{"id":"s2","model":"claude-opus-5-5","usage":{"input_tokens":3,"cache_creation_input_tokens":50,"cache_read_input_tokens":500,"output_tokens":30}}}
JSONL
cp "$AD_OUT/outcome.json" "$AD_OUT/outcome2.json"
(cd "$AD_REPO" && CLAUDE_CONFIG_DIR="$AD_CFG" bash "$PLUGIN_SCRIPTS/auto-dev-report.sh" \
  --outcome "$AD_OUT/outcome2.json" --launch "$AD_OUT/launch.json" --session sid-1 --json >/dev/null 2>&1)
assert_eq "each step's usage is read from its transcript, a request counted once" "launcher:1:7 spec:2:40" \
  "$(jq -r '.usage.steps | to_entries | map("\(.key):\(.value.calls):\(.value.output)") | join(" ")' "$AD_OUT/result.json")"
assert_eq "and marked as a lower bound" "transcript-lower-bound" "$(jq -r .usage.outputSource "$AD_OUT/result.json")"
echo '{"total_cost_usd":1.5,"modelUsage":{"claude-opus-5-5":{"inputTokens":6,"outputTokens":400,"cacheReadInputTokens":1000,"cacheCreationInputTokens":100},"claude-sonnet-5-5":{"inputTokens":5,"outputTokens":70,"cacheReadInputTokens":1000,"cacheCreationInputTokens":100}}}' \
  > "$AD_OUT/claude.json"
bash "$PLUGIN_SCRIPTS/auto-dev-report.sh" --finalize --result "$AD_OUT/result.json" \
  --claude-result "$AD_OUT/claude.json" --json >/dev/null 2>&1
assert_eq "--finalize spreads each model's exact output over its steps" "launcher:70 spec:400 470 reconciled" \
  "$(jq -r '(.usage.steps | to_entries | map("\(.key):\(.value.output)") | join(" ")) + " \(.usage.total.output) \(.usage.outputSource)"' "$AD_OUT/result.json")"

# The finish: a merge request moves the task to review, a failure to BLOCKED.
: > "$AD_LOG"
cp "$AD_OUT/outcome.json" "$AD_OUT/outcome3.json"
ad auto-dev-report.sh --outcome "$AD_OUT/outcome3.json" --launch "$AD_OUT/launch.json" >/dev/null
OUT="$(ad auto-dev-clickup.sh --task DE-7 --finish --result "$AD_OUT/result.json")"
assert_contains "ready-for-mr without its merge request link is refused" "$(printf '%s' "$OUT" | jq -r .REASON)" "--mr-url"
OUT="$(NO_CODE_REVIEW=1 ad auto-dev-clickup.sh --task DE-7 --finish --result "$AD_OUT/result.json" --mr-url https://example.test/pr/1)"
assert_eq "a list without CODE REVIEW gets IN REVIEW" "IN REVIEW true" \
  "$(printf '%s' "$OUT" | jq -r '.MOVED_TO + " " + .COMMENTED')"
assert_contains "the comment links the merge request" "$(grep '^POST .*comment' "$AD_LOG")" "https://example.test/pr/1"
jq '.status = "failed" | .stage = "verify" | .reason = "the project quality commands did not pass"' \
  "$AD_OUT/result.json" > "$AD_OUT/failed.json"
OUT="$(ad auto-dev-clickup.sh --task DE-7 --finish --result "$AD_OUT/failed.json" --pushed true)"
assert_eq "a failed run moves the task to BLOCKED" "BLOCKED" "$(printf '%s' "$OUT" | jq -r .MOVED_TO)"
assert_contains "with why, and where the branch is" "$(grep '^POST .*comment' "$AD_LOG" | tail -1)" "Branch on origin"

# The board's own names, from the project's .claude/auto-dev.json (setup 7d).
echo '{"status":{"ready":"TODO","in_progress":"DOING","in_review":"IN QA","blocked":"STUCK"}}' \
  > "$AD_REPO/.claude/auto-dev.json"
OUT="$(ad auto-dev-clickup.sh --task DE-7 --finish --result "$AD_OUT/failed.json")"
assert_eq "the project's blocked status is the one the task moves to" "STUCK" "$(printf '%s' "$OUT" | jq -r .MOVED_TO)"
OUT="$(ad auto-dev-clickup.sh --task DE-7 --start)"
assert_eq "and its in-progress status the one the work starts in" "DOING" "$(printf '%s' "$OUT" | jq -r .MOVED_TO)"
rm -f "$AD_REPO/.claude/auto-dev.json"

# The commit of a run with a command this machine cannot start: adtest is not
# installed, adlint is a stub whose verdict LINT_RED sets.
AD_CREPO="$AD_DIR/commit-repo"
AD_CBIN="$AD_DIR/commit-bin"
mkdir -p "$AD_CREPO" "$AD_CBIN"
printf '#!/usr/bin/env bash\necho ran >> "%s/adlint.log"\nif [ -n "${LINT_RED:-}" ]; then echo "lib/a.dart:3 1 problem"; exit 1; fi\necho "no issues"\n' \
  "$AD_DIR" > "$AD_CBIN/adlint"
chmod +x "$AD_CBIN/adlint"
(
  cd "$AD_CREPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p .claude
  echo '{"lint":"adlint","typecheck":null,"test":"adtest","absent":{"typecheck":"Dart has no separate type checker"}}' \
    > .claude/quality-commands.json
  git add -A && git commit --quiet -m init && git branch -M main
) >/dev/null 2>&1
adc() {
  (cd "$AD_CREPO" && PATH="$AD_CBIN:$PATH" bash "$PLUGIN_SCRIPTS/auto-dev-commit.sh" "$@" --json 2>/dev/null)
}

adc --task DE-5 --message "feat: no id" >/dev/null
assert_eq "auto-dev-commit wants the task id in the subject" "1" "$?"
OUT="$(adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_eq "it refuses off the task's branch" "3 false" "$? $(printf '%s' "$OUT" | jq -r .COMMITTED)"
assert_contains "saying which branch it is on" "$(printf '%s' "$OUT" | jq -r .REASON)" "main does not carry DE-5"
(cd "$AD_CREPO" && git checkout --quiet -b "feat/DE-5_add-a") >/dev/null 2>&1
OUT="$(adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_contains "with nothing to commit, it says so" "$(printf '%s' "$OUT" | jq -r .REASON)" "nothing to commit"
echo 'one' > "$AD_CREPO/a.dart"
printf '#!/usr/bin/env bash\necho ok\n' > "$AD_CBIN/adtest" && chmod +x "$AD_CBIN/adtest"
OUT="$(adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_eq "with every command runnable it refuses: git commit and the gate work" "3" "$?"
assert_contains "and says to use them" "$(printf '%s' "$OUT" | jq -r .REASON)" "every declared command can run here"
rm -f "$AD_CBIN/adtest"
mkdir -p "$AD_CREPO/.husky"
OUT="$(adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_contains "with a hook manager it refuses: the project's hooks own the checks" \
  "$(printf '%s' "$OUT" | jq -r .REASON)" "husky"
rmdir "$AD_CREPO/.husky"

: > "$AD_DIR/adlint.log"
OUT="$(LINT_RED=1 adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_eq "a red runnable command refuses the commit" "4 false 0" \
  "$? $(printf '%s' "$OUT" | jq -r .COMMITTED) $(cd "$AD_CREPO" && git rev-list --count main..HEAD)"
assert_contains "with its output, as the gate gives it" "$(printf '%s' "$OUT" | jq -r .OUTPUT)" "1 problem"
OUT="$(adc --task DE-5 --message "feat(a): add a [DE-5]")"
assert_eq "green on what can run: committed, the unavailable one skipped" "0 true lint test" \
  "$? $(printf '%s' "$OUT" | jq -r '.COMMITTED + " " + .RAN + " " + .SKIPPED')"
assert_contains "and the merge request's reason is passed on" "$(printf '%s' "$OUT" | jq -r .UNAVAILABLE_REASON)" "adtest"
assert_eq "the commit carries the subject and the whole working tree" "feat(a): add a [DE-5]|a.dart" \
  "$(cd "$AD_CREPO" && git log -1 --format=%s)|$(cd "$AD_CREPO" && git show --name-only --format= HEAD)"
assert_eq "the lint ran once per attempt, from the repository root" "2" "$(grep -c ran "$AD_DIR/adlint.log")"

echo 'two' >> "$AD_CREPO/a.dart"
mkdir -p "$AD_CREPO/.git/hooks"
printf '#!/usr/bin/env bash\necho "commit-msg hook: subject too long"\nexit 1\n' > "$AD_CREPO/.git/hooks/commit-msg"
chmod +x "$AD_CREPO/.git/hooks/commit-msg"
OUT="$(adc --task DE-5 --message "feat(a): change a [DE-5]")"
assert_eq "the project's git hooks still run: one that refuses stops the commit" "4 false" \
  "$? $(printf '%s' "$OUT" | jq -r .COMMITTED)"
assert_contains "and what it said is in OUTPUT" "$(printf '%s' "$OUT" | jq -r .OUTPUT)" "subject too long"
rm -f "$AD_CREPO/.git/hooks/commit-msg"

GATE_OUT="$(cd "$AD_CREPO" && jq -n --arg c "bash \"$PLUGIN_SCRIPTS/auto-dev-commit.sh\" --json --task DE-5 --message \"feat(a): change a [DE-5]\"" \
  --arg d "$AD_CREPO" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
  | PATH="$AD_CBIN:$PATH" bash "$REPO_ROOT/templates/dev-setup/.claude/hooks/gate-commit.sh" 2>/dev/null)"
assert_eq "the commit gate does not take the script call for a commit" "" "$GATE_OUT"

# The checks of a Verify, run so the agent can wait for them. adklint's verdict
# is KLINT_RED's; adktest sleeps KTEST_SLEEP seconds, the stand-in for a suite
# longer than the Bash call's ceiling.
AD_KREPO="$AD_DIR/checks-repo"
AD_KBIN="$AD_DIR/checks-bin"
mkdir -p "$AD_KREPO" "$AD_KBIN"
printf '#!/usr/bin/env bash\nif [ -n "${KLINT_RED:-}" ]; then echo "lib/a.dart:3 unused import"; exit 1; fi\necho "no issues"\n' \
  > "$AD_KBIN/adklint"
printf '#!/usr/bin/env bash\nsleep "${KTEST_SLEEP:-0}"\necho "00:01 +3: All tests passed!"\n' > "$AD_KBIN/adktest"
chmod +x "$AD_KBIN/adklint" "$AD_KBIN/adktest"
(
  cd "$AD_KREPO" || exit 1
  git_init .
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p .claude
  echo '{"lint":"adklint","typecheck":null,"test":"adktest","absent":{"typecheck":"Dart has no separate type checker"}}' \
    > .claude/quality-commands.json
  git add -A && git commit --quiet -m init && git branch -M main
) >/dev/null 2>&1
adk() {
  (cd "$AD_KREPO" && PATH="$AD_KBIN:$PATH" bash "$PLUGIN_SCRIPTS/auto-dev-checks.sh" "$@" --json 2>/dev/null)
}
kfield() { printf '%s' "$1" | jq -r "$2"; }
AD_KSTATE="$AD_KREPO/.git/dev-setup/auto-dev-checks"

OUT="$(adk --task DE-6 --wait)"
assert_eq "auto-dev-checks: --wait with no run started refuses, and starts nothing" "3 false" \
  "$? $(kfield "$OUT" .DONE)$([ -d "$AD_KSTATE/DE-6" ] && echo ' started')"
assert_contains "saying how to start one" "$(kfield "$OUT" .REASON)" "without --wait"

OUT="$(adk --task DE-6)"
assert_eq "a green run: done, passed, each command's status" "0 true true passed absent passed" \
  "$? $(kfield "$OUT" '[.DONE, .PASSED, .LINT_STATUS, .TYPECHECK_STATUS, .TEST_STATUS] | join(" ")')"
assert_contains "OUTPUT ends on the runner's summary" "$(kfield "$OUT" .OUTPUT)" "All tests passed!"
assert_eq "each command keeps its full log, outside the working tree" "true true" \
  "$([ -f "$(kfield "$OUT" .LOG_DIR)/test.log" ] && echo true) $(cd "$AD_KREPO" && [ -z "$(git status --porcelain)" ] && echo true)"

OUT="$(KLINT_RED=1 adk --task DE-6)"
assert_eq "a red command: exit 4, not passed, and the others still run" "4 false failed passed" \
  "$? $(kfield "$OUT" '[.PASSED, .LINT_STATUS, .TEST_STATUS] | join(" ")')"
assert_contains "with the failure in OUTPUT" "$(kfield "$OUT" .OUTPUT)" "unused import"

# A suite longer than the call: the first call stands for the one the harness
# moved to the background, and goes on by itself.
(KTEST_SLEEP=4 adk --task DE-6 >/dev/null) &
AD_KRUN=$!
sleep 1
OUT="$(adk --task DE-6 --wait --budget 0)"
assert_eq "while it runs, --wait answers not done: exit 5, the test running" "5 false running" \
  "$? $(kfield "$OUT" '[.DONE, .TEST_STATUS] | join(" ")')"
echo 'edit' > "$AD_KREPO/b.dart"
OUT="$(adk --task DE-6)"
assert_eq "a start on another tree refuses while the run is alive" "3" "$?"
assert_contains "and names the wait" "$(kfield "$OUT" .REASON)" "wait for it with --wait"
rm -f "$AD_KREPO/b.dart"
OUT="$(adk --task DE-6 --budget 30)"
assert_eq "a second start on the same tree joins the run instead of a second copy" "0 true passed" \
  "$? $(kfield "$OUT" '[.DONE, .TEST_STATUS] | join(" ")')"
wait "$AD_KRUN"
OUT="$(adk --task DE-6 --wait)"
assert_eq "--wait after the end prints the answer" "0 true" "$? $(kfield "$OUT" .PASSED)"

# A run whose heartbeat stopped: its state, as a killed run leaves it.
mkdir -p "$AD_KSTATE/DE-7"
printf '%s' "$(( $(date +%s) - 3600 ))" > "$AD_KSTATE/DE-7/started"
printf '%s' "$(( $(date +%s) - 3600 ))" > "$AD_KSTATE/DE-7/heartbeat"
printf 'running' > "$AD_KSTATE/DE-7/test.status"
printf 'adktest' > "$AD_KSTATE/DE-7/test.cmd"
OUT="$(adk --task DE-7 --wait --budget 5)"
assert_eq "a run whose heartbeat stopped is no verdict: exit 3, the test stopped" "3 true false stopped" \
  "$? $(kfield "$OUT" '[.DONE, .PASSED, .TEST_STATUS] | join(" ")')"
assert_contains "and REASON says why" "$(kfield "$OUT" .REASON)" "stopped before its end"
adk --task DE-7 >/dev/null
assert_eq "a start over a stopped run runs again" "0 true" "$? $(kfield "$(adk --task DE-7 --wait)" .PASSED)"

assert_contains "the script ships" "$(jq -r '.plugin_scripts | join(" ")' "$TEMPLATE_ROOT/manifest.json")" "auto-dev-checks.sh"

# The selection: three clones, one task.
AD_SEL="$AD_DIR/select"
mkdir -p "$AD_SEL/out"
for NAME in web api mobile; do
  git init --quiet --bare --template="$EMPTY_GIT_TEMPLATE" "$AD_SEL/$NAME.git" >/dev/null 2>&1
  (
    cd "$AD_SEL" || exit 1
    git_init "$NAME"
    cd "$NAME" || exit 1
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "# $NAME" > README.md
    mkdir -p .claude
    [ "$NAME" = mobile ] || echo '{"lint":"make lint"}' > .claude/quality-commands.json
    [ "$NAME" = web ] && echo '{"base_branch":"develop"}' > .claude/auto-dev.json
    git add -A && git commit --quiet -m init && git branch -M main && git branch develop
    git remote add origin "$AD_SEL/$NAME.git"
    git push --quiet origin main develop && git fetch --quiet origin
    git remote set-url origin "https://github.com/acme/$NAME.git"
  ) >/dev/null 2>&1
done
sel_args() {
  jq -n --arg d "$1" --arg o "$AD_SEL/out" --arg s "$AD_SEL" \
    '{taskId: "DE-9", runId: "r9", outputDir: $o, tracker: "none",
      repos: [($s + "/web"), ($s + "/api"), ($s + "/mobile")], task: {title: "T", description: $d}}' \
    > "$AD_SEL/args.json"
}
sel() { ad auto-dev-select.sh --args "$AD_SEL/args.json" "$@"; }

sel_args $'Fix the login.\n**repo:** acme/web'
assert_eq "a repo: line chooses with no model, and the clone's config gives the base" \
  "selected acme/web origin/develop config task-line" \
  "$(sel | jq -r '[.STATUS, .SLUG, .BASE_BRANCH, .BASE_SOURCE, .SOURCE] | join(" ")')"
sel_args $'repo: api\nbase: release'
assert_eq "a base the task names and the clone lacks blocks the selection" "blocked" "$(sel | jq -r .STATUS)"
assert_eq "as a failed result at stage select" "failed select" \
  "$(jq -r '.status + " " + .stage' "$AD_SEL/out/result.json")"
sel_args 'repo: mobile'
assert_contains "a clone that declares no quality commands is not ready" "$(sel | jq -r .REASON)" "quality commands"
sel_args 'Something vague'
OUT="$(sel)"
assert_eq "no line and three clones: undecided, for a model to choose" "undecided" "$(printf '%s' "$OUT" | jq -r .STATUS)"
assert_contains "from a candidates file that names each clone" "$(cat "$AD_SEL/out/candidates.md")" "## acme/mobile"
assert_eq "the model's choice is recorded, with the base it read" "selected acme/api origin/develop model" \
  "$(sel --choose "$AD_SEL/api" --reason "the api owns login" --evidence "login -> src/auth" --base develop \
     | jq -r '[.STATUS, .SLUG, .BASE_BRANCH, .BASE_SOURCE] | join(" ")')"
assert_eq "with its evidence" "login -> src/auth" "$(jq -r '.evidence | join(",")' "$AD_SEL/out/selection.json")"

jq 'del(.repos) | .stack = {lint: "make lint"}' "$AD_SEL/args.json" > "$AD_SEL/args-dev.json"
assert_eq "auto-dev-args takes the base from the selection" "true origin/develop" \
  "$(cd "$AD_SEL/api" && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 bash "$PLUGIN_SCRIPTS/auto-dev-args.sh" --args "$AD_SEL/args-dev.json" --json 2>/dev/null \
     | jq -r .ACCEPTED) $(jq -r .baseBranch "$AD_SEL/out/workflow-args.json")"
assert_contains "and refuses a checkout that is not the chosen repository" \
  "$(cd "$AD_SEL/web" && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 bash "$PLUGIN_SCRIPTS/auto-dev-args.sh" --args "$AD_SEL/args-dev.json" --json 2>/dev/null | jq -r .REASON)" \
  "the selection chose acme/api"

# hasDevcontainer is what the runner's `devcontainer up --workspace-folder
# <clone>`, with no --config, can start: a clone with only a nested
# configuration runs on the host, and the selection says why — without
# blocking the task.
sel_dc() {
  sel >/dev/null
  jq -r '"\(.status) \(.hasDevcontainer)|\(.devcontainerNote)"' "$AD_SEL/out/selection.json"
}
sel_args 'repo: api'
assert_eq "no devcontainer: false, and no note" "selected false|" "$(sel_dc)"
mkdir -p "$AD_SEL/api/.devcontainer/web" "$AD_SEL/api/.devcontainer/mobile"
printf '{}\n' > "$AD_SEL/api/.devcontainer/web/devcontainer.json"
printf '{}\n' > "$AD_SEL/api/.devcontainer/mobile/devcontainer.json"
OUT="$(sel_dc)"
assert_eq "only nested configurations: false, and the task is still selected" "selected false" "${OUT%%|*}"
assert_contains "the note names each one, and why the runner cannot use it" "${OUT#*|}" \
  ".devcontainer/mobile/devcontainer.json, .devcontainer/web/devcontainer.json ignored: the runner runs \`devcontainer up\` with no --config"
assert_contains "and the runner's log gets it on stderr" \
  "$(bash "$PLUGIN_SCRIPTS/auto-dev-select.sh" --args "$AD_SEL/args.json" --json 2>&1 >/dev/null)" \
  "warning: .devcontainer/mobile/devcontainer.json, .devcontainer/web/devcontainer.json ignored"
printf '{}\n' > "$AD_SEL/api/.devcontainer/devcontainer.json"
assert_eq ".devcontainer/devcontainer.json at the root: true, no note" "selected true|" "$(sel_dc)"
rm -rf "$AD_SEL/api/.devcontainer"
printf '{}\n' > "$AD_SEL/api/.devcontainer.json"
assert_eq ".devcontainer.json at the root: true, no note" "selected true|" "$(sel_dc)"
rm -f "$AD_SEL/api/.devcontainer.json"

# ═══════════════════════════════════════════════════════════════════════════════
# 19. devcontainer: the facts a proposal starts from, and the check
# ═══════════════════════════════════════════════════════════════════════════════
#
# The runner of the headless runs builds the repository's root devcontainer and
# runs the quality commands inside it. What the proposal starts from has to be
# read the same way every time, and never from `.env`; the check has to hold
# the runner's contract, isolate what it builds, and tell a red project (ready)
# from a devcontainer that cannot start a command (not ready). No Docker: the
# devcontainer CLI, docker and uname are stubs.

echo ""
echo "── devcontainer-facts.sh (what the proposal starts from) ──"

facts() { (cd "$1" && bash "$PLUGIN_SCRIPTS/devcontainer-facts.sh" --json 2>/dev/null); }
fact() { facts "$1" | jq -r --arg k "$2" '.[$k]'; }

DCF_EMPTY="$WORK_DIR/dc-facts-empty"
git_init "$DCF_EMPTY"
assert_eq "an empty repository has no fact, and no coverage" "||||false" \
  "$(facts "$DCF_EMPTY" | jq -r '[.CONFIG, .VERSIONS, .CI_IMAGES, .PRIVATE_DEPS, .PHP_COVERAGE] | join("|")')"

DCF="$WORK_DIR/dc-facts"
git_init "$DCF"
mkdir -p "$DCF/api" "$DCF/app" "$DCF/.github/workflows" "$DCF/.devcontainer/web" "$DCF/node_modules/x"
cat > "$DCF/api/composer.json" <<'EOF'
{"require": {"php": "^8.2", "ext-intl": "*", "ext-pdo_mysql": "*"},
 "require-dev": {"ext-pcov": "*"},
 "repositories": [{"type": "vcs", "url": "https://bot:s3cr3t@github.com/acme/private.git"},
                  {"type": "path", "url": "../packages/local"}],
 "scripts": {"test": "pest --coverage"}}
EOF
printf '<phpunit><php><env name="DB_CONNECTION" value="sqlite"/><env name="DB_DATABASE" value=":memory:"/></php></phpunit>\n' \
  > "$DCF/api/phpunit.xml"
printf 'APP_NAME=api\nDB_CONNECTION=mysql\nREDIS_HOST=127.0.0.1\n# MONGO_URL=mongodb://x\nMAIL_HOST=mailpit\n' \
  > "$DCF/api/.env.example"
printf 'DB_CONNECTION=pgsql\nAPP_KEY=base64:never-printed\n' > "$DCF/api/.env"
printf 'flutter 3.24.3-stable\nnodejs 20.11.0 # pinned\n' > "$DCF/.tool-versions"
printf 'v20\n' > "$DCF/.nvmrc"
printf '{"packageManager": "pnpm@9.1.0+sha256.abc", "devDependencies": {"lib": "github:acme/lib#v1", "ok": "^1.0.0"}}\n' \
  > "$DCF/package.json"
printf '{"engines": {"node": "18"}}\n' > "$DCF/node_modules/x/package.json"
printf 'name: app\nenvironment:\n  sdk: ">=3.4.0 <4.0.0"\n  flutter: 3.24.3\ndependencies:\n  atlas:\n    git:\n      url: git@github.com:acme/atlas.git\n      ref: main\n' \
  > "$DCF/app/pubspec.yaml"
printf '{"flutter": "3.24.3"}\n' > "$DCF/app/.fvmrc"
# shellcheck disable=SC2016
printf '@acme:registry=https://npm.pkg.github.com\n//npm.pkg.github.com/:_authToken=${NPM_TOKEN}\n' > "$DCF/.npmrc"
cat > "$DCF/.github/workflows/ci.yml" <<'EOF'
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: php:8.3-cli
    services:
      mysql:
        image: mysql:8.0
        ports:
          - 3306:3306
      redis:
        image: "redis:7"
    steps:
      - name: Checkout
        uses: actions/checkout@v4
  matrix:
    container: ${{ matrix.image }}
EOF
cat > "$DCF/.gitlab-ci.yml" <<'EOF'
image:
  name: ghcr.io/cirruslabs/flutter:3.24.3
services:
  - postgres:16
  - name: valkey/valkey:8
    alias: cache
test:
  image: node:20
  script:
    - npm test
EOF
printf 'FROM php:8.3\n' > "$DCF/api/Dockerfile"
printf 'FROM node:20\n' > "$DCF/.devcontainer/web/Dockerfile"
printf 'services: {}\n' > "$DCF/docker-compose.yml"
printf '{}\n' > "$DCF/.devcontainer/web/devcontainer.json"
DCF_OUT="$(facts "$DCF")"
dcf() { printf '%s' "$DCF_OUT" | jq -r --arg k "$1" '.[$k]'; }

assert_eq "a nested configuration is not the one the runner reads" \
  "|.devcontainer/web/devcontainer.json" "$(dcf CONFIG)|$(dcf NESTED_CONFIGS)"
assert_line "asdf's nodejs is node, with the file that pins it" "$(dcf VERSIONS)" $'node\t20.11.0\t.tool-versions'
assert_line "packageManager gives the manager's version, without its hash" "$(dcf VERSIONS)" $'pnpm\t9.1.0\tpackage.json'
assert_line "composer.json gives php, from its package" "$(dcf VERSIONS)" $'php\t^8.2\tapi/composer.json'
assert_line "pubspec.yaml gives dart and flutter" "$(dcf VERSIONS)" $'dart\t>=3.4.0 <4.0.0\tapp/pubspec.yaml'
assert_line "and .fvmrc its own flutter pin" "$(dcf VERSIONS)" $'flutter\t3.24.3\tapp/.fvmrc'
assert_eq "node_modules is never read" "false" \
  "$(printf '%s' "$(dcf VERSIONS)" | grep -q 'node_modules' && echo true || echo false)"
assert_eq "the ext-* composer requires, sorted" "intl pcov pdo_mysql" "$(dcf PHP_EXTENSIONS)"
assert_eq "a composer script measuring coverage asks for pcov" "true" "$(dcf PHP_COVERAGE)"
assert_line "phpunit.xml says the tests run on an in-memory sqlite" "$(dcf TEST_ENV)" $'DB_CONNECTION=sqlite\tapi/phpunit.xml'
assert_line "a job container is a job image" "$(dcf CI_IMAGES)" $'php:8.3-cli\tjob\t.github/workflows/ci.yml'
assert_line "a GitHub service is a service image" "$(dcf CI_IMAGES)" $'redis:7\tservice\t.github/workflows/ci.yml'
assert_line "a GitLab image block gives its name" "$(dcf CI_IMAGES)" $'ghcr.io/cirruslabs/flutter:3.24.3\tjob\t.gitlab-ci.yml'
assert_line "a GitLab service item, scalar" "$(dcf CI_IMAGES)" $'postgres:16\tservice\t.gitlab-ci.yml'
assert_line "a GitLab service item, with a name" "$(dcf CI_IMAGES)" $'valkey/valkey:8\tservice\t.gitlab-ci.yml'
assert_eq "a port mapping and an expression are not images" "false" \
  "$(printf '%s' "$(dcf CI_IMAGES)" | grep -qE '^(3306|\$)' && echo true || echo false)"
assert_eq "the Docker files outside .devcontainer/" "api/Dockerfile|docker-compose.yml" \
  "$(dcf DOCKERFILES)|$(dcf COMPOSE_FILES)"
assert_eq "the services .env.example points at, a commented key not one of them" \
  "mailpit mysql redis" "$(printf '%s\n' "$(dcf ENV_SERVICES)" | cut -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq ".env is never read: not its service, not its value, not the file" "false false false" \
  "$(dcf ENV_SERVICES | grep -q postgres && echo true || echo false) $(printf '%s' "$DCF_OUT" | grep -q never-printed && echo true || echo false) $(dcf ENV_EXAMPLES | grep -qx 'api/.env' && echo true || echo false)"
assert_line "a vcs repository needs credentials, its token masked" "$(dcf PRIVATE_DEPS)" \
  $'api/composer.json\trepository vcs https://***@github.com/acme/private.git'
assert_eq "the token itself is printed nowhere" "false" \
  "$(printf '%s' "$DCF_OUT" | grep -qE 's3cr3t|NPM_TOKEN' && echo true || echo false)"
assert_line "a git dependency of package.json" "$(dcf PRIVATE_DEPS)" $'package.json\tlib github:acme/lib#v1'
assert_line "a private npm registry" "$(dcf PRIVATE_DEPS)" $'.npmrc\tregistry https://npm.pkg.github.com'
assert_line "a git dependency of pubspec.yaml" "$(dcf PRIVATE_DEPS)" $'app/pubspec.yaml\tgit git@github.com:acme/atlas.git'
assert_eq "no Testcontainers here" "" "$(dcf TESTCONTAINERS)"
DCF_TC="$WORK_DIR/dc-facts-tc"
git_init "$DCF_TC"
mkdir -p "$DCF_TC/svc" "$DCF_TC/web"
printf 'module acme/svc\n\ngo 1.22\n\nrequire github.com/testcontainers/testcontainers-go v0.30.0\n' > "$DCF_TC/svc/go.mod"
printf '{"devDependencies": {"@testcontainers/postgresql": "^10.0.0", "jest": "^29"}}\n' > "$DCF_TC/web/package.json"
printf '<dependency><groupId>org.testcontainers</groupId></dependency>\n' > "$DCF_TC/pom.xml"
mkdir -p "$DCF_TC/dotnet" "$DCF_TC/rs" "$DCF_TC/py"
printf '<ItemGroup><PackageReference Include="Testcontainers.PostgreSql" Version="3.9.0" /></ItemGroup>\n' \
  > "$DCF_TC/dotnet/Api.Tests.csproj"
printf '[dev-dependencies]\ntestcontainers = "0.20"\ntestcontainers-modules = { version = "0.8" }\n' > "$DCF_TC/rs/Cargo.toml"
printf 'pytest==8.0\ntestcontainers[postgres]==4.4\n' > "$DCF_TC/py/requirements-dev.txt"
git -C "$DCF_TC" remote add origin "https://bot:t0k@github.com/Acme/Svc.git"
assert_eq "Testcontainers, in every manifest's own spelling: the tests need the socket the runner refuses" \
  "dotnet/Api.Tests.csproj Testcontainers.PostgreSql|pom.xml org.testcontainers|py/requirements-dev.txt testcontainers|rs/Cargo.toml testcontainers|rs/Cargo.toml testcontainers-modules|svc/go.mod github.com/testcontainers/testcontainers-go|web/package.json @testcontainers/postgresql" \
  "$(fact "$DCF_TC" TESTCONTAINERS | tr '\t' ' ' | tr '\n' '|' | sed 's/|$//')"
assert_eq "and go.mod still gives its go version" "$(printf 'go\t1.22\tsvc/go.mod')" "$(fact "$DCF_TC" VERSIONS)"
assert_eq "the repository the GCP exclusion names, as auto-dev-select names it, credentials dropped" \
  "acme/svc" "$(fact "$DCF_TC" REPOSITORY)"

echo ""
echo "── devcontainer-check.sh (the runner's contract, built and probed) ──"

DCC_BIN="$WORK_DIR/dc-check-bin"
mkdir -p "$DCC_BIN"
cat > "$DCC_BIN/devcontainer" <<'STUB'
#!/usr/bin/env bash
printf 'devcontainer %s COMPOSE_PROJECT_NAME=%s\n' "$*" "${COMPOSE_PROJECT_NAME:-}" >> "$STUB_LOG"
case "$1" in
  up)
    if [ "${STUB_UP:-success}" != success ]; then
      echo 'E: Unable to locate package flutter' >&2
      printf '{"outcome":"error","message":"Command failed: docker build","description":"An error occurred building the image."}\n'
      exit 1
    fi
    project=""
    [ -n "${COMPOSE_PROJECT_NAME:-}" ] && project=",\"composeProjectName\":\"$COMPOSE_PROJECT_NAME\""
    echo '[2 ms] Start: Run: docker build' >&2
    printf '{"outcome":"success","containerId":"c0ffee","remoteUser":"%s","remoteWorkspaceFolder":"/workspaces/repo"%s}\n' \
      "${STUB_USER:-vscode}" "$project" ;;
  exec)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in --workspace-folder|--container-id|--id-label) shift 2 ;; --*) shift ;; *) break ;; esac
    done
    if [ "$1" = sh ]; then
      printf 'uid=%s\npwd=/workspaces/repo\n' "${STUB_UID:-1000}"
      for t in ${STUB_MISSING:-}; do printf 'missing=%s\n' "$t"; done
      printf 'top=%s\n' "${STUB_TOP:-/workspaces/repo}"
      exit 0
    fi
    exec "$@" ;;
  run-user-commands)
    if [ "${STUB_LIFECYCLE:-success}" != success ]; then
      echo 'git@github.com: Permission denied (publickey).' >&2
      printf '{"outcome":"error","message":"Command failed: /bin/sh -c tool/generate.sh","description":"postCreateCommand from devcontainer.json failed."}\n'
      exit 1
    fi
    printf '{"outcome":"success"}\n' ;;
esac
STUB
cat > "$DCC_BIN/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$STUB_LOG"
[ "$1" = info ] && exit "${STUB_DOCKER_RC:-0}"
case "$*" in exec*stat*) printf '660\n' ;; esac
exit 0
STUB
cat > "$DCC_BIN/ssh-add" <<'STUB'
#!/usr/bin/env bash
exit "${STUB_SSH_ADD_RC:-0}"
STUB
cat > "$DCC_BIN/uname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${STUB_OS:-Darwin}"
STUB
chmod +x "$DCC_BIN"/*

DCC_LOG="$WORK_DIR/dc-check.log"
# Runs the check in $1 with the stubs first on PATH, in this shell: the JSON
# lands in OUT and the exit status in DCC_EXIT. `dck <key>` reads OUT.
dcc() {
  local dir="$1"
  shift
  : > "$DCC_LOG"
  OUT="$(cd "$dir" && STUB_LOG="$DCC_LOG" PATH="$DCC_BIN:$PATH" \
         bash "$PLUGIN_SCRIPTS/devcontainer-check.sh" --json "$@" 2>/dev/null)"
  DCC_EXIT=$?
}
dck() { printf '%s' "$OUT" | jq -r "$1"; }
logged() { grep -q -- "$1" "$DCC_LOG" && echo true || echo false; }
dcc_repo() {
  local dir="$WORK_DIR/dc-check-$1"
  git_init "$dir"
  mkdir -p "$dir/.devcontainer" "$dir/.claude"
  printf '%s\n' '{"lint": "true", "typecheck": null, "test": "false", "absent": {"typecheck": "none"}, "preflight": null, "hook_manager": null}' \
    > "$dir/.claude/quality-commands.json"
  printf '%s' "$dir"
}

DCC="$(dcc_repo none)"
dcc "$DCC"
assert_eq "no configuration at the root is not ready" "not-ready 4" "$(dck .STATUS) $DCC_EXIT"
mkdir -p "$DCC/.devcontainer/web" && printf '{}\n' > "$DCC/.devcontainer/web/devcontainer.json"
dcc "$DCC"
assert_contains "and a nested one is named as the reason" "$(dck .REASON)" "no --config"

DCC="$(dcc_repo ok)"
cat > "$DCC/.devcontainer/devcontainer.json" <<'EOF'
{
  // the toolchain, from "the" repository root
  "name": "app // not a comment",
  "build": { "dockerfile": "Dockerfile", "context": ".." },
  "remoteUser": "vscode", /* the runner's UID */
  "postCreateCommand": "npm ci",
}
EOF
dcc "$DCC"
assert_eq "comments and trailing commas parse, and the check is ready" "ready 0" "$(dck .STATUS) $DCC_EXIT"
assert_eq "a red test is the project's state, not an issue" "passed absent failed|" \
  "$(dck '"\(.LINT_STATUS) \(.TYPECHECK_STATUS) \(.TEST_STATUS)|\(.ISSUES)"')"
assert_contains "and its output is reported" "$(dck .OUTPUT)" "--- test: false (exit 1)"
assert_contains "it builds fresh, under a label of its own" "$(cat "$DCC_LOG")" \
  "--id-label dev-setup.check=dc-check-ok-"
assert_contains "replacing only the check's previous container" "$(cat "$DCC_LOG")" "--remove-existing-container"
assert_contains "the commands run with devcontainer exec, in the container" "$(cat "$DCC_LOG")" \
  "--container-id c0ffee bash -c false"
assert_eq "and the container is removed after" "true" "$(logged 'docker rm -f c0ffee')"
dcc "$DCC" --keep
assert_eq "--keep leaves it running" "true false" "$(dck .KEPT) $(logged 'docker rm')"
assert_eq "no agent is forwarded unless asked" "|false" "$(dck .SSH_AGENT)|$(logged '--mount')"
dcc "$DCC" --ssh-agent
assert_eq "--ssh-agent on macOS mounts Docker Desktop's agent socket, for the check's container only" "forwarded true" \
  "$(dck .SSH_AGENT) $(logged 'devcontainer up .*--mount type=bind,source=/run/host-services/ssh-auth.sock,target=/tmp/dev-setup-ssh-agent.sock')"
assert_eq "and the lifecycle commands find it, and accept github.com's key" "true true" \
  "$(logged 'run-user-commands .*--remote-env SSH_AUTH_SOCK=/tmp/dev-setup-ssh-agent.sock') $(logged 'GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new')"
assert_eq "Docker Desktop's socket is root's: up skips the lifecycle, the socket is opened, then put back" \
  "true true true" \
  "$(logged 'devcontainer up .*--skip-post-create') $(logged 'docker exec -u 0 c0ffee chmod 0666 /tmp/dev-setup-ssh-agent.sock') $(logged 'docker exec -u 0 c0ffee chmod 660 /tmp/dev-setup-ssh-agent.sock')"
assert_eq "in that order: opened, lifecycle, closed" "chmod 0666|run-user-commands|chmod 660" \
  "$(grep -oE 'chmod 0666|run-user-commands|chmod 660' "$DCC_LOG" | tr '\n' '|' | sed 's/|$//')"
STUB_LIFECYCLE=error dcc "$DCC" --ssh-agent
assert_eq "a lifecycle command that fails is a failed up, the socket put back all the same" "not-ready failed true" \
  "$(dck '"\(.STATUS) \(.UP)"') $(logged 'chmod 660')"
assert_contains "with the lifecycle's own log" "$(dck .OUTPUT)" "--- devcontainer lifecycle (exit 1)"
assert_contains "and its description" "$(dck .REASON)" "postCreateCommand from devcontainer.json failed."
STUB_SSH_ADD_RC=1 dcc "$DCC" --ssh-agent
assert_eq "an agent with no key is not worth a build" "unverified false" "$(dck .STATUS) $(logged 'devcontainer up')"
assert_contains "and the reason says to load the key" "$(dck .REASON)" "the SSH agent holds no key"
DCC_SOCK="$WORK_DIR/dc-check-agent.sock"
: > "$DCC_SOCK"
STUB_OS=Linux STUB_UID="$(id -u)" SSH_AUTH_SOCK="$DCC_SOCK" dcc "$DCC" --ssh-agent
assert_eq "on Linux it mounts the agent the session has" "ready true" \
  "$(dck .STATUS) $(logged "source=$DCC_SOCK,target=/tmp/dev-setup-ssh-agent.sock")"
assert_eq "whose socket is already the user's: the lifecycle runs in up, nothing is opened" "false false" \
  "$(logged 'skip-post-create') $(logged 'chmod')"
STUB_OS=Linux SSH_AUTH_SOCK="" dcc "$DCC" --ssh-agent
assert_eq "and with no agent there, nothing is built and the check says why" "unverified 3 false" \
  "$(dck .STATUS) $DCC_EXIT $(logged 'devcontainer up')"
assert_contains "naming SSH_AUTH_SOCK" "$(dck .REASON)" "SSH_AUTH_SOCK is unset"

STUB_UID=0 STUB_USER=root dcc "$DCC"
assert_eq "commands that run as root are not ready" "not-ready 4" "$(dck .STATUS) $DCC_EXIT"
assert_contains "and the issue says why" "$(dck .ISSUES)" "the runner runs as UID 1000"
STUB_UID=1001 dcc "$DCC"
assert_contains "a user with another UID is not ready" "$(dck .ISSUES)" "has UID 1001, the runner's is 1000"
STUB_OS=Linux STUB_UID="$(id -u)" dcc "$DCC"
assert_eq "on a Linux host the CLI maps the UID, so the host's is expected" "ready $(id -u)" \
  "$(dck '"\(.STATUS) \(.EXPECTED_UID)"')"
STUB_MISSING=curl dcc "$DCC"
assert_contains "an image without curl is not ready" "$(dck .ISSUES)" "not in the image: curl"
STUB_TOP=/workspaces dcc "$DCC"
assert_contains "a workspace that is not the repository root is not ready" "$(dck .ISSUES)" \
  "workspaceFolder must be the root"

printf '%s\n' '{"lint": "no-such-linter-anywhere", "typecheck": null, "test": "true", "absent": {"typecheck": "none"}, "preflight": "false"}' \
  > "$DCC/.claude/quality-commands.json"
dcc "$DCC"
assert_eq "a command that does not start, and a red preflight, are the devcontainer's" \
  "not-ready not-found failed 4" "$(dck '"\(.STATUS) \(.LINT_STATUS) \(.PREFLIGHT)"') $DCC_EXIT"
assert_contains "named in the issues" "$(dck .ISSUES)" "lint did not start inside the container"

STUB_UP=error dcc "$DCC"
assert_eq "a build that fails is not ready" "not-ready failed" "$(dck '"\(.STATUS) \(.UP)"')"
assert_contains "with the CLI's description" "$(dck .REASON)" "An error occurred building the image."
assert_contains "and the build log's tail" "$(dck .OUTPUT)" "Unable to locate package flutter"
assert_eq "and no command runs" "false" "$(logged 'bash -c')"

STUB_DOCKER_RC=1 dcc "$DCC"
assert_eq "no Docker daemon: unverified" "unverified 3" "$(dck .STATUS) $DCC_EXIT"
assert_contains "and the reason names the sandbox" "$(dck .REASON)" "inside a sandbox"
NODC_BIN="$WORK_DIR/dc-check-nocli"
mkdir -p "$NODC_BIN" && cp "$DCC_BIN/docker" "$NODC_BIN/docker"
assert_contains "no devcontainer CLI: unverified, with how to install it" \
  "$(cd "$DCC" && STUB_LOG="$DCC_LOG" PATH="$NODC_BIN:/usr/bin:/bin" \
       bash "$PLUGIN_SCRIPTS/devcontainer-check.sh" --json 2>/dev/null | jq -r '"\(.STATUS) \(.REASON)"')" \
  "unverified the devcontainer CLI is not installed (npm install -g @devcontainers/cli)"
rm -f "$DCC/.claude/quality-commands.json"
dcc "$DCC"
assert_eq "no declared commands: unverified, nothing built" "unverified 3 false" \
  "$(dck .STATUS) $DCC_EXIT $(logged 'devcontainer up')"
assert_contains "and the setup's step 3b is named" "$(dck .REASON)" "/dev-setup:setup (step 3b)"

DCC="$(dcc_repo static)"
cat > "$DCC/.devcontainer/devcontainer.json" <<'EOF'
{
  "image": "mcr.microsoft.com/devcontainers/base:bookworm",
  "remoteUser": "root",
  "mounts": ["source=/var/autodev,target=/var/autodev,type=bind"],
  "containerEnv": { "GH_TOKEN": "${localEnv:GH_TOKEN}", "HOME_DIR": "${localEnv:HOME}" }
}
EOF
dcc "$DCC"
assert_eq "a configuration that breaks the contract is not built" "not-ready 4 false" \
  "$(dck .STATUS) $DCC_EXIT $(logged 'devcontainer up')"
assert_eq "three clauses broken, three issues: root, the mount, the credential" "3" \
  "$(dck .ISSUES | grep -c .)"
# shellcheck disable=SC2016
assert_contains "the credential is named" "$(dck .ISSUES)" '${localEnv:GH_TOKEN}'
assert_eq "a localEnv that is not a credential is not an issue" "false" \
  "$(dck .ISSUES | grep -q 'localEnv:HOME' && echo true || echo false)"
# The clauses that keep the agent away from the runner's host, one per line.
dc_static() {
  printf '%s\n' "$1" > "$DCC/.devcontainer/devcontainer.json"
  dcc "$DCC"
  printf '%s %s|%s' "$(dck .STATUS)" "$(logged 'devcontainer up')" "$(dck .ISSUES)"
}
# shellcheck disable=SC2016
OUT_SSH="$(dc_static '{"image": "x", "mounts": ["source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind", "source=node_modules,target=/w/node_modules,type=volume"]}')"
assert_contains "a bind of the host's ~/.ssh fails up on the VM, and is not built" "$OUT_SSH" \
  'not-ready false|a bind mount of a host path (${localEnv:HOME}/.ssh)'
assert_eq "a named volume is not a host path" "1" "$(printf '%s' "${OUT_SSH#*|}" | grep -c .)"
assert_contains "a -v of an absolute host path, in runArgs" \
  "$(dc_static '{"image": "x", "runArgs": ["-v", "/home/me/.aws:/home/vscode/.aws"]}')" \
  "a bind mount of a host path (/home/me/.aws:/home/vscode/.aws)"
assert_contains "the Docker socket" \
  "$(dc_static '{"image": "x", "mounts": [{"source": "/var/run/docker.sock", "target": "/var/run/docker.sock", "type": "bind"}]}')" \
  "the Docker socket is mounted: the runner refuses it"
assert_contains "privileged mode" "$(dc_static '{"image": "x", "privileged": true}')" "privileged mode: the runner refuses it"
assert_contains "privileged mode, in runArgs" "$(dc_static '{"image": "x", "runArgs": ["--privileged"]}')" "privileged mode"
assert_contains "the host network" "$(dc_static '{"image": "x", "runArgs": ["--network=host"]}')" "the host network: the runner refuses it"
assert_contains "a Docker Feature" \
  "$(dc_static '{"image": "x", "features": {"ghcr.io/devcontainers/features/docker-in-docker:2": {}}}')" \
  "the Feature ghcr.io/devcontainers/features/docker-in-docker:2 gives the container Docker"
assert_contains "a workspaceMount of its own" \
  "$(dc_static '{"image": "x", "workspaceMount": "source=${localWorkspaceFolder},target=/src,type=bind"}')" \
  "a custom workspaceMount"
assert_contains "a workspaceFolder of its own" "$(dc_static '{"image": "x", "workspaceFolder": "/src"}')" \
  "a custom workspaceFolder (/src)"
# shellcheck disable=SC2016
assert_eq "the CLI's default, written out, is not one" "ready" \
  "$(dc_static '{"image": "x", "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}"}' | cut -d' ' -f1)"

printf '{"broken": }\n' > "$DCC/.devcontainer/devcontainer.json"
dcc "$DCC"
assert_contains "a configuration that does not parse is named" "$(dck .REASON)" "does not parse"

DCC="$(dcc_repo compose)"
printf '%s\n' '{"dockerComposeFile": ["compose.yml"], "service": "app", "workspaceFolder": "/workspace", "remoteUser": "vscode"}' \
  > "$DCC/.devcontainer/devcontainer.json"
printf 'services:\n  app:\n    build: ..\n    volumes: ["..:/workspace:cached"]\n' > "$DCC/.devcontainer/compose.yml"
dcc "$DCC"
assert_eq "a compose configuration is checked as one" "ready true" "$(dck '"\(.STATUS) \(.COMPOSE)"')"
assert_contains "under a compose project of its own" "$(grep 'devcontainer up' "$DCC_LOG")" \
  "COMPOSE_PROJECT_NAME=devsetup-check-dc-check-compose-"
assert_eq "which is the one taken down with its volumes, and no container is removed alone" "true false" \
  "$(grep -qE 'docker compose -p devsetup-check-dc-check-compose-[0-9]+ down --volumes --remove-orphans' "$DCC_LOG" \
       && echo true || echo false) $(logged 'docker rm')"
STUB_UP=error dcc "$DCC"
assert_eq "a compose build that fails still takes the check's project down" "not-ready true" \
  "$(dck .STATUS) $(grep -qE 'docker compose -p devsetup-check-dc-check-compose-[0-9]+ down' "$DCC_LOG" && echo true || echo false)"
printf 'services:\n  app:\n    volumes: ["/var/autodev:/var/autodev"]\n' > "$DCC/.devcontainer/compose.yml"
dcc "$DCC"
assert_contains "a compose file that mounts /var/autodev is not ready" "$(dck .ISSUES)" \
  ".devcontainer/compose.yml mounts /var/autodev"
assert_eq "and is not also reported as a host path" "false" "$(dck .ISSUES | grep -q 'binds a host path' && echo true || echo false)"
cat > "$DCC/.devcontainer/compose.yml" <<'EOF'
services:
  app:
    build: ..
    volumes:
      - ..:/workspaces/repo:cached
      - ~/.gitconfig:/home/vscode/.gitconfig
      - /var/run/docker.sock:/var/run/docker.sock
  db:
    image: mysql:8.0
    privileged: true
    network_mode: host
    volumes:
      - dbdata:/var/lib/mysql
volumes:
  dbdata:
EOF
dcc "$DCC"
assert_eq "a compose file that reaches the host: four issues, the workspace and a named volume not among them" "4" \
  "$(dck .ISSUES | grep -c .)"
assert_contains "the host path" "$(dck .ISSUES)" ".devcontainer/compose.yml binds a host path (~/.gitconfig)"
assert_contains "the socket" "$(dck .ISSUES)" ".devcontainer/compose.yml mounts the Docker socket"
assert_contains "privileged" "$(dck .ISSUES)" ".devcontainer/compose.yml runs a service privileged"
assert_contains "the host network" "$(dck .ISSUES)" ".devcontainer/compose.yml puts a service on the host network"

echo ""
echo "── the devcontainer command ──"

DC_SKILL="$TEMPLATE_ROOT/.claude/skills/devcontainer/SKILL.md"
assert_eq "it is a command a person starts, never one the model infers" "true true" \
  "$(frontmatter_of "$DC_SKILL" | sed -n 's/^user-invocable:[[:space:]]*//p') $(frontmatter_of "$DC_SKILL" | sed -n 's/^disable-model-invocation:[[:space:]]*//p')"
for DC_SCRIPT in devcontainer-facts.sh devcontainer-check.sh; do
  assert_contains "it calls $DC_SCRIPT through the plugin root" "$(cat "$DC_SKILL")" \
    "\${CLAUDE_PLUGIN_ROOT}/scripts/$DC_SCRIPT"
  assert_eq "and the manifest ships $DC_SCRIPT" "true" \
    "$(jq -r --arg s "$DC_SCRIPT" '.plugin_scripts | index($s) != null' "$TEMPLATE_ROOT/manifest.json")"
done
assert_contains "it stops before any write when nothing is declared" "$(flat "$DC_SKILL")" \
  "\`COMMANDS_SOURCE\` other than \`declared\` → stop, nothing written"
assert_contains "Testcontainers stops it before anything else" "$(flat "$DC_SKILL")" \
  "\`TESTCONTAINERS\` set → GCP does not support it, and nothing is written for the runner"
DC_CONTRACT="$TEMPLATE_ROOT/.claude/skills/devcontainer/reference/contract.md"
assert_contains "and the contract gives the exclusion, verbatim" "$(cat "$DC_CONTRACT")" \
  'in n8n, data table `autodev_projects`, the project'"'"'s row,
column `gcp_excluded` = `testcontainers: <REPOSITORY>`'
assert_contains "a devcontainer for VS Code is asked, with Stop as the default" "$(flat "$DC_CONTRACT")" \
  "**Stop here** (the default; nothing written) or **A devcontainer for VS Code**"
assert_eq "it is not a step of setup" "false" \
  "$(grep -rq 'devcontainer-' "$TEMPLATE_ROOT/setup" && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

discard_dir "$WORK_DIR"

echo ""
if [ "$FAILED" -gt 0 ]; then
  printf '%s%s failed%s, %s passed\n' "$RED" "$FAILED" "$NC" "$PASSED"
  exit 1
fi
printf '%sall %s tests passed%s\n' "$GREEN" "$PASSED" "$NC"
