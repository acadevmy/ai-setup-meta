#!/usr/bin/env bash
# quality-candidates.sh — the lint, typecheck and test commands a project
# already declares somewhere, proposed to the setup (step 3b) as candidates.
#
# The per-language heuristics of detect-stack.sh know the stacks someone wrote a
# rule for, and nothing else: on a Laravel project in `api/` (DE-17472) they
# found three empty commands while the project had `make lint`, `make test` and
# a CI job running both. Every project, whatever its stack, already writes its
# gates down for somebody — the CI that gates the merge, a task runner, the
# package manager's scripts, the README. This script reads those, in that order
# of authority, and puts the heuristics last. It knows no language.
#
# Read-only: it executes nothing it finds. The setup asks the developer to
# confirm or correct the candidates, then writes `.claude/quality-commands.json`.
#
# Usage:
#   quality-candidates.sh [--json] [--dir <path>]
#
#   --json        emit a flat JSON object
#   --dir <path>  scan a sub-project (relative to the repository root): its
#                 candidates come out as `cd <path> && <command>`
#
# Keys:
#   LINT_CANDIDATES       one `<command>\t<source>` line per candidate
#   TYPECHECK_CANDIDATES  the same, for the type check
#   TEST_CANDIDATES       the same, for the tests
#   CANDIDATE_COUNT       how many lines the three hold together
#
# A source is `<kind>:<path from the repository root>`, the kind one of:
#   ci:         .github/workflows/*.yml|yaml (`run:` steps), .gitlab-ci.yml
#               (`script:` items)
#   runner:     Makefile, justfile, Taskfile.yml targets
#   scripts:    package.json, composer.json, pyproject.toml
#               ([tool.poe.tasks], [tool.pdm.scripts])
#   docs:       the fenced shell blocks of README.md and AGENTS.md
#   heuristic:  detect-stack.sh, with no declaration read
#
# Every candidate runs from the repository root, which is where every consumer
# runs the declared commands: a CI step's `working-directory` (on the step, or
# in the job's `defaults.run`) and `--dir` are folded into the command as
# `cd <dir> && `. A command is listed once, with the first source that yielded
# it. A candidate is classified by the gate's generic name, never by a tool:
# typecheck|type-check|types|analyse|analyze|static, then lint, then test. A
# name that watches or fixes is not a gate, and neither is an install step.
#
# Exit: 0 (an empty list is an answer, not an error) · 1 usage error or no jq
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
SUB_DIR=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --dir)
      [ $# -ge 2 ] || die "--dir requires a path"
      SUB_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

ROOT="$(repo_root)"
SUB_DIR="${SUB_DIR#./}"
SUB_DIR="${SUB_DIR%/}"
[ "$SUB_DIR" = "." ] && SUB_DIR=""

SCAN_DIR="$ROOT"
REL_PREFIX=""
if [ -n "$SUB_DIR" ]; then
  SCAN_DIR="$ROOT/$SUB_DIR"
  REL_PREFIX="$SUB_DIR/"
fi
[ -d "$SCAN_DIR" ] || die "directory not found: $SCAN_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

CANDIDATES=""

# Records one candidate: kind, command, source. The order of the calls is the
# order of authority, which the dedupe below relies on.
add_candidate() {
  CANDIDATES="${CANDIDATES}$1	$2	$3
"
}

# Prints `cd <dir> && <command>`, or the command alone at the root. The two
# directories compose: `--dir api` and a step's `working-directory: web` give
# `cd api/web && …`.
in_dir() {
  local dir="$1" cmd="$2"
  dir="${dir#./}"
  dir="${dir%/}"
  if [ -n "$SUB_DIR" ]; then
    if [ -z "$dir" ] || [ "$dir" = "." ]; then dir="$SUB_DIR"; else dir="$SUB_DIR/$dir"; fi
  fi
  if [ -z "$dir" ] || [ "$dir" = "." ]; then
    printf '%s' "$cmd"
  else
    printf 'cd %s && %s' "$dir" "$cmd"
  fi
}

# Prints the kind of gate a name or a command line stands for, or nothing. By
# the gate's generic name only: the script must not need to know a tool to
# recognise a project's gate.
classify() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

  # A watcher never exits, a fixer rewrites the tree: neither is a check.
  if printf '%s' "$lower" | grep -qE 'watch|(^|[^a-z])fix([^a-z]|$)'; then
    return 0
  fi

  if printf '%s' "$lower" | grep -qE 'typecheck|type-check|types|analy[sz]e|static'; then
    printf 'typecheck'
  elif printf '%s' "$lower" | grep -q 'lint'; then
    printf 'lint'
  elif printf '%s' "${lower//latest/}" | grep -q 'test'; then
    printf 'test'
  fi
}

