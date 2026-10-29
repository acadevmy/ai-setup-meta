#!/usr/bin/env bash
# devcontainer-facts.sh — what a repository already says about the environment
# its quality commands need: the toolchain versions it pins, the images and
# services its CI runs on, the Docker files it already has, the services its
# `.env.example` points at, and the dependencies an install has to fetch with
# credentials.
#
# The `devcontainer` command proposes a `.devcontainer/` for the job runner of
# the headless `auto-dev` runs, which runs `devcontainer up` at the repository
# root and the quality commands inside it. The proposal is judgement; what it
# starts from is not, so it is read here, the same way every time. Every
# version comes with the file that pins it, so two files that disagree are both
# on the table.
#
# Read-only, and it never opens `.env`: every input is a tracked file. A URL
# is printed with its user information masked.
#
# Usage:
#   devcontainer-facts.sh [--json]
#
# Keys:
#   CONFIG          the configuration a `devcontainer up` with no `--config`
#                   reads at the root — `.devcontainer/devcontainer.json`, else
#                   `.devcontainer.json` — or empty
#   NESTED_CONFIGS  one `.devcontainer/<name>/devcontainer.json` per line: the
#                   runner reads none of them
#   VERSIONS        one `<tool>\t<version>\t<file>` line per pin: .tool-versions,
#                   .nvmrc, .node-version, package.json (engines.node, volta,
#                   packageManager), composer.json (require.php,
#                   config.platform.php), pubspec.yaml (environment.sdk as
#                   dart, environment.flutter), .fvmrc, .fvm/fvm_config.json,
#                   .python-version, .ruby-version, .java-version, go.mod
#   PHP_EXTENSIONS  the `ext-*` names composer.json requires, space-separated
#   PHP_COVERAGE    true when the PHP tests measure coverage (a `<report>` in
#                   phpunit.xml, `coverage` in a composer script or in the
#                   declared test command): the image then needs pcov
#   TEST_ENV        one `<NAME>=<value>\t<file>` line per `<env>`/`<server>` of
#                   phpunit.xml: what the tests set for themselves (an
#                   in-memory sqlite needs no database service)
#   CI_IMAGES       one `<image>\t<job|service>\t<file>` line per image the CI
#                   runs a job in or starts as a service
#   DOCKERFILES     the Dockerfiles outside `.devcontainer/`, one per line
#   COMPOSE_FILES   the compose files outside `.devcontainer/`, one per line
#   ENV_EXAMPLES    the `.env.example`, `.env.dist` and `.env.sample` files
#   ENV_SERVICES    one `<service>\t<file>:<KEY>` line per service an example
#                   environment file points at (mysql, postgres, redis, …)
#   PRIVATE_DEPS    one `<file>\t<what>` line per dependency fetched from a
#                   git host or a private registry: its install needs the
#                   credentials, which the runner holds only during `up`
#   TESTCONTAINERS  one `<file>\t<dependency>` line per Testcontainers
#                   library (npm, Composer, Maven, Gradle, Go, Python, .NET,
#                   Cargo), at the root and in every package: those tests
#                   need the Docker socket, which the runner refuses, so the
#                   repository is not run on GCP
#   REPOSITORY      owner/repo from origin, as auto-dev-select.sh names it
#
# Every path is relative to the repository root. The search goes three levels
# down and skips the dependency, build and VCS directories, so a monorepo's
# packages are read with the root.
#
# Exit: 0 (an empty key is an answer, not an error) · 1 usage error or no jq
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

