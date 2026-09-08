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
#
# Usage:
#   bash scripts/test-plugin-scripts.sh            # run the suite
#   bash scripts/test-plugin-scripts.sh --update   # rewrite the snapshots
#
# The work directory defaults to .tmp-script-tests/ inside the repository:
# mktemp under /var/folders is denied in a sandboxed session, and a repo-local
# path behaves the same locally and in CI. Override it with TEST_TMPDIR.

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
# Candidates in order: an explicit TEST_TMPDIR, then a repo-local directory
# (what CI uses), then the system temp directory. A candidate is only accepted
# if `git init` actually succeeds in it: under the sandbox the repo-local one
# fails, and silently losing the git-dependent tests would be worse than
# spending a probe on it.
pick_work_dir() {
  local candidate
  for candidate in \
    ${TEST_TMPDIR:+"$TEST_TMPDIR"} \
    "$REPO_ROOT/.tmp-script-tests" \
    "${TMPDIR:-/tmp}/dev-setup-script-tests"; do

    rm -rf "$candidate" 2>/dev/null
    mkdir -p "$candidate/probe" 2>/dev/null || continue

    # `git init` creates .git/ before it writes the config, so neither the
    # directory existing nor `--is-inside-work-tree` proves anything: the latter
    # answers about the enclosing repository when the nested one is broken.
    # The repository is usable only if it reports itself as the top level.
    EMPTY_GIT_TEMPLATE="$candidate/.git-template"
    git_init "$candidate/probe" >/dev/null 2>&1

    if [ "$(git -C "$candidate/probe" rev-parse --show-toplevel 2>/dev/null)" \
       = "$(cd "$candidate/probe" && pwd)" ]; then
      rm -rf "$candidate/probe"
      printf '%s' "$candidate"
      return 0
    fi

    rm -rf "$candidate" 2>/dev/null
  done
  return 1
}

WORK_DIR=$(pick_work_dir) || {
  echo "cannot find a directory where git repositories can be created." >&2
  echo "Set TEST_TMPDIR to a writable path outside the project." >&2
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
  "feat/DE-123-add-refresh-token-rotation" \
  "$(sdd_start --task DE-123 --title "Add refresh token rotation" --json | jq -r '.BRANCH')"

assert_eq "punctuation folded into single dashes" \
  "fix/DE-1-login-500-on-empty-body" \
  "$(sdd_start --task DE-1 --type fix --title "Login: 500 on empty body!" --json | jq -r '.BRANCH')"

assert_eq "no title, no slug" \
  "chore/DE-7" \
  "$(sdd_start --task DE-7 --type chore --json | jq -r '.BRANCH')"

assert_eq "spec dir sits at the repository root" \
  "$SANDBOX/.specs" \
  "$(sdd_start --task DE-7 --json | jq -r '.SPEC_DIR')"

sdd_start --task DE-9 --type banana --json >/dev/null 2>&1
assert_eq "an invalid type is refused" "1" "$?"

sdd_start --json >/dev/null 2>&1
assert_eq "a missing --task is refused" "1" "$?"

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

# ── Anti-bypass mode: no check of its own ──
# The husky fixture has "test": "jest" and no node_modules, so a check run here
# would fail. Getting no decision back proves the gate delegated instead.
assert_eq "with husky the gate runs no check of its own" \
  "none" "$(decision_of "$(gate "$WORK_DIR/nextjs" 'git commit -m "feat: something"')")"

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
  assert_eq "nothing staged, no suite run" \
    "none" "$(decision_of "$(gate "$EMPTY_PROJECT" 'git commit -m "feat: thing"')")"
else
  echo "  ${DIM}npm not found: full-gate execution tests skipped${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "$WORK_DIR"

echo ""
if [ "$FAILED" -gt 0 ]; then
  printf '%s%s failed%s, %s passed\n' "$RED" "$FAILED" "$NC" "$PASSED"
  exit 1
fi
printf '%sall %s tests passed%s\n' "$GREEN" "$PASSED" "$NC"
