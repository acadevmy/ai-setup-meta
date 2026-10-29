# Building the proposal

How the facts become files. The check proves the result, so a recipe here is
a starting point the build confirms, not a guarantee: when the check says an
image lacks a program, the fix goes in the image.

## Index

- [The layout](#the-layout)
- [Reuse before writing](#reuse-before-writing)
- [Versions](#versions)
- [The base image](#the-base-image)
- [PHP: extensions and coverage](#php-extensions-and-coverage)
- [Flutter](#flutter)
- [Node package managers](#node-package-managers)
- [Dependencies and generated sources](#dependencies-and-generated-sources)
- [Services](#services)
- [Keeping it light](#keeping-it-light)

## The layout

| Case | Files |
|---|---|
| No service | `.devcontainer/devcontainer.json` + `.devcontainer/Dockerfile` (or an image and Features alone, when no step is needed) |
| A command reaches a database, a cache, a broker | the same, plus `.devcontainer/compose.yml`, with the toolchain as service `app` |

The model to follow is the Invictus app's: a Dockerfile from
`mcr.microsoft.com/devcontainers/base:bookworm`, `build.context` `..` so it
can `COPY` the file that pins a version (the image then follows the pin and
never drifts from the CI), and `postCreateCommand` running the project's own
generation. Comment each file with where its versions come from.

```jsonc
// image configuration: no workspaceMount, no workspaceFolder
{
  "name": "<repository>",
  "build": { "dockerfile": "Dockerfile", "context": ".." },
  "remoteUser": "vscode",
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

```jsonc
// compose configuration: compose has to name the folder, so it names the
// CLI's default — /workspaces/<repository>, the repository's directory name
{
  "name": "<repository>",
  "dockerComposeFile": "compose.yml",
  "service": "app",
  "workspaceFolder": "/workspaces/<repository>",
  "remoteUser": "vscode",
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

```yaml
# .devcontainer/compose.yml — paths relative to this file, bridge network
services:
  app:
    build: { context: .., dockerfile: .devcontainer/Dockerfile }
    command: sleep infinity
    volumes: ["..:/workspaces/<repository>:cached"]
```

Mount nothing else from the host, and write no script that names either path:
the agent works from the repository's host path under `/var/autodev/`.

## Reuse before writing

- `DOCKERFILES` holds a development Dockerfile (dev dependencies, the
  toolchain) → build from it instead of writing one. A production Dockerfile
  (multi-stage, no dev dependencies) is not a toolchain, but its versions are
  evidence.
- `COMPOSE_FILES` already runs the services → list it first in
  `dockerComposeFile` and add only `app` in `.devcontainer/compose.yml`; the
  services keep one definition.

## Versions

Each pin in `VERSIONS` comes with its file. Order of authority: what the CI
runs (`CI_IMAGES` jobs, a `setup-*` action's version), then `.tool-versions`,
then the tool's own file (`.nvmrc`, `.fvmrc`), then a manifest range
(`^8.2`, `>=20`). A range becomes the highest version it allows that has an
image, and the proposal says so. Two files that disagree are both shown; the
proposal follows the CI's.

## The base image

| Toolchain | Base |
|---|---|
| Node only | `mcr.microsoft.com/devcontainers/javascript-node:<major>-bookworm` (user `node`) |
| PHP | `mcr.microsoft.com/devcontainers/php:<major.minor>-bookworm` (Composer included) |
| Python, Go | `mcr.microsoft.com/devcontainers/python:<x.y>-bookworm`, `…/go:<x.y>-bookworm` |
| Flutter, or several | `mcr.microsoft.com/devcontainers/base:bookworm` (user `vscode`, with git and curl) |

Several toolchains: the base of the heaviest, then a Feature per other one —
`ghcr.io/devcontainers/features/node:1` with `"version"`, `…/python:1`,
`…/go:1`. PHP and Flutter go in the Dockerfile, never as a Feature: the PHP
Feature compiles PHP on every build. Never a Docker Feature
(`docker-in-docker`, `docker-outside-of-docker`): the runner refuses it.

Whatever the Dockerfile installs in a directory of its own belongs to the
remote user (`install -d -o vscode -g vscode /opt/<sdk>`, then `USER vscode`
for the download): an SDK left to root, or to another UID, stops being
writable when the CLI remaps the user, and its cache with it.

## PHP: extensions and coverage

The devcontainers PHP image is the official one underneath. Install what
`PHP_EXTENSIONS` names and the image lacks:

```dockerfile
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions intl pdo_mysql pcov
```

`PHP_COVERAGE=true` → add `pcov`, never Xdebug for coverage alone: it slows
every test. `TEST_ENV` says what the tests set for themselves — an in-memory
sqlite needs `pdo_sqlite` and no database service.

## Flutter

No Feature exists. From the base image, as the Invictus app does:

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/* \
 && install -d -o vscode -g vscode /opt/flutter \
 && ln -s /opt/flutter/bin/flutter /usr/local/bin/flutter \
 && ln -s /opt/flutter/bin/dart /usr/local/bin/dart
COPY .tool-versions /tmp/.tool-versions
USER vscode
RUN version="$(awk '/^flutter /{sub(/-.*/, "", $2); print $2}' /tmp/.tool-versions)" \
 && git clone --quiet --depth 1 --branch "$version" https://github.com/flutter/flutter.git /opt/flutter \
 && flutter config --no-analytics --no-cli-animations \
 && flutter precache --no-android --no-ios --no-web
```

Read the version from the file that pins it — `.fvmrc` when that is the pin.
No Android SDK: `analyze` and `test` do not start it.

## Node package managers

`packageManager` in `VERSIONS` (`pnpm`, `yarn`) → `corepack enable`, as root
in the Dockerfile; Node 25 and later ship without Corepack, so install it
first (`npm install -g corepack`).

## Dependencies and generated sources

After `up`, the quality commands must run at once, with nothing installed by
hand and nobody to answer a prompt. One script, `.devcontainer/post-create.sh`,
does it in order and stops at the first failure — a failure fails `up`, which
is better than a run on a half-ready tree:

```bash
#!/usr/bin/env bash
# Runs from the repository root: everything the quality commands need.
set -euo pipefail
cd "$(dirname "$0")/.."
composer install --no-interaction --prefer-dist          # from the lockfile
[ -f .env ] || { cp .env.example .env && php artisan key:generate; }
tool/generate.sh                                        # what git does not hold
```

- **Dependencies**, from the lockfile, non-interactive: `npm ci`,
  `pnpm install --frozen-lockfile`, `yarn install --immutable`,
  `composer install --no-interaction`, `flutter pub get`, `pip install -r`.
  In a monorepo, one line per package (`(cd api && composer install …)`).
  Private ones (`PRIVATE_DEPS`) install here as they are, SSH URLs included:
  this runs during `up`, while the runner's credentials exist.
- **Generated code** the commands need and git does not hold: the project's
  generation script, `build_runner`, an OpenAPI client.
- **The test environment**, from `.env.example` or `.env.testing`, only when
  the file is missing — a developer's own `.env` is never overwritten. Fake
  values only: no secret in `containerEnv`, `remoteEnv`, `build.args` or
  these files.

## Services

A service goes in only when a declared command reaches it — a feature test on
MySQL, a queue test on Redis. Its image is the CI's (`CI_IMAGES` with role
`service`), at the CI's version; failing that, the `ENV_SERVICES` entry at the
version production runs. Give each a healthcheck, and `app` a `depends_on`
with `condition: service_healthy`, so the tests never start before the
database. The variables the commands read go in `app`'s `environment:` — the
host is the service name (`DB_HOST: mysql`), the values the CI's test ones,
never a production secret. All on compose's default bridge network: no
`network_mode: host`, no `privileged`, no Docker socket.

```yaml
  mysql:
    image: mysql:8.0                       # the CI's service image
    command: --innodb-buffer-pool-size=256M
    environment: { MYSQL_DATABASE: testing, MYSQL_ROOT_PASSWORD: password }
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-ppassword"]
      interval: 5s
      retries: 20
```

## Keeping it light

The runner builds the image on every run, on 4 vCPU and 15 GB, inside a
three-hour budget that also holds the run. Install with
`--no-install-recommends`, clear `/var/lib/apt/lists`, precache only the
platforms the tests use (`--no-android --no-ios --no-web`), cap what a service
keeps in memory, and add no browser, emulator or SDK no quality command
starts. `customizations` cost nothing: the CLI ignores them.