ROOT="$(repo_root)"
cd "$ROOT" || die "cannot enter the repository root: $ROOT"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Prints the files matching one of the names, three levels down, relative to
# the root and sorted, skipping what no image is built from.
find_named() {
  local -a names=()
  local name
  for name in "$@"; do
    [ ${#names[@]} -eq 0 ] || names+=(-o)
    names+=(-name "$name")
  done
  find . -maxdepth 4 \
    \( -name node_modules -o -name vendor -o -name .git -o -name dist -o -name build \
       -o -name .dart_tool -o -name .venv -o -name venv -o -name Pods -o -name .next \
       -o -name coverage -o -name .devcontainer \) -prune \
    -o -type f \( "${names[@]}" \) -print 2>/dev/null \
    | sed 's|^\./||' | LC_ALL=C sort
}

trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# A URL's user information can hold a token: it is never printed.
mask_url() { sed -E 's#(://)[^/@[:space:]]+@#\1***@#g'; }

VERSIONS=""
add_version() {
  local tool="$1" version="$2" file="$3"
  [ -n "$version" ] || return 0
  VERSIONS="${VERSIONS}${tool}	${version}	${file}
"
}

# ── The configuration the runner reads ────────────────────────────────────────

CONFIG=""
if [ -f .devcontainer/devcontainer.json ]; then
  CONFIG=".devcontainer/devcontainer.json"
elif [ -f .devcontainer.json ]; then
  CONFIG=".devcontainer.json"
fi
NESTED_CONFIGS=$(find .devcontainer -mindepth 2 -maxdepth 2 -name devcontainer.json 2>/dev/null \
  | sed 's|^\./||' | LC_ALL=C sort)

# ── Versions ──────────────────────────────────────────────────────────────────

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  # asdf's plugin names, folded to the names the other files use.
  while IFS=$'\t' read -r TOOL VERSION; do
    case "$TOOL" in nodejs) TOOL=node ;; golang) TOOL=go ;; esac
    add_version "$TOOL" "$VERSION" "$FILE"
  done < <(sed 's/#.*//' "$FILE" | awk 'NF >= 2 { print $1 "\t" $2 }')
done < <(find_named .tool-versions)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  add_version node "$(head -n 1 "$FILE" | sed 's/#.*//' | trim)" "$FILE"
done < <(find_named .nvmrc .node-version)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  add_version node "$(jq -r '.engines.node // empty' "$FILE" 2>/dev/null)" "$FILE"
  add_version node "$(jq -r '.volta.node // empty' "$FILE" 2>/dev/null)" "$FILE"
  PM=$(jq -r '.packageManager // empty' "$FILE" 2>/dev/null)
  if [ -n "$PM" ]; then
    PM="${PM%%+*}"
    add_version "${PM%%@*}" "${PM#*@}" "$FILE"
  fi
done < <(find_named package.json)

PHP_EXTENSIONS=""
COMPOSER_FILES=$(find_named composer.json)
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  add_version php "$(jq -r '.require.php // empty' "$FILE" 2>/dev/null)" "$FILE"
  add_version php "$(jq -r '.config.platform.php // empty' "$FILE" 2>/dev/null)" "$FILE"
  PHP_EXTENSIONS="$PHP_EXTENSIONS
$(jq -r '((.require // {}) + (."require-dev" // {})) | keys[] | select(startswith("ext-")) | ltrimstr("ext-")' \
    "$FILE" 2>/dev/null)"
done <<<"$COMPOSER_FILES"
PHP_EXTENSIONS=$(printf '%s\n' "$PHP_EXTENSIONS" | grep . | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')

# pubspec.yaml: the two keys of the `environment:` block.
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS=$'\t' read -r TOOL VERSION; do
    add_version "$TOOL" "$VERSION" "$FILE"
  done < <(awk '
    function unquote(s) { gsub(/^["\047]|["\047]$/, "", s); return s }
    /^environment:[ \t]*$/ { env = 1; next }
    env && /^[^ \t#]/ { env = 0 }
    env && /^[ \t]+sdk:/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); print "dart\t" unquote(v) }
    env && /^[ \t]+flutter:/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); print "flutter\t" unquote(v) }
  ' "$FILE")
done < <(find_named pubspec.yaml)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  add_version flutter "$(jq -r '.flutter // .flutterSdkVersion // empty' "$FILE" 2>/dev/null)" "$FILE"
done < <(find_named .fvmrc fvm_config.json)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  case "$(basename "$FILE")" in
    .python-version) TOOL=python ;;
    .ruby-version) TOOL=ruby ;;
    .java-version) TOOL=java ;;
  esac
  add_version "$TOOL" "$(head -n 1 "$FILE" | sed 's/#.*//' | trim)" "$FILE"
done < <(find_named .python-version .ruby-version .java-version)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  add_version go "$(awk '$1 == "go" { print $2; exit }' "$FILE")" "$FILE"
done < <(find_named go.mod)

# ── PHP coverage, and what the tests set for themselves ───────────────────────

