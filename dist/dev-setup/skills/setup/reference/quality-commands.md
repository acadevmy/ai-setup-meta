# Step 3b — The quality commands, declared and verified

Which command lints this project, which type-checks it and which runs its tests
is a fact about the project, so the project declares it — once, here — in
`.claude/quality-commands.json`. Every flow reads the commands from that file
through `detect-stack.sh`: the commit gate, `sdd-dev`, the `auto-sdd` workflow
and both autonomous launchers, which refuse to start without it.

The per-language heuristics are only a suggestion now. On DE-17472 they knew
no rule for a Laravel project in `api/`, returned three empty commands, and an
autonomous run spent its whole budget without running a test — while the
project had `make lint`, `make test` and a CI job running both. This step reads
where a project already writes its gates down, asks the developer to confirm
them, and runs each one before the setup ends.

Runs in every mode. EXISTING and UPDATE run it after 3.9 and before Step 4,
which reads the commands; GREENFIELD runs it after Step 8, once the scaffold
has written its scripts.

## Index

- [3b.1 — The file](#3b1--the-file)
- [3b.2 — What is already there](#3b2--what-is-already-there)
- [3b.3 — The candidates, and the one question](#3b3--the-candidates-and-the-one-question)
- [3b.4 — Write it](#3b4--write-it)
- [3b.5 — Run every declared command once](#3b5--run-every-declared-command-once)
- [3b.6 — Hand the commands to Steps 4 and 5](#3b6--hand-the-commands-to-steps-4-and-5)
- [3b.7 — The summary line](#3b7--the-summary-line)

## 3b.1 — The file

Tracked, owned by the team, on the model of `.claude/merge-request.json`. It
holds commands, never a credential:

```json
{
  "lint": "make lint",
  "typecheck": null,
  "test": "make test",
  "absent": { "typecheck": "declared absent at setup" },
  "preflight": null,
  "hook_manager": null
}
```

| Key | Holds |
|---|---|
| `lint`, `typecheck`, `test` | required: a command, or `null` when the project has none — with the reason under `absent` |
| `absent` | `<key>: <why>` for every `null` command: a null without a reason is rejected, so a command cannot be blank by accident |
| `preflight` | optional: a readiness check the autonomous launchers run first (`bin/check-toolchain.sh`) |
| `hook_manager` | optional: the project's hook tool when detection does not know it (`pre-commit`, `captainhook`, `grumphp`) — the commit gate then defers to it |

**Every command runs from the repository root**, as the commit gate, `sdd-dev`
and the workflow all run it. A command that belongs to a sub-directory carries
it: `make -C api lint`, `cd api && composer test`. There is no directory key.

## 3b.2 — What is already there

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" --json
```

- **The file exists and the call succeeds** (`COMMANDS_SOURCE: declared`) →
  keep it as the team left it — no question — and go to 3b.5 to verify it.
- **The call fails** — the file is malformed, and stderr says why. Show the
  cause and ask "`.claude/quality-commands.json` is invalid (<cause>). Rewrite
  it from the candidates?" — **default: rewrite**. Yes → 3b.3. No → nothing is
  written, and the summary carries the INVALID line of 3b.7.
- **There is no file** — a first setup, or an UPDATE of a project set up before
  the declaration existed → 3b.3: the same candidates and the same question
  propose one.

## 3b.3 — The candidates, and the one question

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/quality-candidates.sh" --json
```

`LINT_CANDIDATES`, `TYPECHECK_CANDIDATES` and `TEST_CANDIDATES` hold one
`<command>\t<source>` line each, in order of authority: the CI first (what
gates the merge), then the task runners, the package scripts, the docs, and
the heuristics last. In a workspace (`MONOREPO` non-empty) with no candidate
of a kind at the root, `--dir <sub-project>` adds that sub-project's, already
written as `cd <sub-project> && …`.

Then **one** `AskUserQuestion` call, four questions, and the turn ends on it
(`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`):

| Question | Options | Free text takes |
|---|---|---|
| "Which command lints this project?" | the first three lint candidates — label the command, description the source — then **None — this project has no linter** | a command |
| "Which command type-checks it?" | the same, from the typecheck candidates, then **None — this project has no type checker** | a command |
| "Which command runs its tests?" | the same, from the test candidates, then **None — this project has no tests** | a command |
| "Write `.claude/quality-commands.json`?" | **Write it** (the default), **Not now** | — |

A kind with no candidate is **still asked** — no command is left empty without
a decision: its options are **I will type it** (the free-text answer) and the
**None** one. A free-text command is taken as typed; say it runs from the
root.

**Not now** writes nothing: the summary carries the DECLINED line of 3b.7, and
3b.4 to 3b.6 are skipped.

## 3b.4 — Write it

An empty variable is a **None** answer, and becomes `null` with its reason:

```bash
mkdir -p .claude
jq -n --arg lint "$LINT" --arg typecheck "$TYPECHECK" --arg test "$TEST" '
  def cmd($c): if $c == "" then null else $c end;
  {
    lint: cmd($lint), typecheck: cmd($typecheck), test: cmd($test),
    absent: ([{k: "lint", c: $lint}, {k: "typecheck", c: $typecheck}, {k: "test", c: $test}]
             | map(select(.c == "") | {(.k): "declared absent at setup"}) | add // {}),
    preflight: null,
    hook_manager: null
  }' > .claude/quality-commands.json
```

`preflight` and `hook_manager` are nobody's question here: both are `null`,
and either is a one-line edit for the team, the way 7d.3 treats `base_branch`
and `dry_run`.

## 3b.5 — Run every declared command once

A declared command is an executed command — a command that does not start is
a problem of this setup, not of the first autonomous run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/quality-preflight.sh" --run --json
```

It runs each command from the root and reports `LINT_STATUS`,
`TYPECHECK_STATUS` and `TEST_STATUS`: `passed`, `failed`, `not-found` or
`absent`. A red command is reported, not fixed: the project is red today, and
that is the team's to know. `not-found`, a `MISSING` program or a refusal is
the setup's to say plainly: show `REASON` and `OUTPUT`, and name the command to
correct in the file. Either way the result goes in the summary line, never
silently.

## 3b.6 — Hand the commands to Steps 4 and 5

Step 4 picks `tests.md` on `TEST_CMD`, Step 5 writes the commands into
AGENTS.md: both must read the declared ones, so rewrite the scratch file Step 2
wrote:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh --json > .claude/.stack.json
```

GREENFIELD runs 3b after Steps 4 and 5, which already removed the scratch file:
there is nothing to hand over, and the rewrite is skipped.

## 3b.7 — The summary line

**Report in the summary** (a single line) — one of:

```
  - quality commands declared in .claude/quality-commands.json — lint: <cmd> (passed), typecheck: absent, test: <cmd> (failed)
  - quality commands kept as the team left them — lint: <cmd> (passed), typecheck: <cmd> (passed), test: <cmd> (passed)
  - quality commands declared, but <kind> did not start (<cmd>): fix it in .claude/quality-commands.json — auto-sdd and multi-sdd refuse to start until it does
  - quality commands declaration INVALID (<cause>), kept unchanged: auto-sdd and multi-sdd refuse to start until it is fixed
  - quality commands DECLINED: no .claude/quality-commands.json — auto-sdd and multi-sdd refuse to start until it exists; run the setup again to write it
```

The DECLINED line is not decoration: on a project set up before this step, it
is the only place that says why the next autonomous run will refuse.
