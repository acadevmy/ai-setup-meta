---
name: devcontainer
description: Writes and verifies the repository's root `.devcontainer/` for the job runner of headless auto-dev runs — every toolchain the declared quality commands need, their services in docker compose, the runner's contract (UID 1000, no mounts, no host credential). Optional and separate from setup. Use when a project's unattended runs move to GCP and a repository has no devcontainer, or an existing one has to be checked against the runner.
argument-hint: "[--check]"
user-invocable: true
disable-model-invocation: true
---

# Devcontainer

The runner clones the repository, runs `devcontainer up` at its root with no
`--config`, and starts `/dev-setup:auto-dev` inside. This command writes that
devcontainer and proves the quality commands run in it. Only GCP projects need
one, per repository.

**Usage**: `/dev-setup:devcontainer [--check]` — `--check` verifies what
exists and writes nothing.

Never read `.env`: every input is a tracked file.

## 1 — The facts

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" --json
bash "${CLAUDE_PLUGIN_ROOT}/scripts/devcontainer-facts.sh" --json
```

`COMMANDS_SOURCE` other than `declared` → stop, nothing written: the check
runs the declared commands, so `/dev-setup:setup` (step 3b) comes first.

`TESTCONTAINERS` set → GCP does not support it, and nothing is written for the
runner: follow "Testcontainers" in
[reference/contract.md](reference/contract.md) before anything else.

## 2 — An existing configuration

`CONFIG` or `NESTED_CONFIGS` set → the team's files, never overwritten
unasked. With `--check`, go to 5. Otherwise one `AskUserQuestion`, header
`Devcontainer`: **Verify it** (default) → 5; **Propose a rewrite** → 3, as a
diff; **Leave it** → stop. With only `NESTED_CONFIGS`, say the runner reads
none of them. End the turn
(`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`).

No configuration and `--check` → stop: nothing to verify.

## 3 — Propose

Read [reference/contract.md](reference/contract.md) and
[reference/recipes.md](reference/recipes.md), then build the files. Show each
in full (a diff, for a rewrite), every version with the file it came from, and
one `AskUserQuestion`: **Write it** (default), **Not now** — nothing written.
Free text is a change: apply it, ask again. End the turn.

## 4 — Write

Only under `.devcontainer/`, or the `.devcontainer.json` being rewritten.
Never `.env`, never a secret.

## 5 — Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/devcontainer-check.sh" --json
```

It needs Docker and the registries, which the sandbox refuses: run it
unsandboxed (the developer approves) and in the background — a build plus the
suite outlasts a Bash call.

- `ready` (exit 0) — built, contract held, every command started. A red
  command is the project's state: report it, never fix it.
- `not-ready` (exit 4) — `ISSUES`, `REASON`, `OUTPUT`. In files this run
  wrote, fix and verify again, at most twice; in the team's, report.
- `unverified` (exit 3) — no Docker, no CLI, or nothing declared. The files
  stay; say **not verified** and why.

## 6 — Summary

```
Devcontainer: <written: files | kept: CONFIG | declined>
  Check: <STATUS> — up <UP> in <UP_SECONDS>s as <REMOTE_USER> (UID <REMOTE_UID>)
  Commands: preflight <PREFLIGHT>, lint <LINT_STATUS>, typecheck <TYPECHECK_STATUS>, test <TEST_STATUS>
  Open: <ISSUES, why unverified, private dependencies the check could not fetch>
```

Next: commit `.devcontainer/` and merge it into the branch the runner forks
from — `/dev-setup:quick` does both.