PHPUNIT_FILES=$(find_named phpunit.xml phpunit.xml.dist)
PHP_COVERAGE=false
if [ -n "$PHPUNIT_FILES" ] || [ -n "$COMPOSER_FILES" ]; then
  while IFS= read -r FILE; do
    [ -n "$FILE" ] || continue
    grep -q '<report>' "$FILE" 2>/dev/null && PHP_COVERAGE=true
  done <<<"$PHPUNIT_FILES"
  while IFS= read -r FILE; do
    [ -n "$FILE" ] || continue
    jq -r '(.scripts // {}) | [.. | strings] | join("\n")' "$FILE" 2>/dev/null \
      | grep -qi 'coverage' && PHP_COVERAGE=true
  done <<<"$COMPOSER_FILES"
  DECLARED_TEST=$(jq -r '.test // empty' .claude/quality-commands.json 2>/dev/null)
  case "$DECLARED_TEST" in *[Cc]overage*) PHP_COVERAGE=true ;; esac
fi

TEST_ENV=""
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  TEST_ENV="${TEST_ENV}$(grep -oE '<(env|server)[[:space:]][^>]*>' "$FILE" 2>/dev/null \
    | sed -nE 's/.*name="([^"]*)".*value="([^"]*)".*/\1=\2/p' \
    | awk -v f="$FILE" '{ print $0 "\t" f }')
"
done <<<"$PHPUNIT_FILES"

# ── The CI's images ───────────────────────────────────────────────────────────

# GitHub Actions: `container:` (a scalar, or a block with `image:`) is the job's
# image, every `image:` under `services:` a service. GitLab CI: `image:` (a
# scalar, or a block with `name:`) is the job's, the items of `services:` (a
# scalar, or `- name:`) its services. An expression (`${{ … }}`, `$VAR`) is not
# an image anyone can pull.
ci_images() {
  awk -v f="$1" '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function value(s) {
      sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); s = trim(s)
      gsub(/^["\047]|["\047]$/, "", s); return s
    }
    function emit(img, role) { if (img != "" && img !~ /^\$/) print img "\t" role "\t" f }
    {
      line = $0; sub(/\r$/, "", line)
      i = ind(line); t = trim(line)
      if (t == "" || t ~ /^#/) next
      if (in_svc && i <= svc_ind) in_svc = 0
      if (in_img && i <= img_ind) in_img = 0
      if (t ~ /^services:[ \t]*$/) { in_svc = 1; svc_ind = i; svc_child = -1; next }
      if (in_svc && svc_child < 0) svc_child = i
      role = in_svc ? "service" : "job"
      # A list item directly under `services:` is a GitLab service; one deeper
      # (`ports: - 5432:5432`) is not an image.
      if (t ~ /^- /) {
        item = trim(substr(t, 3))
        if (in_svc && i == svc_child) {
          if (item ~ /^name:/) { emit(value(item), role); next }
          if (item !~ /:[ \t]/ && item !~ /:$/) { gsub(/^["\047]|["\047]$/, "", item); emit(item, role); next }
        }
        t = item; i = i + 2
      }
      if (t ~ /^(image|container):[ \t]*$/) { in_img = 1; img_ind = i; img_role = role; next }
      if (t ~ /^(image|container):/) { emit(value(t), role); next }
      if (t ~ /^name:/ && (in_img || in_svc)) { emit(value(t), in_img ? img_role : role); next }
    }
  ' "$1"
}

CI_IMAGES=""
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  CI_IMAGES="${CI_IMAGES}$(ci_images "$FILE")
"
done < <({ find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null \
             | sed 's|^\./||'; [ -f .gitlab-ci.yml ] && echo .gitlab-ci.yml; } | LC_ALL=C sort)
CI_IMAGES=$(printf '%s' "$CI_IMAGES" | grep . | awk '!seen[$0]++')

# ── Docker files already in the repository ────────────────────────────────────

DOCKERFILES=$(find_named Dockerfile 'Dockerfile.*' '*.Dockerfile' '*.dockerfile')
COMPOSE_FILES=$(find_named 'docker-compose*.yml' 'docker-compose*.yaml' 'compose.yml' 'compose.yaml' \
  'compose.*.yml' 'compose.*.yaml')

# ── The services an example environment points at ─────────────────────────────

ENV_EXAMPLES=$(find_named .env.example .env.dist .env.sample)

