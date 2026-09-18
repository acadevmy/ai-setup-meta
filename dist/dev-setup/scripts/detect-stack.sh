#!/usr/bin/env bash
# detect-stack.sh — deterministic stack detection for the dev-setup plugin.
#
# Replaces the prose detection the setup skill used to re-interpret on every run
# (the setup skill's Step 2). Reads only files already on disk: no network, no
# package installation, no `.env*` access.
#
# Usage:
#   detect-stack.sh [--json] [--dir <path>]
#
#   --json        emit a flat JSON object (the machine contract)
#   --dir <path>  inspect <path> instead of the current directory
#
# Keys:
#   LANG            comma-separated list of detected languages, or "unknown"
#   FRAMEWORKS      comma-separated list of detected frameworks, or "" if none
#   PKG_MANAGER     pnpm | yarn | npm | bun | pub | pip | poetry | go | cargo | ""
#   VCS             git | none
#   MONOREPO        the monorepo tool (nx, turborepo, pnpm-workspace, lerna,
#                   npm-workspaces, structural) or "" for a single project
#   HAS_FRONTEND    true | false
#   HAS_MOBILE      true | false
#   HAS_INFRA       true | false
#   SERVICES_GLOB   glob matching the business-logic layer, or "" when the
#                   project has no backend (used to instantiate the
#                   backend-services path-scoped rule)
#   TEST_CMD        the test command, or "" when none was detected
#   LINT_CMD        the lint command, or "" when none was detected
#   TYPECHECK_CMD   the type-check command, or "" when none was detected
#   HOOK_MANAGER    husky | lefthook | simple-git-hooks | custom-hookspath | ""
#
# A missing value is always the empty string, never a message: the consumer
# tests for emptiness. Exits non-zero only on a real error (bad flag, missing
# jq, unreadable directory).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

AS_JSON=false
TARGET_DIR="."

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --dir)
      [ $# -ge 2 ] || die "--dir requires a path"
      TARGET_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -d "$TARGET_DIR" ] || die "directory not found: $TARGET_DIR"
cd "$TARGET_DIR" || die "cannot enter: $TARGET_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

# True when the given package.json declares the dependency (any block).
has_dep_in() {
  local pkg="$1" dep="$2"
  [ -f "$pkg" ] || return 1
  jq -e --arg d "$dep" '
    (.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {})
    | has($d)
  ' "$pkg" >/dev/null 2>&1
}

# The same test against the root package.json.
has_dep() {
  has_dep_in package.json "$1"
}

# True when package.json declares the given npm script.
has_script() {
  local name="$1"
  [ -f package.json ] || return 1
  jq -e --arg s "$name" '(.scripts // {}) | has($s)' package.json >/dev/null 2>&1
}

# Prints the body of an npm script.
script_body() {
  local name="$1"
  [ -f package.json ] || return 1
  jq -r --arg s "$name" '(.scripts // {})[$s] // empty' package.json 2>/dev/null
}

# True when the given pyproject.toml table is present.
has_pyproject_table() {
  [ -f pyproject.toml ] && grep -q "^\[$1\]" pyproject.toml 2>/dev/null
}

# True when at least one file matching the glob exists at depth <= 2, skipping
# the dependency and build directories.
has_file_at_depth() {
  local pattern="$1" found
  found=$(find . -maxdepth 2 -name "$pattern" -not -path '*/node_modules/*' \
    -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' \
    -print -quit 2>/dev/null)
  [ -n "$found" ]
}

# Prints the comma-separated list with the value appended, skipping duplicates.
# Written as a filter rather than by reference: bash 3.2 (the system bash on
# macOS) has no namerefs.
append_csv() {
  local acc="$1" value="$2"
  case ",$acc," in
    *",$value,"*) printf '%s' "$acc"; return 0 ;;
  esac
  if [ -z "$acc" ]; then printf '%s' "$value"; else printf '%s,%s' "$acc" "$value"; fi
}

# ── Languages ─────────────────────────────────────────────────────────────────

