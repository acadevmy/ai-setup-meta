---
name: beowulf
description: Distills a branch into a document for someone who did not follow the work — what the system does now, the high-risk points with permalinks, the decisions taken and where they come from, what to try by hand. Written locally, never committed; a short version goes in the merge request description. Use when a branch is done or nearly done, before opening or updating a merge request, or when asked to summarise, explain or distill the work on a branch.
effort: medium
argument-hint: "[branch] [--description]"
user-invocable: true
disable-model-invocation: false
---

# Beowulf

Turn a diff into something a person can read: what changed, what matters, where
to look first. It is not a reviewer — `verify` and `review` look for gaps. It
explains what is there.

It writes only an untracked local file, so the chain can reach it after
`review` without a prompt. Its section in the merge request description is
opt-in and behind the `ask` rule on `gh api` / `glab api` writes. No score,
no merge verdict: the reviewer decides.

## Before you start

- **`reference/document.md`** — the document's sections, how risk is assigned,
  and how code is cited.
- **`reference/mr-description.md`** — only for the merge request: the section
  appended to its description.

## Procedure

### 1. Gather

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

`BRANCH`, `BASE_BRANCH`, `MERGE_BASE`, `CHANGED_FILES`, `SPEC`. When a merge
request is open, its target branch wins over `BASE_BRANCH`.

Read from the general to the particular, never the whole diff at once:
`git diff --stat -M <MERGE_BASE>`, `git log --format='%h %s' <MERGE_BASE>..HEAD`,
then the full diff only of the files that matter — business logic, API
contracts, data schema and migrations, auth, configuration and infrastructure,
async flows. Lockfiles, formatting, generated code and pure renames are noise.

**Decisions.** The diff says what changed, never why. Sources, each cited:
the spec's `## Decision log` and `## Technical decisions`, this conversation if
the work was done in it, commit messages, the merge request. With no source
the section says so: a reason is never reconstructed after the fact.

### 2. Write

Follow `reference/document.md`, in the `LANGUAGE` that
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/mr-meta.sh" --json` returns.

Path: `<git-common-dir>/dev-setup/distill/<branch, / → ->.md`, with
`git rev-parse --path-format=absolute --git-common-dir`. It is shared by every
worktree and invisible to `git add`. Rewrite it whole on every run: it
describes the branch as it is now.

### 3. Description — only with `--description` or the yes of step 4

Follow `reference/mr-description.md`.

### 4. Hand off

Give the developer the path and the **In short** block, not the whole document.
Then, invoked on its own or from the chain, one question: with no merge request
open, open it through `vcs-ops` with the distill section in its body; with one
open, update that section. Nothing is published without that yes.

## Expected output

- the distill document in `<git-common-dir>/dev-setup/distill/`;
- decisions cited with their source, or the section stating there is none;
- on a yes, the distill section of the merge request description.
