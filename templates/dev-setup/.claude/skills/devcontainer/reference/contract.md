# The runner's contract

What the job runner does with the repository's devcontainer, and what the
configuration owes it in return. `devcontainer-check.sh` verifies every
clause it can observe; the last section says which ones it cannot.

## Index

- [What the runner does](#what-the-runner-does)
- [What the configuration owes](#what-the-configuration-owes)
- [Testcontainers](#testcontainers)
- [What the check cannot see](#what-the-check-cannot-see)

## What the runner does

1. Clones the repository under `/var/autodev/` on an e2-standard-4 VM (4 vCPU,
   15 GB) whose `maxRunDuration` of three hours includes the image build, and
   runs `devcontainer up` **at its root, with no `--config`**: it reads
   `.devcontainer/devcontainer.json`, else `.devcontainer.json`, nothing else.
2. Adds `--mount type=bind,source=/var/autodev,target=/var/autodev` and
   `--remote-env GIT_CONFIG_GLOBAL=/var/autodev/gitconfig`. The repository is
   therefore mounted twice: at `/workspaces/<repo>`, the CLI's default, and at
   its host path under `/var/autodev/`, where the agent works.
3. Holds the git credentials (GitHub `x-access-token`, GitLab `oauth2`) for the
   duration of `up` only, with `GIT_TERMINAL_PROMPT=0`. Its git configuration
   rewrites `git@github.com:` and `ssh://git@github.com/` (and GitLab's) to
   HTTPS, so a private dependency declared with an SSH URL installs as it is.
4. Blocks the cloud metadata server with iptables — the `OUTPUT` chain for
   UID 1000, `DOCKER-USER` for the containers — so that nothing the agent runs
   reaches the service-account token, which reads the git secrets.
5. Runs `/dev-setup:auto-dev` inside as `autodev`, UID 1000, with `claude` and
   `jq` from `/var/autodev/bin` on the PATH, an `agent.env` holding only the
   Anthropic and ClickUp keys, and Claude Code's sandbox off (bubblewrap
   cannot create namespaces in the container).
6. Builds the image again on every run: about five minutes on the Invictus
   app, plus one and a half for its code generation.

If `up` fails — a lifecycle command included — the job dies before
`result.json`, and the task can stay `IN PROGRESS` on the board.

## What the configuration owes

| Clause | Why |
|---|---|
| One configuration, at the root. A monorepo gets one `.devcontainer/` with every toolchain its commands need, never one per package | The runner passes no `--config`: `.devcontainer/<name>/` is never read |
| `remoteUser` is the image's non-root user with UID 1000 (`vscode`, `node`), it owns every SDK installed in the image (Flutter in `/opt/flutter` belongs to `vscode`), and `updateRemoteUserUID` is not `false` | When the image's UID differs from the host's, the CLI changes it, and an SDK owned by the previous UID stops being writable — its caches (pub, Composer) fail |
| `bash`, `git` and `curl` in the image | auto-dev's scripts are bash, the run commits, the board is reached over the ClickUp REST API |
| No `workspaceMount`, no `workspaceFolder` of its own (compose, which has to name one, uses `/workspaces/<repo>`), and no script that assumes an absolute path of the repository | The agent works at the host path under `/var/autodev/`, not at the workspace folder |
| No bind mount of a host path — `~/.ssh`, `~/.gitconfig`, `~/.aws`, `${localEnv:HOME}/…`, `/var/autodev` | None of them exists on the VM, and a missing source fails `up`; the runner adds `/var/autodev` itself. SSH is not needed (3); VS Code forwards the SSH agent with no mount |
| No Docker socket, `privileged`, host network, docker-in-docker or docker-outside-of-docker | Each one lets the agent start a root container on the host network and read the token (4). Services go in docker compose, on a bridge network |
| `onCreateCommand`/`postCreateCommand` leave the quality commands runnable at once, with no interaction: dependencies installed (private ones too), uncommitted code generated, the test environment prepared from `.env.example` or `.env.testing` without overwriting an existing one | The credentials exist only during `up`; after it nothing can fetch, and nothing answers a prompt. A failing step fails `up`, and the whole job with it |
| No secret in `containerEnv`, `remoteEnv` or `build.args`, and no `${localEnv:…}` of a token | The agent sees the container's whole environment. Test variables carry fake values, taken from `.env.example` or `.env.testing` |
| Versions pinned by the files the CI reads | The image follows the pin and never drifts from the CI (the Invictus app clones Flutter at the tag in `.tool-versions`) |
| Only what the quality commands use, sized for the VM | No device SDK, emulator or browser; services capped (`innodb_buffer_pool_size`), so services and suite fit in 15 GB and the run in three hours |

A prebuilt image on Artifact Registry would remove the build from every run.
It is out of scope for now: the configuration builds from the repository.

## Testcontainers

`TESTCONTAINERS` not empty → some tests start their own containers through the
Docker socket, which the runner refuses. GCP does not support it: **no
devcontainer is written for the runner**, and the project is excluded from
GCP. Say it before anything else, with the evidence and the instruction,
verbatim:

```
Testcontainers: <file — dependency, one per line, from TESTCONTAINERS>
These tests start containers through the Docker socket, which the GCP runner
refuses: this project has to be excluded from GCP.
To exclude it: in n8n, data table `autodev_projects`, the project's row,
column `gcp_excluded` = `testcontainers: <REPOSITORY>`
```

`REPOSITORY` empty → write `<owner/repo>` and say origin did not name it.

A devcontainer for VS Code alone is the developer's call, never assumed: one
`AskUserQuestion`, header `Devcontainer` — **Stop here** (the default; nothing
written) or **A devcontainer for VS Code** (the same contract: no socket,
`privileged` or docker-in-docker, even then — the Testcontainers tests fail in
it too). End the turn. On a yes, propose as usual, and the summary says
**for VS Code only — the project is excluded from GCP**.

## What the check cannot see

- **Private dependencies.** On a developer's machine `devcontainer up` has
  neither the runner's credentials nor its URL rewriting, so a lifecycle
  command that fetches a private package can fail here and pass there. When
  `PRIVATE_DEPS` is set and `up` fails on a fetch, say so under **Open**
  instead of changing the command.
- **The host's UID.** On macOS the CLI does not map UIDs, so the check expects
  1000 itself; on a Linux machine it expects the host's, as on the runner.
- **SDK ownership after a UID change.** Visible only where the UIDs differ: a
  command that fails on a permission error inside an SDK directory is this
  clause, not the project.
- **Time and memory.** `UP_SECONDS` is this machine's, with its cache; the
  runner builds from nothing on 4 vCPU and 15 GB.
