# Steps 6 to 7d — MCP servers, environment, branches, auto-dev

What the project needs from the outside world: the MCP servers worth their
context cost, the environment keys declared in `.env.example`, the two
governance settings that belong on the host rather than in a document, the one
setting that decides where a parallel session starts from, and the file an
unattended run reads instead of asking.

## Index

- [Step 6 — Configure MCP servers](#step-6--configure-mcp-servers)
- [Step 7 — Declare the environment variables](#step-7--declare-the-environment-variables)
- [Step 7b — Branch protection on the reference branch](#step-7b--branch-protection-on-the-reference-branch)
- [Step 7c — The worktree base ref](#step-7c--the-worktree-base-ref)
- [Step 7d — The auto-dev configuration](#step-7d--the-auto-dev-configuration)

---

## Step 6 — Configure MCP servers

The plugin declares **no** MCP servers of its own: every server costs context in
every session, so only what the project actually uses gets registered. This step
decides from the Step 2 detection.

Check whether the `claude` CLI is available with `command -v claude`. If it is
not, print the commands to run manually and move on.

> **Transport**: `-t` accepts `stdio`, `sse`, `http`. `url` is not a valid
> transport: a server declared with `"type": "url"` is silently discarded.

### 6.1 — The task tracker (user scope MCP, project file)

Which tracker the team uses is a project fact, and the flows read it from
`.claude/tracker.json` (`${CLAUDE_PLUGIN_ROOT}/reference/tracker-contract.md`,
"Resolving the provider and the task list"). Ask
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/tracker-config.sh" --json` first:

- **`SOURCE` is `file`** → the project already chose. Print the provider and
  its lists, and ask "Keep the task tracker configuration?" — **default: keep
  it**. A keep skips the questions and the file, and goes on to the permissions
  and the MCP check below: they only add, and a settings file rewritten at 3.2
  or migrated at 3.2b has lost them.
- **anything else** — no file yet, a project configured by an older version
  included — ask the questions below. An older project's
  `CLICKUP_SETUP_LIST_ID` is not read any more: its value is the default of the
  list question, when the session can see it, and nothing more.

Two calls, because the second one's options depend on the first answer. End
the turn on each:

1. "Which task tracker does the team use?" — `clickup` (the default), `linear`,
   `none`.
2. For `clickup` or `linear`, in **one** `AskUserQuestion` call:

| Field | Question | Options (the first is the default) |
|---|---|---|
| `lists` | "Which list do the tasks come from?" | ClickUp: a list id (`app.clickup.com/.../li/<ID>`); Linear: a team key (`ENG`). Several comma-separated |
| `status` | "What does the board call its statuses (backlog · ready · in progress · in review · done · blocked)?" | the chosen adapter's default map (`${CLAUDE_PLUGIN_ROOT}/reference/tracker-<provider>.md`, "Status map") |

The status names are the board's own, copied exactly as it shows them: a name
the board does not have makes every transition of the flow fail. On Linear,
`blocked` is not a default state — the answer may name another state the team
has, or leave `Blocked` for the team to add.

**`none`** writes `{"provider": "none"}` to `.claude/tracker.json` — so an
earlier choice stops applying — registers no server and ends the step with
`task tracker: none — the flows run from a description and write to no board`.

Otherwise write the file:

```bash
mkdir -p .claude
LISTS=$(printf '%s\n' "$LIST_ANSWER" | tr ',' '\n' | sed 's/[[:space:]]//g' \
        | grep -v '^$' | jq -R . | jq -s .)
jq -n --arg p "$PROVIDER" --argjson lists "$LISTS" \
  --arg backlog "$BACKLOG" --arg ready "$READY" --arg progress "$IN_PROGRESS" \
  --argjson review "$IN_REVIEW_JSON" --arg done "$DONE" --arg blocked "$BLOCKED" \
  '{provider: $p, lists: $lists,
    status: {backlog: $backlog, ready: $ready, in_progress: $progress,
             in_review: $review, done: $done, blocked: $blocked}}' > .claude/tracker.json
```

`IN_REVIEW_JSON` is a JSON array: `["CODE REVIEW", "IN REVIEW"]` for the ClickUp
default, one name otherwise. The file holds no credential and is tracked.

**Permissions and network.** Merge the provider's fragment from
`${CLAUDE_SKILL_DIR}/reference/tracker-permissions.json` into
`.claude/settings.json` — `allow` and `ask` into `permissions`, `network` into
`sandbox.network.allowedDomains` — de-duplicated, never replacing what is there:

```bash
jq --slurpfile f "${CLAUDE_SKILL_DIR}/reference/tracker-permissions.json" --arg p "$PROVIDER" '
  ($f[0][$p]) as $x
  | .permissions.allow = ((.permissions.allow // []) + $x.allow | unique)
  | .permissions.ask = ((.permissions.ask // []) + $x.ask | unique)
  | .sandbox.network.allowedDomains = ((.sandbox.network.allowedDomains // []) + $x.network | unique)
' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

Unlike 3.3 and 3.4 this runs even when `.claude/settings.json` is the team's own
file: it only adds, and the `ask` entries are the human checkpoints on the
board's writes.

**The MCP server.** Check with `claude mcp list` whether the adapter's server
(`clickup`, `linear`) is already configured — a `plugin:` or claude.ai row for
the same tracker counts. If it is not, register it with the command the
adapter's "Server" section gives:

```bash
claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
claude mcp add linear -t http -s user https://mcp.linear.app/mcp
```

Close with **exactly one** line for the summary — one of:

```
  - task tracker: <provider>, <n> list(s), statuses <ready>/<in progress>/<in review>/<blocked> — MCP <registered|already there>
  - task tracker kept: <provider>, <n> list(s)
  - task tracker: none — the flows run from a description and write to no board
```

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

  On first use, Figma asks for authorization via the browser (like the task
  tracker).

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

**You never write `.env`, and no setup step reads it.** Step 3.2 denies writes
at two levels — the file tools refuse them and the sandbox refuses them to your
shell commands — and the values are the developer's: nothing in this step needs
one. Work on `.env.example`, which is tracked and carries no values.

1. `.env.example` exists and already contains `TRACKER_PROVIDER` → do nothing.
2. `.env.example` exists without it → append:

   ```

   # Task tracker — overrides .claude/tracker.json on one machine (added by setup)
   TRACKER_PROVIDER=
   TRACKER_LIST_ID=
   ```

3. `.env.example` does not exist → create it with the same block.

With a tracker chosen at 6.1, add the key a headless run needs, commented —
`# CLICKUP_API_TOKEN=` and `# CLICKUP_TEAM_ID=` for ClickUp, `# LINEAR_API_KEY=`
for Linear — when the file does not already name it. A developer working in a
session never needs one: the MCP authorises over OAuth.

In every case, close with one line for the summary:
`task tracker variables declared in .env.example — they override .claude/tracker.json on one machine (setup cannot write .env)`

---

## Step 7b — Branch protection on the reference branch

"One review required" and "no direct push to the reference branch" are not
prose: they are settings on the host, so this step sets them there.

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

---

## Step 7d — The auto-dev configuration

An unattended run has nobody to ask. Which tag marks a task as the agent's and
where the designs live are **project** facts, not session facts — so they
belong in a file the project owns rather than in answers nobody will be there
to give. Which board it pulls work from, and what that board calls its
statuses, is already one: `.claude/tracker.json`, written at 6.1.

That file is `.claude/auto-dev.json`. It holds a tag and ids, and no credential
ever: the tracker's authorization stays in its MCP server's OAuth and the Figma
one in its own. So the file is tracked — a runner that clones the repository is
configured by the clone.

The plugin's own commands do not read it: `sdd`, `quick`, `auto-sdd` and
`multi-sdd` resolve those facts from the session and from the repository. This
file is what a runner with no session to ask — a scheduled routine, a CI job —
starts from, together with `tracker.json`, and writing it is how a project
declares itself available for one.

Runs in every mode, on every project with a tracker. With `none` at 6.1 the
step ends with `auto-dev not configured: no task tracker (6.1)`.

### 7d.1 — The gate

`.claude/auto-dev.json` **already exists** → print what it configures (tag,
Figma) and ask "Reconfigure the autonomous dev flow?" — **default: keep it**.
On a keep the step ends with the summary line
`auto-dev configuration kept as it was (tag <tag>)`. A kept file that still
carries `clickup_list_ids` or `status` predates the tracker file: nothing reads
those keys, and the line says so — `… (tag <tag>; its lists and statuses now
live in .claude/tracker.json)`.

Otherwise ask, once:

> "Configure the autonomous dev flow (auto-dev)? It writes
> `.claude/auto-dev.json`: the tag that marks a task as the agent's and the
> Figma file the designs live in. It reads the lists and the statuses from
> `.claude/tracker.json`. (yes / skip)"

A **skip** writes nothing and ends the step with one line for the summary:
`auto-dev declined: no .claude/auto-dev.json — an unattended run has nothing to read; run the setup again to add it`.
Nothing else in the procedure depends on the answer.

### 7d.2 — The two answers

Ask them in **one** `AskUserQuestion` call and end the turn on it: they are two
fields of a single file, with no follow-up to lose between them.

| Field | Question | First option (the default) | What free text accepts |
|---|---|---|---|
| `tag` | "Which tag (ClickUp) or label (Linear) marks a task as the agent's?" | `claude` | any name, as the board spells it |
| `figma` | "Which Figma file holds this project's designs?" | "No Figma file" | the file URL |

The Figma question is asked under the same condition as 6.3 — `HAS_FRONTEND` or
`HAS_MOBILE`, or a web/mobile/fullstack stack chosen at 2b. On a pure backend it
is not asked and `figma` is `null`. Both answers go in the summary line of 7d.4.

### 7d.3 — The two fields nobody is asked about

- **`base_branch` is always `null`.** Null means "resolve it per run", which is
  what `check-prerequisites.sh` does from the repository itself. A name written
  here pins every future run to whatever was the reference branch on the day of
  the setup — the defect Step 7b.1 exists to avoid, one layer down. Pinning one
  deliberately is a one-line edit of the file.
- **`dry_run` is `false`.** `true` makes a run do everything up to the push —
  branch, spec, code, commit — and stop before the push, the merge request and
  the board write. It is worth one rehearsal run on a project nobody has tried
  this on yet, and it is a one-word edit, not another question here.

### 7d.4 — Write it

```bash
mkdir -p .claude

if [ -n "$FIGMA_URL" ]; then
  FILE_KEY=$(printf '%s' "$FIGMA_URL" \
             | sed -E 's#.*figma\.com/(design|file|board|proto)/([A-Za-z0-9]+).*#\2#')
  [ "$FILE_KEY" = "$FIGMA_URL" ] && FILE_KEY=""   # no match: sed echoed the input back
  FIGMA=$(jq -n --arg k "$FILE_KEY" --arg u "$FIGMA_URL" '{file_key: $k, url: $u}')
else
  FIGMA=null
fi

jq -n \
  --arg tag "$TAG" \
  --argjson figma "$FIGMA" \
  '{
     tag: $tag,
     base_branch: null,
     figma: $figma,
     dry_run: false
   }' > .claude/auto-dev.json
```

An empty `FILE_KEY` means the URL was not a Figma file URL: write `"figma": null`
instead of an object with a blank key, and say so in the summary line. What
lands looks like this:

```json
{
  "tag": "claudio",
  "base_branch": null,
  "figma": { "file_key": "wMJHvCjPaCfK6765aKTfgn", "url": "https://www.figma.com/design/wMJHvCjPaCfK6765aKTfgn/V-Program" },
  "dry_run": false
}
```

**Report in the summary** exactly one line — one of:

```
  - auto-dev configured: tag <tag>, Figma <file_key|none>, dry_run false — lists and statuses from .claude/tracker.json
  - auto-dev configuration kept as it was (tag <tag>)
  - auto-dev declined: .claude/auto-dev.json not written — an unattended run has nothing to read
  - auto-dev not configured: no task tracker (6.1)
```
