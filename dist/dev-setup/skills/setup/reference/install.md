# Steps 2c and 3 — VCS detection and installing the resources

Runs in every mode. Step 2c decides which host the project belongs to; Step 3
writes the plugin's files into it. Nothing here is specific to a mode: the only
difference is where the detected values came from, and by now the mode's own
reference has produced them.

## Index

- [Step 2c — VCS detection](#step-2c--vcs-detection)
- [3.1 — Transformed files](#31--transformed-files-read-into-memory)
- [3.2 — Verbatim files](#32--verbatim-files-straight-to-destination)
- [3.2b — Migrate a pre-sandbox settings.json](#32b--migrate-a-settingsjson-written-before-the-sandbox)
- [3.3 — Adapt the allowlist to the package manager](#33--adapt-the-allowlist-to-the-detected-package-manager)
- [3.4 — Compose the sandbox network allowlist](#34--compose-the-sandbox-network-allowlist)
- [3.5 — Credential masking](#35--credential-masking-user-scope-optional)
- [3.6 — Git over the sandbox: SSH remotes](#36--git-over-the-sandbox-ssh-remotes)
- [3.7 — The worktree files](#37--the-worktree-files)
- [3.8 — The pull/merge request template](#38--the-pullmerge-request-template)
- [3.9 — The merge request metadata and the labels](#39--the-merge-request-metadata-and-the-labels)

---

## Step 2c — VCS detection

`detect-stack.sh` reports whether the project is a git repository at all; which
host it belongs to is decided here, because it drives Steps 5, 7b, 8.4, 8.6 and
the summary.

1. Read the remote URL:

   ```bash
   git -C <project-root> remote get-url origin 2>/dev/null
   ```

   If `origin` does not exist, use the first available remote (`git remote | head -1`).

2. If there is no `.git` or no remote configured:
   - `vcs = none`
   - Tell the developer: "No Git remote detected. VCS-specific files (CI,
     `.releaserc.json`) will not be installed."
   - Skip to Step 3.

3. Otherwise, lowercase the URL and classify:
   - contains `github.com` → `vcs = github`
   - contains `gitlab` (any host, e.g. `gitlab.com`,
     `gitlab.company.internal`) → `vcs = gitlab`
   - neither → go to point 4.

4. **CLI probe** for ambiguous self-hosted instances (e.g. `git@git.company.com:...`):
   - extract the hostname from the URL (handle both HTTPS and SSH);
   - run `gh auth status --hostname <host> 2>/dev/null` and
     `glab auth status --hostname <host> 2>/dev/null`;
   - if exactly one of them recognizes the host → `vcs = <that one>`;
   - if neither or both do, ask with `AskUserQuestion`:

     ```
     question: "Which Git provider does this project use?"
     options: [ {label: "GitHub"}, {label: "GitLab"}, {label: "Other / none"} ]
     ```

   - "Other / none" → `vcs = other` (treated the same as `none` for
     VCS-specific files).

5. Report the detected VCS before proceeding. Save the value — the rest of the
   procedure calls it `{VCS}`.

---

## Step 3 — Install the resources from the plugin

### 3.1 — Transformed files (read into memory)

These need adapting before they land in the project.

**Rule templates** (rendered in Step 4): they stay on disk —
`render-template.sh` reads them itself, so there is nothing to load into context
here. They live in `${CLAUDE_SKILL_DIR}/templates/rules/`.

**AGENTS template** (processed in Step 5):

- single project → `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md`
- multi-project (or the fullstack stack) →
  `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md` **and**
  `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`

**Stack profile** — GREENFIELD only, applied at Step 8.5. Read the profile the
chosen stack calls for from `${CLAUDE_SKILL_DIR}/templates/profiles/`:
`web-frontend.md`, `backend-node.md`, `mobile.md`, `terraform.md`, or both
`web-frontend.md` and `backend-node.md` for full-stack. In EXISTING and UPDATE
there is nothing to read: those modes do not configure the project's tooling.

`nextjs.md` is the exception — Step 5 consults it in any mode, for the Next.js
`AGENTS.md` convention, on a project that uses Next.js.

### 3.2 — Verbatim files (straight to destination)

These are copied exactly. Before every write, check whether the destination
already exists (**conflict detection**): if it does, tell the developer and keep
the existing one, skipping the write.

**settings.json** (project permissions + Bash sandbox). If
`.claude/settings.json` does **not** exist:

```bash
mkdir -p .claude
```

Read `${CLAUDE_SKILL_DIR}/templates/settings.json` and write it to
`.claude/settings.json`. If it already exists, tell the developer and keep
theirs.

The file carries a `sandbox` block that turns on OS-level filesystem and network
isolation for every Bash command Claude runs (Seatbelt on macOS, bubblewrap on
Linux/WSL2). It denies writes of the `.env` family — reads stay open, so a task
can use the values it needs — denies reads of `~/.ssh`, `~/.aws` and `~/.kube`,
unsets the usual token variables inside sandboxed commands, and pre-allows a
small set of network domains that 3.4 adapts to this project. **The file you
have just written is the security boundary of the project: from here on,
neither you nor the shell commands you run can write `.env`.** The setup itself
still never touches the real file — `mcp-env.md` works on `.env.example`.

`.claude/settings.user.json` is **not** installed here: it is a user-scope
snippet, handled in 3.5.

**If the project's own test or dev command writes one of the denied files**,
the sandbox will break it — the deny covers every sandboxed command, not just
the ones Claude writes. Tell the developer, and fix it by deleting that
filename from `sandbox.filesystem.denyWrite` in `.claude/settings.json`. A deny
entry cannot be re-opened from another settings file:
`.claude/settings.local.json` can only add denies, never remove them. The
`credentials.envVars` block stays either way, so the token variables remain
unset inside sandboxed commands.

**REGISTRY.md** — single project: if `REGISTRY.md` does not exist (or the
developer confirms the overwrite), read
`${CLAUDE_SKILL_DIR}/templates/REGISTRY.md` and write it to `REGISTRY.md`.
Multi-project: one `REGISTRY.md` per confirmed sub-project, at
`<sub-project-path>/REGISTRY.md`, and none at the root.

**.gitignore** — if it does not exist, copy
`${CLAUDE_SKILL_DIR}/templates/.gitignore`.

**.env.example** — if it does not exist, copy
`${CLAUDE_SKILL_DIR}/templates/.env.example`.

**.worktreeinclude** — if it does not exist, copy
`${CLAUDE_SKILL_DIR}/templates/.worktreeinclude`. See 3.7 for what it does and
for the one `.gitignore` line that goes with it.

**IMPORTANT**: write the files you read **exactly as received**. Do not
reformat, do not adjust, do not improve. The content must be verbatim.

**Check**: verify that the written files are not empty. If one is, tell the
developer and stop.

**In UPDATE mode** `REGISTRY.md`, `.gitignore` and `.env.example` are the
project's, not generated artefacts: keep conflict detection on and ask before
touching them. (The `dev-setup-*.md` rules are the other exception, and
`rules-generation.md` explains why.)

`.claude/settings.json` is the case where "keep theirs" is the wrong answer —
see 3.2b.

### 3.2b — Migrate a settings.json written before the sandbox

Earlier versions of this setup wrote a `settings.json` holding nothing but
`permissions`: a wide allowlist (`npx`, `node`, `claude`), a deny list without
the force-push, `--no-verify` and `.env` entries, no `ask` block, and no
`sandbox` block at all. Conflict detection reads that file as the team's and
keeps it — so on a project set up before the sandbox landed, **none of the
protection arrives**, while `dev-setup-core.md` goes on telling every session
that the sandbox denies writing `.env`. A rule that describes a mechanism the
project does not have is the exact defect this plugin exists to remove.

So: a settings.json **without** a `sandbox` key is an old artefact, and it gets
migrated wholesale. One **with** it is the team's, and conflict detection
applies — with two exceptions, and the script touches nothing else: if it still
carries the `.env` read denies this template retired, it removes exactly those
entries (`REASON: env-read-unblocked`); if it lacks an entry of the template's
`sandbox.excludedCommands` (`gh *`, `glab *`, `git push origin *`,
`git push -u origin *`), it adds it next to the team's own and replaces a bare
`gh` / `glab` it supersedes (`REASON: excluded-commands-added`,
`RETIRED_EXCLUDED`) — together with the template's `deny` entries that guard an
excluded command, so a push never leaves the sandbox without the protected-branch
denies (`ADDED_DENY`; `REASON: excluded-commands-guarded` when only those were
missing).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/migrate-settings.sh \
  --in .claude/settings.json \
  --template "${CLAUDE_SKILL_DIR}/templates/settings.json" \
  --out .claude/settings.json.migrated \
  --json
```

The script never writes in place. It reports `MIGRATED`, `REASON`,
`ADDED_SANDBOX`, `ADDED_ASK`, `ADDED_DENY`, `RETIRED_ALLOW`, `KEPT_ALLOW`,
`RETIRED_DENY` and `ADDED_EXCLUDED`, and exits `3` with `REASON: already-sandboxed` when there is
nothing to do — in which case delete the `.migrated` file and move on.

When it did migrate with `REASON: migrated`, show the developer what it changed
and ask once:

> "`.claude/settings.json` predates the Bash sandbox. Migrating it adds the
> sandbox block (filesystem, network and credential isolation), the `ask`
> checkpoints on `gh pr create` / `glab mr create` and on ClickUp writes,
> `<ADDED_DENY>` deny rules (force push, protected branches, `--no-verify`,
> `.env` writes, lock files), and drops `<RETIRED_ALLOW>` from the allowlist.
> Your own entries are kept: `<KEPT_ALLOW>`. Apply it? (yes / skip)"

With `REASON: env-read-unblocked` or `excluded-commands-added` the file already
has the sandbox and only those two passes ran. Ask once, keeping the sentence
whose report key is not empty:

> "`.claude/settings.json` needs two small fixes from this plugin version.
> It still denies reading `.env` — reads are open now so a task can use the
> values it needs; writes stay denied: migrating removes `<RETIRED_DENY>`.
> It runs `gh` / `glab` inside the sandbox, where on macOS they cannot verify
> a TLS certificate and every call fails: migrating adds `<ADDED_EXCLUDED>` to
> `sandbox.excludedCommands` (replacing `<RETIRED_EXCLUDED>`, which matched only
> the bare command). The deny and ask rules still apply to it.
> Nothing else changes. Apply it? (yes / skip)"

- **yes** → replace `.claude/settings.json` with the migrated file. From here on
  the sandbox is real, and the rest of Step 3 treats the file as freshly
  written.
- **skip** → delete the `.migrated` file, leave theirs, and **say plainly in the
  summary that the project is running without the sandbox**, listing what is
  missing. Do not report a protection that was declined.

Never hand-edit the old file into shape instead of running the script: the merge
has to keep every entry the team added, and that is what it is for.

### 3.3 — Adapt the allowlist to the detected package manager

The template lists all three Node package managers (`Bash(npm *)`,
`Bash(pnpm *)`, `Bash(yarn *)`) in `permissions.allow`, because at plugin
release we do not know which one you will use. If the project has a single
unambiguous lock file, narrow the allowlist to the PM in use — an agent must not
invoke `yarn install` in a pnpm project and bypass the workspace/hoisting
conventions.

**Skip if**:

- `.claude/settings.json` was neither written at 3.2 nor migrated at 3.2b — the
  file is the team's and post-hoc edits are not yours to make;
- `LANG` does not include `node` (e.g. a pure Python/Go/Terraform project): the
  three entries stay to support the occasional `npx <tool>`.

`PKG_MANAGER` from `detect-stack.sh` already resolved the lock file. Handle the
edge cases it collapses:

| Lock files in root | Package manager |
|---|---|
| exactly one | that one — narrow the allowlist |
| more than one | **ambiguous** — do not touch the allowlist, report the anomaly in the summary |
| none (`package.json` present but never installed) | **none** — leave all three entries, report it in the summary |

**Allowlist changes** (only for an unambiguous PM): keep the entry for the
detected manager, remove the other two.

**Do not add `Bash(npx *)`, `Bash(pnpx *)`, `Bash(node *)` or `Bash(claude *)`.**
They were removed from the template on purpose: each of them executes arbitrary
code chosen at call time, so an allow rule for them is an allow rule for
everything — including `claude --dangerously-skip-permissions`. One-shot tools
such as `npx ctx7@latest` or `npx @next/codemod@latest` still work: with the
sandbox on, a command that stays inside the filesystem and network boundary runs
without a prompt anyway (`sandbox.autoAllowBashIfSandboxed`), and one that
leaves it is exactly the case that deserves a prompt.

**Leave the deny and ask arrays intact**: do NOT touch them.
`Bash(npm publish*)`, `Bash(pnpm publish*)`, `Bash(yarn publish*)` all stay — an
accidental `publish` through the "wrong" PM is still an event worth blocking —
and the `ask` entries are the human checkpoints on `gh pr create` /
`glab mr create` and on ClickUp writes.

**Implementation** (jq, idempotent, preserves the rest of the file):

```bash
# Detected PM == "pnpm"
jq '.permissions.allow -= ["Bash(npm *)", "Bash(yarn *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Detected PM == "yarn"
jq '.permissions.allow -= ["Bash(npm *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Detected PM == "npm"
jq '.permissions.allow -= ["Bash(yarn *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

`jq` is already a declared dependency of the plugin, so assuming it is present
is reasonable.

**Report in the summary** (a single line):

- unambiguous PM: `allowlist tightened to <pm>-only commands per detected lock file (<lockfile>)`
- multiple lock files: `multiple lock files detected (<list>) — allowlist left as default; consider committing to a single PM`
- no lock file but `node` detected: `no lock file present — allowlist left as default; the team should run \`<pm> install\` and re-run setup to tighten`

### 3.4 — Compose the sandbox network allowlist

The template ships a deliberately small `sandbox.network.allowedDomains`.
Rewrite it from what Steps 2 and 2c detected, so the project pre-allows the
registries and the forge it actually uses and nothing else.

**Skip if** `.claude/settings.json` was neither written at 3.2 nor migrated at
3.2b.

Start from an empty list and add the rows that apply:

| Condition | Domains to add |
|---|---|
| `node` in `LANG` | `registry.npmjs.org` |
| `PKG_MANAGER` is `yarn` | `registry.yarnpkg.com` |
| `python` in `LANG` | `pypi.org`, `files.pythonhosted.org` |
| Flutter / Dart detected | `pub.dev`, `storage.googleapis.com` |
| `go` in `LANG` | `proxy.golang.org`, `sum.golang.org` |
| Terraform detected | `registry.terraform.io`, `releases.hashicorp.com` |
| `{VCS}` == `github` | `github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com` |
| `{VCS}` == `gitlab`, host `gitlab.com` | `gitlab.com` |
| `{VCS}` == `gitlab`, self-hosted | the host from the remote URL (e.g. `gitlab.company.internal`) |
| `CLICKUP_SETUP_LIST_ID` set (see `mcp-env.md`) | `api.clickup.com` |

**Implementation** (jq, replaces the list wholesale):

```bash
# Example: Node + pnpm project on GitHub with ClickUp configured
DOMAINS='["registry.npmjs.org","github.com","api.github.com","codeload.github.com","objects.githubusercontent.com","raw.githubusercontent.com","api.clickup.com"]'
jq --argjson d "$DOMAINS" '.sandbox.network.allowedDomains = $d' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

A domain missing from the list is not a hard failure: the first time a sandboxed
command needs it, Claude Code asks the developer, and answering "Yes, and don't
ask again" records it in `.claude/settings.local.json`. The list only removes
the prompts the project is guaranteed to hit. (3.5 changes that prompt into a
deny.)

**Report in the summary** (a single line):
`sandbox network allowlist: <n> domains (<pm registry>, <vcs host>[, api.clickup.com])`

### 3.5 — Credential masking (user scope, optional)

Three sandbox keys are ignored when they come from a repository's
`.claude/settings.json` or `.claude/settings.local.json`, because they widen
what a project can do to the developer's machine: `sandbox.credentials.*`
entries with `"mode": "mask"`, `sandbox.network.tlsTerminate`, and
`sandbox.network.strictAllowlist`. Shipping them in the project template would
produce a config that reads as protection and enforces nothing — so they live in
`~/.claude/settings.json` instead, and the developer installs them.

Skip this if `.claude/settings.json` was neither written at 3.2 nor migrated at
3.2b: the deny entries this trades against are not in the project's file.

**You must not write `~/.claude/settings.json` yourself.** It is a protected
path: print the command and let the developer run it.

Ask with `AskUserQuestion`:

```
question: "How do gh/glab/npm authenticate on this machine?"
options:
  - label: "Interactive login"    (gh auth login / glab auth login — no token in the environment)
  - label: "Environment token"    (GH_TOKEN / GITLAB_TOKEN / NPM_TOKEN exported in the shell)
```

- **Interactive login** → nothing to install. The project settings already unset
  those variables inside sandboxed commands, and the CLIs keep working from
  their own credential store. Report it in the summary and move on.
- **Environment token** → the project settings would break those CLIs inside the
  sandbox, because `"mode": "deny"` unsets the variable. Replace deny with
  masking: the command sees a per-session placeholder, and the sandbox proxy
  swaps in the real value only on requests to the host you name. Two edits, in
  this order:

  1. Drop the masked variables from the project deny list — **`deny` wins over
     `mask` in every scope**, so a leftover deny entry silently disables the mask:

     ```bash
     jq '.sandbox.credentials.envVars |= map(select(.name as $n | ["GH_TOKEN","GITLAB_TOKEN","NPM_TOKEN"] | index($n) | not))' \
       .claude/settings.json > .claude/settings.json.tmp \
       && mv .claude/settings.json.tmp .claude/settings.json
     ```

     Keep the entries for the variables the project does not authenticate with.

  2. Give the developer this command to merge the snippet into their user
     settings (it is `${CLAUDE_SKILL_DIR}/templates/settings.user.json`, printed
     here so they can review it before running anything):

     ```bash
     jq -s '.[0] * .[1]' ~/.claude/settings.json <snippet-path> > /tmp/cc-settings.json \
       && mv /tmp/cc-settings.json ~/.claude/settings.json
     ```

     Trim the snippet to the variables and hosts that apply before printing it —
     an `injectHosts` entry authorizes the proxy to send a real credential to
     that host.

     The snippet also sets `network.strictAllowlist`, which turns "prompt for an
     unknown domain" into "deny it". Tell the developer they can drop that key
     to keep the prompt.

**Report in the summary** (a single line):

- interactive login: `credential masking not needed — gh/glab authenticate from their own store`
- environment token: `credential masking snippet printed for ~/.claude/settings.json (GH_TOKEN, ...); project deny entries removed for the masked variables`

### 3.6 — Git over the sandbox: SSH remotes

Sandboxed commands reach the network **only** through the sandbox's HTTP(S)
proxy. There is no raw TCP and no DNS for anything else, so a `git fetch` or
`git push` against an `ssh://` or `git@host:` remote fails inside the sandbox —
the hostname does not even resolve. This is a property of the sandbox, not of
the deny rules: it applies to every project whose `origin` is an SSH URL.

Check the remote read in Step 2c. If it starts with `git@` or `ssh://`, let the
developer pick with `AskUserQuestion`:

```
question: "origin is an SSH remote. Inside the Bash sandbox, git cannot reach it. How do you want to handle it?"
options:
  - label: "Switch to HTTPS"   (recommended — the forge CLI holds the credentials)
  - label: "Keep SSH"          (the push to origin runs outside the sandbox; fetch asks)
```

- **Switch to HTTPS** → print these for the developer to run; the credential
  helper keeps the token out of the URL and out of `ps`:

  ```bash
  # GitHub
  gh auth login && gh auth setup-git
  git remote set-url origin https://github.com/<org>/<repo>.git

  # GitLab
  glab auth login
  git config --global credential.helper '!glab auth git-credential'
  git remote set-url origin https://<host>/<group>/<repo>.git
  ```

  Make sure the HTTPS host is in the `sandbox.network.allowedDomains` written at
  3.4.

- **Keep SSH** → nothing to change. `git push origin …` and `git push -u origin …`
  are in `sandbox.excludedCommands`, so the push runs outside the sandbox
  directly — towards `origin` only, whose URL lives in `.git/config`, which the
  sandbox protects. `git fetch` and any other network command still hit a
  sandbox violation and are retried outside it through the normal permission
  flow. The `deny` rules on force push and on the protected branches (`-u`
  included) still apply — they are permission rules, evaluated whether or not
  the command runs sandboxed.

**Report in the summary** (a single line):

- HTTPS remote: `origin already on HTTPS — git works inside the sandbox`
- switched: `switch origin to HTTPS: <command printed>`
- kept SSH: `origin left on SSH — the push to origin runs unsandboxed; fetch asks each time`

### 3.7 — The worktree files

A worktree is a clean checkout, so a gitignored file is absent from it: the app
boots without `.env` and fails for a reason that looks like a code problem. Two
small artefacts prevent it, and both are additive.

**`.worktreeinclude`** (written at 3.2) lists, in `.gitignore` syntax, the files
Claude Code copies into every worktree it creates. Only a file that matches
**and is gitignored** is copied. If the project already has one, keep it and say
so. If the stack needs more than the template's env files — Flutter's
`android/local.properties`, a `*.tfvars` — say which lines to add rather than
adding them silently.

**One `.gitignore` line.** Whether the file is the one written at 3.2 or the
project's own, check it for `.claude/worktrees/`:

```bash
grep -q '^\.claude/worktrees/' .gitignore || printf '\n# Claude Code worktrees\n.claude/worktrees/\n' >> .gitignore
```

Without it, every file of every worktree shows up as untracked in the main
checkout. This is the one edit made to a `.gitignore` the setup did not write:
it adds a line, removes nothing, and the alternative is a `git status` nobody can
read.

The base ref a worktree forks from is Step 7c — it needs the reference branch,
which is resolved later.

**Report in the summary** (a single line):
`worktree files: .worktreeinclude <written|kept>, .gitignore worktrees entry <added|present>`

### 3.8 — The pull/merge request template

A merge request is reviewed against what its description says was done and how to
check it. That description is not improvised once per branch: the repository
carries the template, the flows fill it in, and every reviewer reads the same
shape. `vcs-ops` is the other half of this — it fills whatever template it finds
here, and falls back to its own body only when there is none.

**Skip if** `{VCS}` is `none` or `other`: with no forge there is nowhere to put
one. Report it in the summary and move on.

**Where it goes** — the host's convention, not a choice:

| `{VCS}` | Destination |
|---|---|
| `github` | `.github/PULL_REQUEST_TEMPLATE.md` |
| `gitlab` | `.gitlab/merge_request_templates/Default.md` |

GitLab reads merge request templates **only** from
`.gitlab/merge_request_templates/`. A file at `.gitlab/PULL_REQUEST_TEMPLATE.md`
is ignored by the web UI and invisible to `glab mr create --template`, so it
would be a template nothing ever applies — the one failure mode this step exists
to avoid. `Default.md` is the name both GitLab and `vcs-ops` look for first.

**Conflict detection, and what UPDATE does.** The destination already exists →
keep it, quote its first heading, and say so in the summary: a template is the
team's own document, and `vcs-ops` fills the one that is there. The destination
does not exist → write it, in every mode. That is how a project configured
before this step existed gets the template on its next UPDATE run.

**The language.** Ask once, with `AskUserQuestion` — **in every mode, on every
project with a forge**, unless `.claude/merge-request.json` already exists (its
`language` is the answer, and 3.9 keeps the file). The answer picks the template
file here and becomes the `language` 3.9 writes: `vcs-ops` reads it from there
to write every title and description, so this single answer decides what the
team reads on the forge.

```
question: "Which language should pull/merge request titles and descriptions be written in?"
options: [ {label: "Italian"}, {label: "English"} ]
```

Italian → `PULL_REQUEST_TEMPLATE.it.md`; English → `PULL_REQUEST_TEMPLATE.en.md`
(default: Italian, the team's own template — and, when a template is already in
place, the language it is written in). Everything else the setup writes stays in
English — this one answer is about the document a reviewer reads, not about the
code.

**Resolve the placeholders.** The template carries three, and
`render-template.sh` fails on any one left unresolved rather than committing a
`{{TODO}}` into the project:

```bash
REPO_URL=$(git remote get-url origin \
  | sed -E -e 's#^git@([^:]+):#https://\1/#' -e 's#^ssh://git@#https://#' -e 's#\.git$##')

BASE=$(${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh --json | jq -r .BASE_BRANCH)
REMOTE=$(git remote | head -1)
BASE_BRANCH=${BASE#"$REMOTE/"}   # BASE_BRANCH comes back remote-qualified
```

| Placeholder | `github` | `gitlab` |
|---|---|---|
| `{{MR_LINK_BASE}}` | `$REPO_URL/pull` | `$REPO_URL/-/merge_requests` |
| `{{BASE_BRANCH}}` | the branch resolved above — never a hard-coded `develop` | the same |
| `{{CODE_CONVENTIONS_LINK}}` | a whole markdown link, composed below | the same |

`{{CODE_CONVENTIONS_LINK}}` is a link and not a URL because what it points at
depends on the project. With `BLOB="$REPO_URL/blob/$BASE_BRANCH"` on GitHub and
`BLOB="$REPO_URL/-/blob/$BASE_BRANCH"` on GitLab:

- the repository has a `CODE_CONVENTIONS.md` → `[CODE_CONVENTIONS.md]($BLOB/CODE_CONVENTIONS.md)`
- it does not → the rules Step 4 writes are this project's conventions:
  `[.claude/rules/]($BLOB/.claude/rules)`

Then render it:

```bash
mkdir -p "$(dirname "$DEST")"
${CLAUDE_PLUGIN_ROOT}/scripts/render-template.sh \
  --in "${CLAUDE_SKILL_DIR}/templates/boilerplate/<the file chosen above>" \
  --out "$DEST" \
  --var MR_LINK_BASE="$REPO_URL/pull" \
  --var BASE_BRANCH="$BASE_BRANCH" \
  --var CODE_CONVENTIONS_LINK="[CODE_CONVENTIONS.md]($BLOB/CODE_CONVENTIONS.md)"
```

**The `Issue:` line ships as an example** — `DE-00000` on the team's ClickUp
workspace. It is the shape a PR author overwrites, not a live link. If this
project tracks its work somewhere else, say so in the summary line and leave the
correction to the developer: the setup does not invent a tracker URL.

**Report in the summary** (a single line) — one of:

```
  - pull request template written to <path> (<Italian|English>) — the flows fill it when they open a merge request
  - pull request template already at <path> — kept as the team wrote it
  - pull request template skipped: no forge configured for this repository
```

### 3.9 — The merge request metadata and the labels

The language answered at 3.8 and the labels a merge request carries are project
facts that the developers own, so they live in a tracked file they edit, not in
the plugin: `.claude/merge-request.json`. `mr-meta.sh` reads it whenever a flow
opens a merge request and returns the language, the title and the labels.

**Skip if** `{VCS}` is `none` or `other`, like 3.8.

**The file.** It exists → keep it as the team left it, and read its `language`
instead of asking at 3.8. It does not exist → write it, in every mode — that is
how a project set up before this step gets it on its next UPDATE:

```bash
mkdir -p .claude
jq --arg lang "<it|en>" '.language = $lang' \
  "${CLAUDE_SKILL_DIR}/templates/boilerplate/merge-request.json" \
  > .claude/merge-request.json
```

What the developers change in it, and what each key does:

| Key | Holds |
|---|---|
| `language` | `it` or `en` — the language of every title and description |
| `labels.catalog` | every label the team uses, with its colour: what this step creates on the forge |
| `labels.by_type` | branch type → labels (`feat` → `Type: Feature`) |
| `labels.breaking` | added when the change breaks a contract |
| `labels.by_priority` | the task's priority → labels (`high` → `Priority: High`) |
| `labels.on_open` | added to every merge request when it opens (`State: Pending`) |

The catalogue labels no mapping names — `Type: Bug`, `Work: *`, `State: Approved`,
`State: Blocked` — are the reviewers' to set by hand on the forge.

**Create the labels the forge is missing.** A merge request asking for a label
that does not exist fails as a whole on GitHub, so the catalogue is created here,
once, rather than discovered missing when a merge request opens. List what
exists, and create only what is absent — never `--force`, which would recolour a
label the team already has:

```bash
# GitHub
gh label list --limit 200 --json name --jq '.[].name' > "$TMPDIR/labels.txt"
jq -r '.labels.catalog[] | [.name, .color] | @tsv' .claude/merge-request.json \
  | while IFS=$'\t' read -r name color; do
      grep -Fxq "$name" "$TMPDIR/labels.txt" || gh label create "$name" --color "$color"
    done

# GitLab
glab label list --per-page 100 --output json | jq -r '.[].name' > "$TMPDIR/labels.txt"
# … the same loop, with: glab label create --name "$name" --color "#$color"
```

A `gh`/`glab` that is not authenticated, or a token without the right to create
labels, is not a reason to stop the setup: report which labels are missing and
leave them to the developer.

**Report in the summary** (a single line) — one of:

```
  - merge request metadata written to .claude/merge-request.json (<it|en>, <n> labels) — <k> label(s) created on the forge, <m> already there
  - merge request metadata kept as it was (<it|en>, <n> labels) — <k> label(s) created on the forge
  - merge request metadata written; labels not created (<reason>) — missing on the forge: <names>
  - merge request metadata skipped: no forge configured for this repository
```