LANGS=""
[ -f package.json ] && LANGS=$(append_csv "$LANGS" node)
{ [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && LANGS=$(append_csv "$LANGS" python)
[ -f go.mod ] && LANGS=$(append_csv "$LANGS" go)
[ -f pubspec.yaml ] && LANGS=$(append_csv "$LANGS" flutter)
[ -f Cargo.toml ] && LANGS=$(append_csv "$LANGS" rust)
has_file_at_depth '*.tf' && LANGS=$(append_csv "$LANGS" terraform)
[ -z "$LANGS" ] && LANGS="unknown"

lang_has() { case ",$LANGS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# ── Frameworks ────────────────────────────────────────────────────────────────
#
# Detected by dependency, most specific first: a Next.js project also declares
# react, and reporting both would make the consumer disambiguate again.
#
# In a monorepo the root package.json usually holds only the workspace tooling,
# so the sub-projects are scanned too. Without that, a workspace with a Next app
# under applications/web reported no framework and HAS_FRONTEND=false.

FRAMEWORKS=""

detect_frameworks_in() {
  local pkg="$1"
  [ -f "$pkg" ] || return 0

  if has_dep_in "$pkg" next; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" nextjs)
  elif has_dep_in "$pkg" nuxt; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" nuxt)
  elif has_dep_in "$pkg" '@angular/core'; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" angular)
  elif has_dep_in "$pkg" svelte; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" svelte)
  elif has_dep_in "$pkg" vue; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" vue)
  elif has_dep_in "$pkg" react; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" react)
  fi

  has_dep_in "$pkg" '@nestjs/core' && FRAMEWORKS=$(append_csv "$FRAMEWORKS" nestjs)
  has_dep_in "$pkg" express && FRAMEWORKS=$(append_csv "$FRAMEWORKS" express)
  has_dep_in "$pkg" fastify && FRAMEWORKS=$(append_csv "$FRAMEWORKS" fastify)

  if has_dep_in "$pkg" expo; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" expo)
  elif has_dep_in "$pkg" react-native; then FRAMEWORKS=$(append_csv "$FRAMEWORKS" react-native)
  fi
}

detect_frameworks_in package.json

# Sub-projects, at the depth a workspace normally uses (applications/web,
# packages/ui, apps/api). node_modules is excluded: every dependency in there
# ships its own package.json.
#
# The result is sorted: `find` walks in filesystem order, which differs between
# macOS and Linux, and that would make FRAMEWORKS come out in a different order
# on the same project. The output of this script is a contract — it has to be
# reproducible, not merely correct.
while IFS= read -r SUB_PKG; do
  [ -n "$SUB_PKG" ] || continue
  detect_frameworks_in "$SUB_PKG"
done < <(find . -mindepth 2 -maxdepth 3 -name package.json \
  -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/.next/*' 2>/dev/null | LC_ALL=C sort)

# A pubspec.yaml in a sub-project means a Flutter app in the workspace.
if [ -z "$(find . -maxdepth 1 -name pubspec.yaml 2>/dev/null)" ]; then
  if find . -mindepth 2 -maxdepth 3 -name pubspec.yaml -not -path '*/node_modules/*' \
    -print -quit 2>/dev/null | grep -q .; then
    FRAMEWORKS=$(append_csv "$FRAMEWORKS" flutter)
  fi
fi

lang_has flutter && FRAMEWORKS=$(append_csv "$FRAMEWORKS" flutter)
lang_has terraform && FRAMEWORKS=$(append_csv "$FRAMEWORKS" terraform)

if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  grep -qi 'django' requirements.txt pyproject.toml 2>/dev/null && FRAMEWORKS=$(append_csv "$FRAMEWORKS" django)
  grep -qi 'fastapi' requirements.txt pyproject.toml 2>/dev/null && FRAMEWORKS=$(append_csv "$FRAMEWORKS" fastapi)
fi

framework_has() { case ",$FRAMEWORKS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# ── Package manager ───────────────────────────────────────────────────────────
#
# The lockfile wins over `packageManager`: it is what the installed tree was
# actually produced with.

PKG_MANAGER=""
if [ -f pnpm-lock.yaml ]; then PKG_MANAGER="pnpm"
elif [ -f yarn.lock ]; then PKG_MANAGER="yarn"
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PKG_MANAGER="bun"
elif [ -f package-lock.json ]; then PKG_MANAGER="npm"
elif [ -f package.json ]; then
  PKG_MANAGER=$(jq -r '.packageManager // empty' package.json 2>/dev/null | cut -d@ -f1)
  [ -z "$PKG_MANAGER" ] && PKG_MANAGER="npm"
elif [ -f pubspec.yaml ]; then PKG_MANAGER="pub"
elif [ -f poetry.lock ] || has_pyproject_table 'tool.poetry'; then PKG_MANAGER="poetry"
elif [ -f requirements.txt ]; then PKG_MANAGER="pip"
elif [ -f go.mod ]; then PKG_MANAGER="go"
elif [ -f Cargo.toml ]; then PKG_MANAGER="cargo"
fi

# The runner prefix for npm scripts, per package manager.
run_prefix() {
  case "$PKG_MANAGER" in
    pnpm) printf 'pnpm run' ;;
    yarn) printf 'yarn' ;;
    bun)  printf 'bun run' ;;
    *)    printf 'npm run' ;;
  esac
}

# ── Monorepo ──────────────────────────────────────────────────────────────────

MONOREPO=""
if [ -f nx.json ]; then MONOREPO="nx"
elif [ -f turbo.json ]; then MONOREPO="turborepo"
elif [ -f pnpm-workspace.yaml ]; then MONOREPO="pnpm-workspace"
elif [ -f lerna.json ]; then MONOREPO="lerna"
elif [ -f package.json ] && jq -e 'has("workspaces")' package.json >/dev/null 2>&1; then
  MONOREPO="npm-workspaces"
else
  # Structural fallback: two or more top-level directories carrying a project
  # marker. Non-project directories are skipped.
  MARKER_DIRS=0
  for dir in */; do
    [ -d "$dir" ] || continue
    case "${dir%/}" in
      node_modules|.git|.claude|dist|build|coverage|.github|.husky|.next|vendor|target) continue ;;
    esac
    for marker in package.json pubspec.yaml go.mod pyproject.toml requirements.txt Cargo.toml; do
      if [ -f "$dir$marker" ]; then
        MARKER_DIRS=$((MARKER_DIRS + 1))
        break
      fi
    done
  done
  [ "$MARKER_DIRS" -ge 2 ] && MONOREPO="structural"
fi

# ── Capability flags ──────────────────────────────────────────────────────────

HAS_FRONTEND=false
if framework_has nextjs || framework_has nuxt || framework_has angular \
  || framework_has vue || framework_has svelte || framework_has react; then
  HAS_FRONTEND=true
elif find . -maxdepth 3 \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' \) \
  -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
  HAS_FRONTEND=true
fi

HAS_MOBILE=false
if framework_has flutter || framework_has expo || framework_has react-native; then
  HAS_MOBILE=true
fi

HAS_INFRA=false
lang_has terraform && HAS_INFRA=true

# ── Service-layer glob ────────────────────────────────────────────────────────
#
# Feeds the `paths:` frontmatter of the backend-services rule, which is the one
# governance file that cannot be scoped by extension: "the business logic" is a
# layout, not a file type. Two shapes cover what the team writes — the NestJS
# suffix convention, and the directory convention everything else uses.
#
# Kept to a handful of brace groups on purpose: a rule's whole `paths` list has
# a budget of 1000 expanded patterns, and a pattern that blows it is used
# unexpanded, which matches nothing.

SERVICES_GLOB=""
if framework_has nestjs; then
  SERVICES_GLOB='**/*.{service,controller,repository,resolver,guard,interceptor}.ts'
elif framework_has express || framework_has fastify; then
  SERVICES_GLOB='**/{services,controllers,repositories,routes,handlers,use-cases}/**/*.{ts,js}'
elif framework_has django || framework_has fastapi; then
  SERVICES_GLOB='**/{services,views,repositories,api,use_cases}/**/*.py'
elif lang_has go; then
  SERVICES_GLOB='**/{internal,pkg}/**/*.go'
elif lang_has node && [ "$HAS_FRONTEND" = false ] && [ "$HAS_MOBILE" = false ]; then
  # A Node project that is neither a frontend nor an app is a backend even when
  # no framework was recognised (a plain http server, a worker, a CLI daemon).
  SERVICES_GLOB='**/{services,controllers,repositories,routes,handlers,use-cases}/**/*.{ts,js,mts}'
fi

# ── Quality commands ──────────────────────────────────────────────────────────
#
# An npm script wins over the bare binary: the project's own script carries the
# flags the project needs.

TEST_CMD=""
if has_script test; then
  # A placeholder `test` script ("no test specified") is not a test command.
  body=$(script_body test)
  case "$body" in
    *'no test specified'*|*'Error: no test'*) TEST_CMD="" ;;
    *) TEST_CMD="$(run_prefix) test" ;;
  esac
fi
if [ -z "$TEST_CMD" ]; then
  if has_dep vitest; then TEST_CMD="npx vitest run"
  elif has_dep jest; then TEST_CMD="npx jest"
  elif [ -f pubspec.yaml ]; then TEST_CMD="flutter test"
  elif [ -f pytest.ini ] || has_pyproject_table 'tool.pytest.ini_options'; then TEST_CMD="pytest"
  elif [ -f go.mod ]; then TEST_CMD="go test ./..."
  elif [ -f Cargo.toml ]; then TEST_CMD="cargo test"
  elif lang_has terraform; then TEST_CMD="terraform validate"
  fi
fi

LINT_CMD=""
if has_script lint; then
  LINT_CMD="$(run_prefix) lint"
elif [ -f eslint.config.js ] || [ -f eslint.config.mjs ] || [ -f eslint.config.cjs ] \
  || [ -f eslint.config.ts ] || has_dep eslint; then
  LINT_CMD="npx eslint ."
elif [ -f analysis_options.yaml ]; then LINT_CMD="dart analyze"
elif has_pyproject_table 'tool.ruff'; then LINT_CMD="ruff check ."
elif [ -f .flake8 ]; then LINT_CMD="flake8"
elif [ -f .golangci.yml ] || [ -f .golangci.yaml ]; then LINT_CMD="golangci-lint run"
elif [ -f Cargo.toml ]; then LINT_CMD="cargo clippy"
elif lang_has terraform; then LINT_CMD="terraform fmt -check -recursive"
fi

TYPECHECK_CMD=""
for candidate in typecheck type-check tsc; do
  if has_script "$candidate"; then
    TYPECHECK_CMD="$(run_prefix) $candidate"
    break
  fi
done
if [ -z "$TYPECHECK_CMD" ]; then
  if [ -f tsconfig.json ]; then TYPECHECK_CMD="npx tsc --noEmit"
  elif [ -f pubspec.yaml ]; then TYPECHECK_CMD="flutter analyze"
  elif has_pyproject_table 'tool.mypy' || [ -f mypy.ini ]; then TYPECHECK_CMD="mypy ."
  elif [ -f go.mod ]; then TYPECHECK_CMD="go build ./..."
  elif [ -f Cargo.toml ]; then TYPECHECK_CMD="cargo check"
  fi
fi

# In a monorepo the commands must run from the workspace root. Nx and Turborepo
# expose a root-level task runner that fans out across the projects, and that
# beats the single-language fallbacks above: on an Nx workspace holding both a
# Next app and a Terraform module, `terraform validate` is not the test command.
# An explicit root script still wins — the project wrote it on purpose.
#
# The workspace managers (pnpm/yarn/npm/lerna) need a filter per package, which
# only the caller knows, so there the root script is used as-is.
case "$MONOREPO" in
  nx)
    has_script test      || TEST_CMD="npx nx run-many -t test"
    has_script lint      || LINT_CMD="npx nx run-many -t lint"
    if ! has_script typecheck && ! has_script type-check; then
      TYPECHECK_CMD="npx nx run-many -t typecheck"
    fi
    ;;
  turborepo)
    has_script test      || TEST_CMD="npx turbo run test"
    has_script lint      || LINT_CMD="npx turbo run lint"
    if ! has_script typecheck && ! has_script type-check; then
      TYPECHECK_CMD="npx turbo run typecheck"
    fi
    ;;