env_services() {
  awk -v f="$1" '
    function emit(svc, key) { if (!seen[svc]++) print svc "\t" f ":" key }
    /^[ \t]*#/ || !/=/ { next }
    {
      line = $0; sub(/^[ \t]*export[ \t]+/, "", line)
      key = line; sub(/=.*/, "", key); gsub(/[ \t]/, "", key)
      val = line; sub(/^[^=]*=/, "", val); gsub(/^["\047 \t]+|["\047 \t\r]+$/, "", val)
      lval = tolower(val)
      if (key == "DB_CONNECTION") {
        if (lval == "pgsql" || lval == "postgres" || lval == "postgresql") emit("postgres", key)
        else if (lval == "mysql") emit("mysql", key)
        else if (lval == "mariadb") emit("mariadb", key)
        else if (lval == "sqlsrv") emit("sqlserver", key)
      } else if (key ~ /DATABASE_URL$/ || key ~ /^DB_URL$/) {
        if (lval ~ /^postgres(ql)?:/) emit("postgres", key)
        else if (lval ~ /^mysql:/) emit("mysql", key)
        else if (lval ~ /^mariadb:/) emit("mariadb", key)
        else if (lval ~ /^mongodb(\+srv)?:/) emit("mongo", key)
      } else if (key ~ /^REDIS_(HOST|URL)$/) emit("redis", key)
      else if (key ~ /^MONGO(DB)?_(URI|URL|HOST)$/) emit("mongo", key)
      else if (key ~ /^(RABBITMQ_HOST|AMQP_URL|RABBITMQ_URL)$/) emit("rabbitmq", key)
      else if (key ~ /^(ELASTICSEARCH|ELASTIC)_(HOST|HOSTS|URL)$/) emit("elasticsearch", key)
      else if (key ~ /^OPENSEARCH_(HOST|HOSTS|URL)$/) emit("opensearch", key)
      else if (key ~ /^MEILISEARCH_(HOST|URL)$/) emit("meilisearch", key)
      else if (key ~ /^KAFKA_(BROKERS|BOOTSTRAP_SERVERS)$/) emit("kafka", key)
      else if (key == "MAIL_HOST" && (lval ~ /mailpit/ || lval ~ /mailhog/)) emit(lval ~ /mailpit/ ? "mailpit" : "mailhog", key)
    }
  ' "$1"
}

ENV_SERVICES=""
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  ENV_SERVICES="${ENV_SERVICES}$(env_services "$FILE")
"
done <<<"$ENV_EXAMPLES"

# ── Dependencies that need credentials ────────────────────────────────────────