# True when a command line only prepares the environment: an install, a
# dependency fetch, an echo. These sit next to the gates in every CI file.
is_setup_line() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$lower" | grep -qE \
    '^(echo|printf|export|git|curl|wget|apt|apt-get|brew|sudo|cat|ls|mkdir|cp|mv|rm|source|\.)( |$)|^(npm|pnpm|yarn|bun|composer|pip[0-9.]*|pipx|poetry|uv|pdm|bundle|gem|cargo|go|mix|dotnet|flutter|dart) (ci|install|i|add|get|deps\.get|fetch|sync|restore|pub get|mod download)( |$)'
}

# Feeds the `<dir>\037<command>` lines a reader printed through the filters, and
# records each one that names a gate. The separator is the ASCII unit
# separator, not a tab: `read` collapses a leading tab, and an empty directory —
# a command run at the root — is the common case.
take_lines() {
  local source="$1" dir cmd kind
  while IFS=$'\037' read -r dir cmd; do
    [ -n "$cmd" ] || continue
    is_setup_line "$cmd" && continue
    kind=$(classify "$cmd")
    [ -n "$kind" ] || continue
    add_candidate "$kind" "$(in_dir "$dir" "$cmd")" "$source"
  done
}

# Records one runner target or package script: the kind is read off its name,
# and the command is the runner plus the name.
take_named() {
  local source="$1" runner="$2" name kind
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    kind=$(classify "$name")
    [ -n "$kind" ] || continue
    add_candidate "$kind" "$(in_dir "" "$runner $name")" "$source"
  done
}

# ── 1. CI: what gates the merge ───────────────────────────────────────────────
#
# YAML read line by line — no parser, so the dependency contract stays bash +
# jq. What is understood is the shape a workflow is written in: jobs, steps as
# list items, `run:` on one line or as a `|`/`>` block, and `working-directory`
# on a step, under a job's `defaults.run`, or under the workflow's.

