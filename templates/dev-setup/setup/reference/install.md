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
Linux/WSL2). It denies reads and writes of the `.env` family, denies reads of
`~/.ssh`, `~/.aws` and `~/.kube`, unsets the usual token variables inside
sandboxed commands, and pre-allows a small set of network domains that 3.4
adapts to this project. **The file you have just written is the security
boundary of the project: from here on, you cannot read or write `.env`, and
neither can the shell commands you run.** That is intentional —
`mcp-env.md` is written to work without ever touching it.

`.claude/settings.user.json` is **not** installed here: it is a user-scope
snippet, handled in 3.5.

**If the project's own test or dev command loads one of the denied files**, the
sandbox will break it — the deny covers every sandboxed command, not just the
ones Claude writes. Tell the developer, and fix it by deleting that filename
from `sandbox.filesystem.denyRead` in `.claude/settings.json`. A `denyRead`
entry cannot be re-opened from another settings file: `.claude/settings.local.json`
can only add denies, never remove them. The `credentials.envVars` block stays
either way, so the token variables remain unset inside sandboxed commands.

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
that the sandbox denies reading `.env`. A rule that describes a mechanism the
project does not have is the exact defect this plugin exists to remove.

So: a settings.json **with** a `sandbox` key is the team's, and conflict
detection applies. One **without** it is an old artefact, and it gets migrated.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/migrate-settings.sh \
  --in .claude/settings.json \
  --template "${CLAUDE_SKILL_DIR}/templates/settings.json" \
  --out .claude/settings.json.migrated \
  --json
```

The script never writes in place. It reports `MIGRATED`, `REASON`,
`ADDED_SANDBOX`, `ADDED_ASK`, `ADDED_DENY`, `RETIRED_ALLOW` and `KEPT_ALLOW`,
and exits `3` with `REASON: already-sandboxed` when there is nothing to do — in
which case delete the `.migrated` file and move on.

When it did migrate, show the developer what it changed and ask once:

> "`.claude/settings.json` predates the Bash sandbox. Migrating it adds the
> sandbox block (filesystem, network and credential isolation), the `ask`
> checkpoints on `gh pr create` / `glab mr create` and on ClickUp writes,
> `<ADDED_DENY>` deny rules (force push, protected branches, `--no-verify`,
> `.env`, lock files), and drops `<RETIRED_ALLOW>` from the allowlist. Your own
> entries are kept: `<KEPT_ALLOW>`. Apply it? (yes / skip)"

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
  - label: "Keep SSH"          (git network commands run outside the sandbox)
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

- **Keep SSH** → nothing to change. `git fetch`/`git push` will hit a sandbox
  violation and Claude Code will retry them outside the sandbox, which sends
  them through the normal permission flow: in Manual mode the developer confirms
  each one. The `deny` rules on force push and on the protected branches still
  apply — they are permission rules, and they are evaluated whether or not the
  command runs sandboxed.

**Report in the summary** (a single line):

- HTTPS remote: `origin already on HTTPS — git works inside the sandbox`
- switched: `switch origin to HTTPS: <command printed>`
- kept SSH: `origin left on SSH — git network commands will run unsandboxed, with a confirmation each time`

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
