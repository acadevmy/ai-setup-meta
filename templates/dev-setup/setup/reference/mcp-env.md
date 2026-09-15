# Steps 6, 7, 7b and 7c — MCP servers, environment, branches

What the project needs from the outside world: the MCP servers worth their
context cost, the environment keys declared in `.env.example`, the two
governance settings that belong on the host rather than in a document, and the
one setting that decides where a parallel session starts from.

## Index

- [Step 6 — Configure MCP servers](#step-6--configure-mcp-servers)
- [Step 7 — Declare the environment variables](#step-7--declare-the-environment-variables)
- [Step 7b — Branch protection on the reference branch](#step-7b--branch-protection-on-the-reference-branch)
- [Step 7c — The worktree base ref](#step-7c--the-worktree-base-ref)

---

## Step 6 — Configure MCP servers

The plugin declares **no** MCP servers of its own: every server costs context in
every session, so only what the project actually uses gets registered. This step
decides from the Step 2 detection.

Check whether the `claude` CLI is available with `command -v claude`. If it is
not, print the commands to run manually and move on.

> **Transport**: `-t` accepts `stdio`, `sse`, `http`. `url` is not a valid
> transport: a server declared with `"type": "url"` is silently discarded.

### 6.1 — ClickUp (user scope, only with the task list configured)

ClickUp is only useful if the team tracks tasks there. Resolve
`CLICKUP_SETUP_LIST_ID` as `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`
describes — environment variable, then the plugin's `userConfig`, and **never**
the project's `.env`, which 3.2 denied to you and to your shell commands.

- **Set** → check with `claude mcp list` whether `clickup` is already configured.
  If it is not:

  ```bash
  claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
  ```

- **Empty or absent** → do **not** register the server. Report in the summary:
  "ClickUp MCP not configured: set `CLICKUP_SETUP_LIST_ID` in `.env` (Step 7
  left the key in `.env.example`), then run
  `claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`".

### 6.2 — Library documentation: the `ctx7` CLI, not MCP

Do **not** register Context7 as an MCP server. `AGENTS.md` declares the `ctx7`
CLI as the preferred source — faster and with no tool-call budget — so the
server would duplicate the same capability while paying for its tool definitions
in every session.

Check with `command -v ctx7`:

- **present** → nothing to do
- **absent** → nothing to install: `AGENTS.md` instructs to invoke it via
  `npx ctx7@latest <command>`

Only if neither the CLI nor `npx` is reachable (an environment without npm
network access), report the manual fallback in the summary:

```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

### 6.3 — Figma (project scope, only if frontend or mobile is detected)

Only if `HAS_FRONTEND` or `HAS_MOBILE` is `true`, or if the stack chosen at Step
2b is web-frontend / mobile / fullstack. On a pure backend, Figma is **not**
registered.

Read `claude mcp list` first. A plugin can carry the server itself, and those
rows are named `plugin:<plugin>:<server>` — a project-scope `figma` added on top
of one of them is a duplicate, not a configuration.

- **a `figma` row is already there** (project, user or `plugin:` scope) →
  register nothing.
- **no `figma` row** → ask "Do you want to configure the Figma MCP?
  Authentication happens via OAuth in the browser." On a yes:

  ```bash
  claude mcp add figma -t http -s project https://mcp.figma.com/mcp
  ```

  On first use, Figma asks for authorization via the browser (like ClickUp).

Close with **exactly one** line for the summary — one of:

```
  - Figma MCP registered (project scope) — authorize it in the browser on first use
  - Figma MCP declined: the design tools stay unavailable in this project
  - Figma MCP already available from <the row `claude mcp list` printed> — nothing to register
  - Figma MCP skipped: no frontend and no mobile in this stack
```

The line is not decoration. This step is the flow's only optional registration,
and it is the one that went missing when 6.3 moved out of the skill body and in
here: with no reported outcome, a skipped ask and a declined ask and a step that
never ran all look identical from the summary.

---

## Step 7 — Declare the environment variables

**You never read or write `.env`.** Step 3.2 denied it at two levels — the file
tools refuse it and the sandbox refuses it to your shell commands — so the real
file stays the developer's. Work on `.env.example`, which is tracked, carries no
values, and is explicitly excluded from those deny rules.

1. `.env.example` exists and already contains `CLICKUP_SETUP_LIST_ID` → do
   nothing.
2. `.env.example` exists without the key → append:

   ```

   # ClickUp — task list ID (added by setup)
   CLICKUP_SETUP_LIST_ID=
   ```

3. `.env.example` does not exist → create it with:

   ```
   # ClickUp — task list ID
   CLICKUP_SETUP_LIST_ID=
   ```

In every case, close with one line for the summary:
`CLICKUP_SETUP_LIST_ID declared in .env.example — copy it into .env and fill it in (setup cannot write .env)`

---

## Step 7b — Branch protection on the reference branch

"One review required" and "no direct push to the reference branch" used to be
two bullets in a governance document nobody could enforce. They are settings on
the host, so this step sets them there and they stop being prose.

**Skip this step** when `{VCS}` is `none` or `other`.

### 7b.1 — Resolve the reference branch

Never assume `main`. The plugin already knows how to work this out:

```bash
BASE=$(${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh --json | jq -r .BASE_BRANCH)
REMOTE=$(git remote | head -1)
BASE_BRANCH=${BASE#"$REMOTE/"}   # BASE_BRANCH comes back remote-qualified (origin/next);
                                 # the host APIs want the bare name
```

It resolves the branch from the repository itself — the upstream, the remote's
default, then `main`/`master`/`develop`/`next` — and picks the one HEAD actually
forked from. On a project whose work targets `next`, protecting `main` would
protect the wrong ref.

### 7b.2 — Show the developer what will change, then ask

This writes to the remote, and on most hosts it needs admin rights on the
repository. State the branch and the two settings, and ask for a yes before
running anything:

> "Protect `$BASE_BRANCH` on <GitHub|GitLab>? It would require 1 approving
> review on every pull request, block direct pushes, and refuse a merge while CI
> is red. You need admin rights on the repo. (yes / skip)"

If they skip, note it in the summary and move on — the rest of the setup does
not depend on it.

### 7b.3 — Apply it

**GitHub** — first find out which checks this repository actually runs. Their
names differ per project, and a name that was guessed makes every PR permanently
unmergeable:

```bash
CHECKS=$(gh api "repos/{owner}/{repo}/commits/$BASE_BRANCH/check-runs" \
  --jq '[.check_runs[].name] | unique' 2>/dev/null || echo '[]')
```

If the array is non-empty, show the developer the names and ask which ones gate
a merge (default: all of them). Then apply the protection with those checks
required:

```bash
gh api -X PUT "repos/{owner}/{repo}/branches/$BASE_BRANCH/protection" --input - <<JSON
{
  "required_pull_request_reviews": { "required_approving_review_count": 1 },
  "required_status_checks": { "strict": true, "contexts": $CHECKS },
  "enforce_admins": false,
  "restrictions": null
}
JSON
```

If the array is empty — no workflow has ever run on that branch — send
`"required_status_checks": null` instead and tell the developer to re-run this
step once CI has completed once. Do **not** invent context names.

**GitLab** — protected branches are their own endpoint, and approvals are a
separate setting:

```bash
glab api -X POST "projects/:id/protected_branches" \
  -f "name=$BASE_BRANCH" -f "push_access_level=0" -f "merge_access_level=30"
glab api -X POST "projects/:id/approval_rules" \
  -f "name=Default" -f "approvals_required=1"
```

`push_access_level=0` is "no one", `merge_access_level=30` is "developers and
above" — direct pushes are blocked, merge requests still work.

GitLab's equivalent of "cannot merge with a red pipeline" is a project setting,
not part of the protected-branch payload:

```bash
glab api -X PUT "projects/:id" \
  -f "only_allow_merge_if_pipeline_succeeds=true" \
  -f "only_allow_merge_if_all_discussions_are_resolved=true"
```

### 7b.4 — When it fails

A 403 means no admin rights, a 404 on GitLab means the plan does not include
approval rules. Neither is a setup failure: report exactly what came back, say
which setting is still missing, and continue. Do not retry with different
parameters, and do not fall back to protecting a different branch.

---

## Step 7c — The worktree base ref

Runs in every mode, on every git project. It is one key in
`.claude/settings.json`, and it decides which commit a new worktree forks from —
for `--worktree` sessions and for every subagent that runs with
`isolation: worktree`.

**`worktree.baseRef` cannot name a branch.** It takes exactly two values:

| Value | Forks from |
|---|---|
| `"fresh"` (the harness default) | the remote's default branch, usually `main` |
| `"head"` | the local `HEAD`, unpushed commits included |

So the value follows one question: **is the reference branch the remote
default?** Reuse the `$BASE_BRANCH` resolved at 7b.1 and compare:

```bash
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
DEFAULT=${DEFAULT#origin/}
```

- **the same** (work targets `main`, and `origin/HEAD` is `main`) → `"fresh"`.
  Every worktree starts from a clean tree matching the remote.
- **different** (work targets `next` or `develop`, `origin/HEAD` is still
  `main`) → `"head"`. With `"fresh"`, a worktree would fork from `main` and the
  branch would carry the whole `main..next` delta — the exact defect
  `check-prerequisites.sh` exists to avoid, reintroduced one layer down.

Write it only when the key is absent — an existing `worktree` block is the
team's choice, and this step does not overwrite it:

```bash
jq -e 'has("worktree")' .claude/settings.json >/dev/null 2>&1 \
  || { jq '.worktree.baseRef = "head"' .claude/settings.json > .claude/settings.json.tmp \
       && mv .claude/settings.json.tmp .claude/settings.json; }
```

Unlike 3.3 and 3.4, this runs even when `.claude/settings.json` is the team's
own file: adding a key the file does not have takes nothing away, and it is the
only way an already-configured project ever gets the setting.

Whichever value lands, the SDD flow still passes the fork point explicitly
(`sdd-start.sh --base <ref>`), because a setting cannot know which task branch a
worktree is for. `${CLAUDE_PLUGIN_ROOT}/reference/worktree.md` is the rest of the
convention: the port offset, the overlap warning, the dependency install.

**Report in the summary** (a single line):
`worktree.baseRef: <fresh|head> (reference branch <name>, remote default <name>) — or "left as the team set it"`