github_runs() {
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function unquote(s) {
      if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
      return s
    }
    function value(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); return unquote(trim(s)) }
    # A step ends: its runs join the job, each with the step own directory.
    function flush(  k) {
      for (k = 1; k <= nrun; k++) { jcmd[++njob] = runs[k]; jwd[njob] = step_wd }
      nrun = 0; step_wd = ""; in_step = 0
    }
    # A job ends: only now is its `defaults.run` known, wherever it was written.
    function flush_job(  k, w) {
      flush()
      for (k = 1; k <= njob; k++) {
        w = jwd[k] != "" ? jwd[k] : (job_wd != "" ? job_wd : wf_wd)
        print w "\037" jcmd[k]
      }
      njob = 0; job_wd = ""
    }
    {
      line = $0; sub(/\r$/, "", line)
      i = ind(line); t = trim(line)

      if (in_block) {
        if (t == "") next
        if (i > block_ind) { if (t !~ /^#/) runs[++nrun] = t; next }
        in_block = 0
      }
      if (t == "" || t ~ /^#/) next

      if (in_steps && i <= steps_ind && t !~ /^- /) { flush(); in_steps = 0 }
      if (in_jobs && i <= jobs_ind) { flush_job(); in_jobs = 0; job_ind = -1 }

      if (t ~ /^jobs:[ \t]*$/) { flush_job(); in_jobs = 1; jobs_ind = i; job_ind = -1; next }
      if (in_jobs && job_ind < 0 && i > jobs_ind) job_ind = i
      if (in_jobs && i == job_ind && t ~ /^[^ ]+:[ \t]*$/) {
        flush_job(); in_steps = 0; next
      }
      if (t ~ /^steps:[ \t]*$/) { flush(); in_steps = 1; steps_ind = i; next }

      key_ind = i
      if (in_steps && t ~ /^- /) {
        flush(); in_step = 1; step_ind = i
        t = trim(substr(t, 3)); key_ind = i + 2
      }

      if (t ~ /^working-directory:/) {
        if (in_step && key_ind > step_ind) step_wd = value(t)
        else if (in_jobs) job_wd = value(t)
        else wf_wd = value(t)
        next
      }
      if (in_step && t ~ /^run:/) {
        v = value(t)
        if (v ~ /^[|>][-+]?$/) { in_block = 1; block_ind = key_ind }
        else if (v != "") runs[++nrun] = v
      }
    }
    END { flush_job() }
  ' "$1"
}

gitlab_scripts() {
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function unquote(s) {
      if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
      return s
    }
    {
      line = $0; sub(/\r$/, "", line)
      i = ind(line); t = trim(line)
      if (t == "" || t ~ /^#/) next
      if (in_script) {
        if (t ~ /^- / && i >= script_ind) {
          item = unquote(trim(substr(t, 3)))
          if (item !~ /^[|>]/) print "\037" item
          next
        }
        if (i <= script_ind) in_script = 0
      }
      if (t ~ /^script:/) {
        v = t; sub(/^script:[ \t]*/, "", v)
        if (v == "") { in_script = 1; script_ind = i }
        else if (v !~ /^\[/) print "\037" unquote(v)
      }
    }
  ' "$1"
}

# Every reader feeds its take_* through `< <(…)`, never through a pipe: the
# right side of a pipe runs in a subshell, and the candidates it recorded would
# be gone when it returned.

if [ -d "$SCAN_DIR/.github/workflows" ]; then
  while IFS= read -r WORKFLOW; do
    [ -n "$WORKFLOW" ] || continue
    take_lines "ci:${REL_PREFIX}.github/workflows/$(basename "$WORKFLOW")" \
      < <(github_runs "$WORKFLOW")
  done < <(find "$SCAN_DIR/.github/workflows" -maxdepth 1 -type f \
             \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | LC_ALL=C sort)
fi

if [ -f "$SCAN_DIR/.gitlab-ci.yml" ]; then
  take_lines "ci:${REL_PREFIX}.gitlab-ci.yml" < <(gitlab_scripts "$SCAN_DIR/.gitlab-ci.yml")
fi

# ── 2. Task runners ───────────────────────────────────────────────────────────

# Rule lines: `target:` or `a b: deps`, never a `:=` assignment, a special
# `.TARGET` or a `%` pattern rule.
makefile_targets() {
  awk '
    /^[A-Za-z0-9][A-Za-z0-9_.\/ -]*:/ && $0 !~ /^[^:]*:[:!]?=/ {
      names = $0; sub(/:.*/, "", names)
      n = split(names, parts, /[ \t]+/)
      for (k = 1; k <= n; k++) if (parts[k] != "" && parts[k] !~ /%/) print parts[k]
    }
  ' "$1"
}

justfile_recipes() {
  awk '
    /^(set|alias|export|import|mod)[ \t]/ { next }
    /^@?[A-Za-z0-9_-]+[^:=]*:/ && $0 !~ /:=/ {
      name = $0; sub(/^@/, "", name); sub(/[ \t:].*/, "", name); print name
    }
  ' "$1"
}

# The keys right under `tasks:`, at the first indentation found there.
taskfile_tasks() {
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    /^tasks:[ \t]*$/ { in_tasks = 1; task_ind = -1; next }
    in_tasks && /^[^ #]/ { in_tasks = 0 }
    in_tasks && /^ +[^ #-][^:]*:/ {
      i = ind($0)
      if (task_ind < 0) task_ind = i
      if (i == task_ind) {
        name = $0; sub(/^ +/, "", name); sub(/:.*/, "", name)
        gsub(/["\047]/, "", name); print name
      }
    }
  ' "$1"
}

if [ -f "$SCAN_DIR/Makefile" ]; then
  take_named "runner:${REL_PREFIX}Makefile" make < <(makefile_targets "$SCAN_DIR/Makefile")
fi

for JUSTFILE in justfile Justfile; do
  [ -f "$SCAN_DIR/$JUSTFILE" ] || continue
  take_named "runner:${REL_PREFIX}$JUSTFILE" just < <(justfile_recipes "$SCAN_DIR/$JUSTFILE")
  break
done

for TASKFILE in Taskfile.yml Taskfile.yaml; do
  [ -f "$SCAN_DIR/$TASKFILE" ] || continue
  take_named "runner:${REL_PREFIX}$TASKFILE" task < <(taskfile_tasks "$SCAN_DIR/$TASKFILE")
  break
done

# ── 3. The package manager's scripts ──────────────────────────────────────────

# The heuristics are read once: their PKG_MANAGER gives the npm runner prefix
# (the same one detect-stack.sh uses for its own answers), and their commands
# are section 5.
HEURISTIC=$(bash "$SCRIPT_DIR/detect-stack.sh" --json --no-declaration --dir "$SCAN_DIR" 2>/dev/null) \
  || { warn "detect-stack.sh failed: no heuristic candidate"; HEURISTIC='{}'; }
heuristic_get() { printf '%s' "$HEURISTIC" | jq -r --arg k "$1" '.[$k] // empty'; }

script_names() { jq -r '(.scripts // {}) | keys_unsorted[]' "$1" 2>/dev/null; }

# `[tool.poe.tasks]` with `name = …` keys, or one `[tool.poe.tasks.name]` table
# per task; the same two shapes for pdm. Keys starting with `_` are pdm
# settings, not scripts.
pyproject_names() {
  awk -v table="$2" '
    /^\[/ {
      header = $0; gsub(/^\[+|\]+.*$/, "", header); gsub(/[ \t"]/, "", header)
      in_table = (header == table)
      if (index(header, table ".") == 1) {
        name = substr(header, length(table) + 2); sub(/\..*/, "", name)
        if (name !~ /^_/ && !(name in seen)) { seen[name] = 1; print name }
      }
      next
    }
    in_table && /^[A-Za-z0-9_-]+[ \t]*=/ {
      name = $0; sub(/[ \t]*=.*/, "", name)
      if (name !~ /^_/ && !(name in seen)) { seen[name] = 1; print name }
    }
  ' "$1"
}

if [ -f "$SCAN_DIR/package.json" ]; then
  case "$(heuristic_get PKG_MANAGER)" in
    pnpm) NPM_RUN="pnpm run" ;;
    yarn) NPM_RUN="yarn" ;;
    bun)  NPM_RUN="bun run" ;;
    *)    NPM_RUN="npm run" ;;
  esac
  take_named "scripts:${REL_PREFIX}package.json" "$NPM_RUN" \
    < <(script_names "$SCAN_DIR/package.json")
fi

if [ -f "$SCAN_DIR/composer.json" ]; then
  take_named "scripts:${REL_PREFIX}composer.json" composer \
    < <(script_names "$SCAN_DIR/composer.json")
fi

if [ -f "$SCAN_DIR/pyproject.toml" ]; then
  take_named "scripts:${REL_PREFIX}pyproject.toml" poe \
    < <(pyproject_names "$SCAN_DIR/pyproject.toml" tool.poe.tasks)
  take_named "scripts:${REL_PREFIX}pyproject.toml" "pdm run" \
    < <(pyproject_names "$SCAN_DIR/pyproject.toml" tool.pdm.scripts)
fi

# ── 4. The docs ───────────────────────────────────────────────────────────────
#
# Only the shell blocks — an unlabelled fence or a bash/sh/shell/console/zsh
# one. A JSON block holding `"lint": …` is configuration, not a command.

doc_commands() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    /^[ \t]*(```|~~~)/ {
      if (in_fence) { in_fence = 0; next }
      lang = trim($0); sub(/^(```|~~~)+/, "", lang); lang = tolower(trim(lang))
      in_fence = 1
      shell = (lang == "" || lang ~ /^(bash|sh|shell|console|zsh)$/)
      next
    }
    in_fence && shell {
      t = trim($0); sub(/^\$[ \t]+/, "", t)
      if (t != "" && t !~ /^#/) print "\037" t
    }
  ' "$1"
}

for DOC in README.md AGENTS.md; do
  [ -f "$SCAN_DIR/$DOC" ] || continue
  take_lines "docs:${REL_PREFIX}$DOC" < <(doc_commands "$SCAN_DIR/$DOC")
done

# ── 5. The heuristics, last ───────────────────────────────────────────────────

for KIND in lint typecheck test; do
  case "$KIND" in
    lint) CMD=$(heuristic_get LINT_CMD) ;;
    typecheck) CMD=$(heuristic_get TYPECHECK_CMD) ;;
    test) CMD=$(heuristic_get TEST_CMD) ;;
  esac
  [ -n "$CMD" ] && add_candidate "$KIND" "$(in_dir "" "$CMD")" "heuristic:detect-stack.sh"
done

# ── Output ────────────────────────────────────────────────────────────────────

# Once per command, the first source that yielded it: the order above is the
# order of authority, so the CI wins over the Makefile that defines the same
# target and the README that repeats it.
UNIQUE=$(printf '%s' "$CANDIDATES" | awk -F'\t' 'NF >= 3 && !seen[$2]++')

of_kind() { printf '%s\n' "$UNIQUE" | awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3 }'; }

json_set LINT_CANDIDATES "$(of_kind lint)"
json_set TYPECHECK_CANDIDATES "$(of_kind typecheck)"
json_set TEST_CANDIDATES "$(of_kind test)"
json_set CANDIDATE_COUNT "$(printf '%s' "$UNIQUE" | grep -c . || true)"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