esac

# ── Hook manager ──────────────────────────────────────────────────────────────
#
# Decision 9: when the project already owns a hook manager, the Claude-side
# commit gate stands down to anti-bypass and lets that tooling run the
# per-commit checks. Detection has to be reliable in both directions.

HOOK_MANAGER=""
HOOKS_PATH=$(git config --get core.hooksPath 2>/dev/null || true)

if [ -d .husky ] || has_dep husky; then
  HOOK_MANAGER="husky"
elif [ -f lefthook.yml ] || [ -f lefthook.yaml ] || [ -f .lefthook.yml ] \
  || [ -f .lefthook.yaml ] || has_dep lefthook || has_dep '@evilmartians/lefthook'; then
  HOOK_MANAGER="lefthook"
elif [ -f .simple-git-hooks.json ] || has_dep simple-git-hooks \
  || { [ -f package.json ] && jq -e 'has("simple-git-hooks")' package.json >/dev/null 2>&1; }; then
  HOOK_MANAGER="simple-git-hooks"
elif [ -n "$HOOKS_PATH" ] && [ "$HOOKS_PATH" != ".git/hooks" ]; then
  HOOK_MANAGER="custom-hookspath"
elif [ -f .git/hooks/pre-commit ] && [ -x .git/hooks/pre-commit ]; then
  # A hand-written, executable pre-commit hook is a project gate too.
  HOOK_MANAGER="custom-hookspath"
fi

# ── Output ────────────────────────────────────────────────────────────────────

json_set LANG "$LANGS"
json_set FRAMEWORKS "$FRAMEWORKS"
json_set PKG_MANAGER "$PKG_MANAGER"
json_set VCS "$(detect_vcs)"
json_set MONOREPO "$MONOREPO"
json_set HAS_FRONTEND "$HAS_FRONTEND"
json_set HAS_MOBILE "$HAS_MOBILE"
json_set HAS_INFRA "$HAS_INFRA"
json_set SERVICES_GLOB "$SERVICES_GLOB"
json_set TEST_CMD "$TEST_CMD"
json_set LINT_CMD "$LINT_CMD"
json_set TYPECHECK_CMD "$TYPECHECK_CMD"
json_set HOOK_MANAGER "$HOOK_MANAGER"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
