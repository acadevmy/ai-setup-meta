# Step 4 — Generate the path-scoped rules

The project's governance is not one document read in full at every session: it
is a set of files under `.claude/rules/`, each declaring in its frontmatter the
globs it applies to. The harness injects a rule when the model touches a file
that matches, which means the match is deterministic, costs nothing on the
sessions that never touch those files, and survives compaction.

Only `core.md` has no `paths:` — it is the one that loads unconditionally, and it
holds only what is unsafe to discover late (secrets, untrusted content, supply
chain, the gates). Everything else arrives with the file it applies to.

## Index

- [4.1 — Read the stack once](#41--read-the-stack-once)
- [4.2 — Pick the rules this project needs](#42--pick-the-rules-this-project-needs)
- [4.3 — Render them](#43--render-them)
- [4.4 — The `dev-setup-` prefix is the contract](#44--the-dev-setup--prefix-is-the-contract)
- [4.5 — Migrating a project that still has CONSTITUTION.md](#45--migrating-a-project-that-still-has-constitutionmd)

## 4.1 — Read the stack once

EXISTING and UPDATE runs already have the object: Step 2 wrote it to
`.claude/.stack.json`. If it is not there (a GREENFIELD run, or a re-entry),
create it:

```bash
mkdir -p .claude
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh --json > .claude/.stack.json
```

Everything in this step reads from that object; 4.3 deletes it. It is a scratch
file, not project state — do not commit it and do not add it to `.gitignore`.

## 4.2 — Pick the rules this project needs

| Template | Generated as | Generate when |
|---|---|---|
| `core.md` | `dev-setup-core.md` | always |
| `code-style.md` | `dev-setup-code-style.md` | always |
| `typescript.md` | `dev-setup-typescript.md` | `LANG` contains `node`, or a `tsconfig.json` exists |
| `nestjs.md` | `dev-setup-nestjs.md` | `FRAMEWORKS` contains `nestjs` |
| `react.md` | `dev-setup-react.md` | `FRAMEWORKS` contains `nextjs` or `react` |
| `react-native.md` | `dev-setup-react-native.md` | `FRAMEWORKS` contains `expo` or `react-native` |
| `vue.md` | `dev-setup-vue.md` | `FRAMEWORKS` contains `nuxt` or `vue` |
| `flutter.md` | `dev-setup-flutter.md` | `FRAMEWORKS` contains `flutter` |
| `dart-analysis.md` | `dev-setup-dart-analysis.md` | `FRAMEWORKS` contains `flutter` |
| `terraform.md` | `dev-setup-terraform.md` | `HAS_INFRA` is `true` |
| `tests.md` | `dev-setup-tests.md` | `TEST_CMD` is non-empty, or the mode is GREENFIELD |
| `backend-services.md` | `dev-setup-backend-services.md` | `SERVICES_GLOB` is non-empty |

`core.md` and `code-style.md` are both generated every time, but only `core.md`
loads unconditionally: `code-style.md` declares source-file globs, so a session
spent on documentation or configuration never pays for it.

**GREENFIELD**: the project is not scaffolded yet, so `detect-stack.sh` reports
almost nothing. Evaluate the table against the stack the developer picked at
Step 2b instead — `greenfield.md` maps each choice onto the same keys. A
greenfield Next.js project must come out with `dev-setup-react.md`, not without
it.

**Multi-project**: the table is evaluated against the union of the sub-projects —
a workspace holding a Next app and a NestJS API gets both `dev-setup-react.md`
and `dev-setup-backend-services.md`. The rules live in the workspace root's
`.claude/rules/`, and the globs (`**/*.tsx`, `**/*.service.ts`) already restrict
each one to the right sub-tree.

Do not generate a rule for a stack the project does not have. That is the whole
point of this step: a Flutter project must not carry the React rule, and a Next
project must not carry the Terraform one.

## 4.3 — Render them

```bash
mkdir -p .claude/rules

# One call per rule selected above.
${CLAUDE_PLUGIN_ROOT}/scripts/render-template.sh \
  --in "${CLAUDE_SKILL_DIR}/templates/rules/<template>.md" \
  --out ".claude/rules/dev-setup-<template>.md" \
  --vars-json .claude/.stack.json
```

`backend-services.md` is the only template with a placeholder:
`{{SERVICES_GLOB}}`, which `detect-stack.sh` resolved from the project's layout.
The others render unchanged — passing `--vars-json` anyway keeps the command
identical for every rule and makes an accidentally-added placeholder an error
instead of a `{{PLACEHOLDER}}` shipped into the project.

**Check**: `render-template.sh` exits non-zero on an unresolved placeholder. If
it does, stop and report — do not write the file by hand.

When every rule is written, remove the scratch file:

```bash
rm -f .claude/.stack.json
```

## 4.4 — The `dev-setup-` prefix is the contract

Everything this skill writes into `.claude/rules/` is named `dev-setup-*.md`.
Everything the project's own team writes there is not. That single convention is
what makes UPDATE mode safe:

- **GREENFIELD / EXISTING** — write the selected rules. If a `dev-setup-*.md`
  already exists, apply conflict detection: tell the developer and keep theirs.
- **UPDATE** — regenerate every `dev-setup-*.md` the table selects, overwriting
  without asking (they are generated artefacts, and this is what the developer
  asked for). Then delete the `dev-setup-*.md` files the table did **not**
  select: they belong to a stack this project no longer has. **Never** touch a
  file in `.claude/rules/` whose name does not start with `dev-setup-` — those
  are the project's own rules.

## 4.5 — Migrating a project that still has CONSTITUTION.md

Earlier versions of this setup copied a single `CONSTITUTION.md` into the
project root. If one is there:

1. Generate the rules as above.
2. Tell the developer the file is superseded, and show what replaced it: the
   governance now lives in `.claude/rules/`, and the mechanical parts of it
   (function length, naming, `any`, coverage floors, who may push to the
   reference branch) moved into ESLint, the test runner and branch protection.
3. Ask before deleting it — a team may have added its own rules to that file.
   If they say no, leave it and note that it is no longer read by anything.