PRIVATE_DEPS=""
add_private() { PRIVATE_DEPS="${PRIVATE_DEPS}$1	$(printf '%s' "$2" | mask_url)
"; }

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS= read -r WHAT; do
    [ -n "$WHAT" ] && add_private "$FILE" "$WHAT"
  done < <(jq -r '
      (.repositories // [] | if type == "object" then [.[]] else . end)[]?
      | select(type == "object" and ((.type // "") | test("^(vcs|git|github|gitlab|bitbucket|composer)$")))
      | select((.url // "") | test("packagist\\.org") | not)
      | "repository \(.type) \(.url // "")"' "$FILE" 2>/dev/null)
done <<<"$COMPOSER_FILES"

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS= read -r WHAT; do
    [ -n "$WHAT" ] && add_private "$FILE" "$WHAT"
  done < <(jq -r '
      ((.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {}))
      | to_entries[]
      | select((.value | type) == "string"
               and (.value | test("^(git\\+|git@|git://|github:|gitlab:|bitbucket:)|\\.git(#|$)")))
      | "\(.key) \(.value)"' "$FILE" 2>/dev/null)
done < <(find_named package.json)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS= read -r WHAT; do
    [ -n "$WHAT" ] && add_private "$FILE" "$WHAT"
  done < <(awk '
    function public(v) { return v ~ /registry\.npmjs\.org/ || v ~ /registry\.yarnpkg\.com/ }
    /^[ \t]*[#;]/ { next }
    /_authToken|_auth[ \t]*=|_password|npmAuthToken|npmAuthIdent/ { if (!tok++) print "registry authentication"; next }
    /registry[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*/, "", v); if (!public(v)) print "registry " v; next }
    /npmRegistryServer:/ {
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/["\047]/, "", v)
      if (!public(v)) print "registry " v
    }
  ' "$FILE")
done < <(find_named .npmrc .yarnrc.yml)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS= read -r WHAT; do
    [ -n "$WHAT" ] && add_private "$FILE" "$WHAT"
  done < <(awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    /^[ \t]*git:[ \t]*[^ \t]/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); print "git " trim(v); next }
    /^[ \t]*git:[ \t]*$/ { git = 1; next }
    git && /^[ \t]*url:/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); print "git " trim(v); git = 0; next }
    git && /^[ \t]*[a-z_]+:/ && !/^[ \t]*(ref|path):/ { git = 0 }
  ' "$FILE")
done < <(find_named pubspec.yaml)

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  while IFS= read -r WHAT; do
    [ -n "$WHAT" ] && add_private "$FILE" "$WHAT"
  done < <(grep -oE 'git\+[a-z]+://[^[:space:]"#]+' "$FILE" 2>/dev/null | sort -u)
done < <(find_named 'requirements*.txt' pyproject.toml)

# ── Tests that start containers ───────────────────────────────────────────────

# Testcontainers starts its containers through the Docker socket, which the
# runner refuses: a repository that declares it is excluded from GCP. Each
# manifest is read for its own spelling of the library.
TESTCONTAINERS=""
while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  case "$(basename "$FILE")" in
    package.json)
      DEPS=$(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]
                    | select(. == "testcontainers" or startswith("@testcontainers/"))' "$FILE" 2>/dev/null) ;;
    composer.json)
      DEPS=$(jq -r '((.require // {}) + (."require-dev" // {})) | keys[]
                    | select(startswith("testcontainers/"))' "$FILE" 2>/dev/null) ;;
    pom.xml|build.gradle|build.gradle.kts)
      DEPS=$(grep -oE 'org\.testcontainers' "$FILE" 2>/dev/null) ;;
    go.mod)
      DEPS=$(grep -oE 'github\.com/testcontainers/testcontainers-go[^[:space:]]*' "$FILE" 2>/dev/null) ;;
    Cargo.toml)
      DEPS=$(grep -oE '^[[:space:]]*testcontainers(-modules)?[[:space:]]*=|^\[(dev-)?dependencies\.testcontainers(-modules)?\]' \
               "$FILE" 2>/dev/null | grep -oE 'testcontainers(-modules)?') ;;
    *.csproj|Directory.Packages.props|packages.config)
      DEPS=$(grep -oE '(Include|Update|id)="Testcontainers[A-Za-z0-9.]*"' "$FILE" 2>/dev/null \
               | sed -E 's/^[A-Za-z]+="//; s/"$//') ;;
    *)
      DEPS=$(grep -oiE '(^|[^a-z0-9_./-])testcontainers([^a-z0-9_/-]|$)' "$FILE" 2>/dev/null \
               | grep -oi 'testcontainers' | tr '[:upper:]' '[:lower:]') ;;
  esac
  while IFS= read -r DEP; do
    [ -n "$DEP" ] && TESTCONTAINERS="${TESTCONTAINERS}${FILE}	${DEP}
"
  done < <(printf '%s\n' "$DEPS" | awk 'NF && !seen[$0]++')
done < <(find_named package.json composer.json pom.xml build.gradle build.gradle.kts go.mod \
           pyproject.toml 'requirements*.txt' setup.cfg Pipfile Cargo.toml '*.csproj' \
           Directory.Packages.props packages.config)

# owner/repo from origin, credentials dropped — as auto-dev-select.sh computes
# it, so the two compare equal. It names the repository in the GCP exclusion.
remote_slug() {
  printf '%s' "$1" \
    | sed -E 's#^[a-zA-Z+]+://##; s#^[^@/]+@##; s#^[^/:]*\.[^/:]*[:/]##; s#^[^/:.]+:##; s#\.git$##; s#/+$##' \
    | tr '[:upper:]' '[:lower:]'
}
REPOSITORY="$(remote_slug "$(git remote get-url origin 2>/dev/null || true)")"

# ── Output ────────────────────────────────────────────────────────────────────

lines() { printf '%s' "$1" | grep . || true; }

json_set CONFIG "$CONFIG"
json_set NESTED_CONFIGS "$NESTED_CONFIGS"
json_set VERSIONS "$(lines "$VERSIONS")"
json_set PHP_EXTENSIONS "$PHP_EXTENSIONS"
json_set PHP_COVERAGE "$PHP_COVERAGE"
json_set TEST_ENV "$(lines "$TEST_ENV")"
json_set CI_IMAGES "$CI_IMAGES"
json_set DOCKERFILES "$DOCKERFILES"
json_set COMPOSE_FILES "$COMPOSE_FILES"
json_set ENV_EXAMPLES "$ENV_EXAMPLES"
json_set ENV_SERVICES "$(lines "$ENV_SERVICES")"
json_set PRIVATE_DEPS "$(lines "$PRIVATE_DEPS")"
json_set TESTCONTAINERS "$(lines "$TESTCONTAINERS")"
json_set REPOSITORY "$REPOSITORY"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
