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
# exists, the command reimplements none of the workflow, and an answered
# needs-human resumes at Dev instead of redoing the spec.
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

    # Both sides resolved with `pwd -P`: on macOS $TMPDIR sits under /tmp, which
    # is a symlink to /private/tmp, and git reports the physical path. Comparing
    # it against a logical `pwd` rejected a directory that works perfectly.
    if [ "$(cd "$(git -C "$candidate/probe" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P)" \
       = "$(cd "$candidate/probe" && pwd -P)" ]; then
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
  "feat/DE-123-add-refresh-token-rotation" \
  "$(sdd_start --task DE-123 --title "Add refresh token rotation" --json | jq -r '.BRANCH')"

assert_eq "punctuation folded into single dashes" \
  "fix/DE-1-login-500-on-empty-body" \
  "$(sdd_start --task DE-1 --type fix --title "Login: 500 on empty body!" --json | jq -r '.BRANCH')"

assert_eq "no title, no slug" \
  "chore/DE-7" \
  "$(sdd_start --task DE-7 --type chore --json | jq -r '.BRANCH')"

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

assert_eq "the merged settings denies reading .env" "true" \
  "$(jq -r '[.sandbox.filesystem.denyRead[], .permissions.deny[]]
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

# ═══════════════════════════════════════════════════════════════════════════════
# 8. auto-sdd.js: the workflow script (DE-16479)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The autonomous orchestration is code now, so it is tested like code. What the
# static check cannot see is whether the file compiles: the harness parses the
# `export const meta` literal and then compiles the rest as the body of an async
# function, which is neither valid CommonJS nor a valid ES module on its own —
# `node --check` answers the wrong question. This reproduces both halves.

echo ""
echo "── auto-sdd.js (workflow script) ──"

AUTO_SDD="$REPO_ROOT/templates/dev-setup/.claude/workflows/auto-sdd.js"

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
      "auto-sdd" "$(printf '%s' "$WF_META" | jq -r '.name')"

    assert_eq "the four phases are declared in order" \
      "Spec Challenge Dev Verify" \
      "$(printf '%s' "$WF_META" | jq -r '.phases | join(" ")')"

    assert_eq "meta carries a description" "false" \
      "$(printf '%s' "$WF_META" | jq -r '.description == ""')"
  else
    fail "the script compiles the way the harness compiles it" "$WF_META"
  fi
else
  printf '%s  skip%s  node not found: the workflow compile test needs it\n' "$DIM" "$NC"
fi

if [ -f "$AUTO_SDD" ]; then
  # The decisions the audit turned into code. A number in prose was a suggestion;
  # these are the lines that make them bounds.
  assert_eq "three adversarial lenses, no more and no fewer" \
    "3" "$(grep -c "^    key: '" "$AUTO_SDD")"

  assert_contains "two objections stop the run" \
    "$(cat "$AUTO_SDD")" "objections.length >= 2"

  assert_contains "a dead verifier counts as an objection" \
    "$(cat "$AUTO_SDD")" "counted as an objection"

  assert_contains "the dev stage runs in an isolated worktree" \
    "$(cat "$AUTO_SDD")" "isolation: 'worktree'"

  # Effort is differentiated per call: max only on the verifiers, high on spec
  # and dev, low on the stage that only runs commands.
  assert_eq "only the verifiers get max effort" \
    "1" "$(grep -c "effort: 'max'" "$AUTO_SDD")"
  assert_eq "spec and dev run at high effort" \
    "2" "$(grep -c "effort: 'high'" "$AUTO_SDD")"
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
assert_eq "the replaced agents are gone from the distributed surface" "" \
  "$(grep -rl -E "sdd-approver|discovery-responder|methodology-picker" \
       "$REPO_ROOT/templates" "$REPO_ROOT/dist" 2>/dev/null || true)"

assert_eq "no command points at the retired tdd/bdd skills" "" \
  "$(grep -rl -E "dev-setup:(tdd|bdd)" \
       "$REPO_ROOT/templates" "$REPO_ROOT/dist" 2>/dev/null || true)"

assert_eq "the workflow ships in the built plugin" "true" \
  "$([ -f "$REPO_ROOT/dist/dev-setup/workflows/auto-sdd.js" ] && echo true || echo false)"

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
  "$(cat "$MULTI"/SKILL.md "$MULTI"/reference/*.md)" "dev-setup:auto-sdd"

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
echo "── the answered needs-human resumes at Dev ──"

# Criterion 3: after the developer answers, the run continues without redoing
# the phases that completed. That is only true if what they said reaches the
# workflow *after* the Challenge — the resume replays every agent call whose
# prompt is unchanged, so a guidance string inside the spec prompt would throw
# away the spec, the three verdicts and the whole point of resuming.
if [ -f "$AUTO_SDD" ]; then
  assert_contains "the workflow takes the lenses the developer cleared" \
    "$(cat "$AUTO_SDD")" "input.resolved"
  assert_contains "and only a named lens comes off the count" \
    "$(cat "$AUTO_SDD")" "cleared.includes(o.lens)"

  CACHED_REGION=$(awk "/^phase\('Spec'\)/,/^const raised =/" "$AUTO_SDD")
  assert_eq "nothing the developer said reaches the cached prompts" "" \
    "$(printf '%s' "$CACHED_REGION" | grep -nE 'guidance|cleared|overruled' || true)"

  # An overrule that leaves no trace is an auto-approval with extra steps.
  assert_contains "the overrule reaches the developer agent" \
    "$(cat "$AUTO_SDD")" "is overruled"
  assert_contains "and travels in the outcome" \
    "$(cat "$AUTO_SDD")" "overruled,"
fi

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

# The asks in the setup are real tool calls: the skill has to be allowed to make
# them. `install.md` alone instructs three of them.
assert_contains "the setup skill may call AskUserQuestion" \
  "$(sed -n '2,/^---$/p' "$REPO_ROOT/dist/dev-setup/skills/setup/SKILL.md")" \
  "AskUserQuestion"

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
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "$WORK_DIR"

echo ""
if [ "$FAILED" -gt 0 ]; then
  printf '%s%s failed%s, %s passed\n' "$RED" "$FAILED" "$NC" "$PASSED"
  exit 1
fi
printf '%sall %s tests passed%s\n' "$GREEN" "$PASSED" "$NC"
