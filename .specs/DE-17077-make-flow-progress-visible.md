# Spec: [dev-setup] Make progress visible: notifications, session name, phases and next command [DE-17077]

> Status: implemented
> Task: https://app.clickup.com/t/869fb17f1
> Branch: `feat/DE-17077_make-flow-progress-visible` (created by `sdd-start.sh` at launch)
> Created: 2026-10-16
> Approved: 2026-10-16

## Context

A developer who starts a flow of this plugin and looks away cannot tell where it has got to. Today `templates/dev-setup` has no `Notification` hook, nothing sets a session title, and no flow publishes a task list. `auto-sdd` and `multi-sdd` runs work in the background ("wait for its notification, never poll", `templates/dev-setup/.claude/skills/auto-sdd/SKILL.md`). Their outcome is a decision the developer has to take: the `ask` rule on `gh pr create` / `glab mr create` for `ready-for-mr`, the `ask` rule on the `BLOCKED` move (`mcp__clickup__clickup_update_*`) for `failed`. Nothing calls the developer back for it. Claude Code's own notification says "Claude needs your permission" and does not say for which task. With five runs in flight that tells the developer nothing.

There are three more gaps. `claude --resume` lists sessions by their first prompt, not by task. During an `sdd` the phases are only in the skill's table, and the developer never sees them. The reports a flow closes on end in different ways: the stop-point report ends on `Resume: /dev-setup:sdd DE-123`, while the closure, `quick` and the autonomous outcomes end on a link or nothing, so the developer has to work out what to run next.

The task's own risk is the design constraint, the same one `post-merge-request.sh` was built on (AGENTS.md, "The obligation travels with the event"): **a hook that speaks when there is nothing to say gets switched off.** Every new hook stays silent unless a plugin task is in play here, and lets everything through when something it needs is missing.

What the installed client does (Claude Code 2.1.292, read from the hooks reference and the binary):

- `Notification` matches on `notification_type`. Values include `permission_prompt`, `idle_prompt`, `agent_needs_input` and `agent_completed`. The last two are emitted by the agent view (`claude agents`, the background-sessions roster) when a background session in its roster blocks or finishes, as `<session name> needs your input` / `<session name> finished`, and by the teammate-setup dialog; never when a `Workflow` run lands. The hook runs in the raising process's own session and cwd. It can't block or change the notification. It runs alongside the built-in one.
- `SessionStart` (matcher `startup|resume|clear|compact`) accepts `hookSpecificOutput.sessionTitle`. Its input carries `session_title` when a title is already set (`--name`, `/rename`), so that a hook can avoid overwriting it. `UserPromptSubmit` also accepts `sessionTitle` and carries `session_title` in its input. A title a hook sets is the name the agent view shows for that session.
- `preferredNotifChannel` (`auto`, `terminal_bell`, …): `auto` notifies only in iTerm2, Ghostty and Kitty. `terminal_bell` rings in any terminal.
- `footerLinksRegexes` is read from user, flag and managed settings only. Project `.claude/settings.json` ignores it. Its entries are `{ "type": "regex", "pattern", "url", "label" }`, with `{name}` placeholders filled from named capture groups.

## Requirements

- REQ-1: `hooks/notify.sh`, on a `Notification` payload whose `notification_type` is `permission_prompt`, sends exactly one desktop notification when a candidate task exists. The candidates are the tasks `task-clock.sh --status --json` reports in `OPEN_TASKS`, plus those in `RECENT_TASKS` (REQ-14). If the branch of the payload's `cwd` names one of the candidates (`branch_task_id` in `common.sh`, matched between delimiters as `post-merge-request.sh` does), the title carries that one; otherwise it carries all of them, space-separated. The title is `dev-setup · <TASK_IDS>` and the body is the payload's `message`. The delivery is `osascript` (`display notification`, title and body passed as `argv`, never interpolated into the script) when `uname -s` is `Darwin`, and `notify-send <title> <body>` when it is `Linux`.
- REQ-2: `notify.sh` is silent when there is nothing to say. That means: no candidate, whatever the branch is called (a task branch with no open or just-stopped clock is not a signal), or any other `notification_type` (`idle_prompt`, `auth_success`, `agent_needs_input`, `agent_completed`, …) even with a task open. Silent means no notifier invoked, empty stdout and exit 0.
- REQ-3: `notify.sh` fails open. With no `jq`, no plugin scripts found, a `cwd` outside a git repository, an unsupported OS, or a notifier command missing or failing, it exits 0 with an empty stdout, and at most a diagnostic line on stderr.
- REQ-4: An `auto-sdd` run whose outcome waits for the developer produces a notification naming its task, even though the launcher's checkout is on a branch with no task id. `ready-for-mr` raises `permission_prompt` on `gh pr create` / `glab mr create` while the run's clock is still open (`run-outcomes.md`: `vcs-ops` is invoked before `--stop`), so the open clock names it. `failed` raises `permission_prompt` on the `BLOCKED` update seconds after `--stop` (`run-outcomes.md`, failed step 3), so that task is in `RECENT_TASKS`.
- REQ-5: `hooks/session-title.sh`, on `SessionStart` with `source` `startup` or `resume`, in a `cwd` whose branch carries a task id, prints one JSON object `{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"<TASK_ID> <slug>"}}`. The slug is the branch text after the id and its delimiter, so `feat/DE-123_add-user-auth` and `feat(auth)/DE-123_add-user-auth` both give `DE-123 add-user-auth`, and the legacy `feat/DE-123-add-x` gives `DE-123 add-x`.
- REQ-6: `session-title.sh` never overwrites a title the developer chose. A non-empty `session_title` in the payload that does not start with a task id (`^[A-Z][A-Z0-9]*-[0-9]+( |$)`) makes it silent. A title that does start with one is the hook's own earlier answer, so it is replaced when it differs, and the hook stays silent when it is already equal.
- REQ-7: `session-title.sh`, on `UserPromptSubmit`, sets the title when the prompt launches a single-task flow: `^/dev-setup:(sdd|quick|auto-sdd)[[:space:]]+<TASK_ID>`. That covers a session opened on `next` that cuts its branch mid-session, where `SessionStart` has already run. The title is `<TASK_ID> <slug>` when a local branch carries that id, `<TASK_ID>` otherwise, with `hookEventName: "UserPromptSubmit"`. Any other prompt, including `/dev-setup:multi-sdd`, leaves it silent, and REQ-6 applies.
- REQ-8: `session-title.sh` is silent on a branch without a task id, and fails open like REQ-3: no `jq`, not a repository, no scripts → exit 0 with an empty stdout.
- REQ-9: Both hooks are mounted through the plugin. The `hooks` block of `templates/dev-setup/.claude/settings.json` declares four handlers: `Notification` with matcher `permission_prompt` → `notify.sh`; `SessionStart` with matcher `startup|resume` → `session-title.sh`; `UserPromptSubmit` → `session-title.sh`; and the existing `compact` handler, unchanged. `templates/dev-setup/manifest.json` lists both scripts. The generated `dist/dev-setup/hooks/hooks.json` carries the three new handlers with `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/` paths, and both scripts ship in `dist/dev-setup/hooks/scripts/`.
- REQ-10: During an `sdd` the phases are a visible, updated task list. `sdd/reference/intake.md` tells the flow to publish one through the session's task-list tool (`TaskCreate`/`TaskUpdate`, or `TodoWrite` where that is the tool the session has), once the brief is shown. The list holds Intake, Discovery, Spec, Approval, then what the saved stop point reaches: `spec` stops there; `development` adds Development; `review` adds Development and Gates; past Gates the last phase is named after the stop point — `commit` → `Commit`, `push` → `Commit and push`, `merge-request` → `Commit and merge request`. On a resume, the phases already passed are created completed. Each phase is marked in progress when it starts and completed when it ends. Between tool calls the flow writes at most one line of commentary.
- REQ-11: Every report a flow closes on ends with a `Next:` line carrying the exact command to run next:
  - the stop-point report in `sdd/reference/stop-point.md` ends `Next: /dev-setup:sdd <id>`, replacing `Resume:`;
  - the closure (`sdd/reference/closure.md` step 9), `quick` step 6 and the `ready-for-mr` outcome in `reference/run-outcomes.md` end on `Next:` and the follow-its-CI command from the host reference `vcs-ops` loaded. None of the three files names `gh` or `glab`;
  - `shared/skills/vcs-ops/reference/github.md` gets the row `Follow its CI | gh pr checks <n> --watch`, and `gitlab.md` the row `Follow its pipeline | glab ci status --live --branch '<BRANCH>'` (the branch is explicit, because the `auto-sdd` launcher sits on the developer checkout, not on the merge request's branch);
  - a declined merge request ends `Next: /dev-setup:sdd <id>` in the closure, and `Next:` with the host reference's open command in `quick` and `ready-for-mr`;
  - the `failed` outcome ends `Next: cd "<worktreePath>" && <the command that failed>` at stage `verify`, `Next: cd "<worktreePath>"` at stage `dev`, `Next: /dev-setup:sdd <taskId>` at stage `spec`, and `Next: /dev-setup:auto-sdd <taskId>` at stage `intake`.
- REQ-12: At intake, a task that meets `quick`'s bar is named in the brief with the exact command. The bar is at most three files and no new component, dependency or public interface. The brief line is `Route: looks like quick — /dev-setup:quick <id>`, and the flow goes on in `sdd`. `sdd` never moves itself to a lighter flow; only `quick` offers the heavier one, as it already does. The choice stays with the developer (DE-16480).
- REQ-13: The documentation covers the new behaviour:
  - `docs/onboarding.md` gets one line on `preferredNotifChannel` (`"terminal_bell"` for terminals with no desktop notification), and the `footerLinksRegexes` entry that turns `DE-\d+` into a ClickUp link, stated as user or managed settings, never the project's `.claude/settings.json`. The page stays within its 120-line cap;
  - `docs/developer-guide.md` §1 ("Where you are, without a turn") names `notify.sh` and `session-title.sh` and when each speaks;
  - `AGENTS.md`'s hooks section gets a paragraph on them, the `task-clock.sh` row lists `RECENT_TASKS`, and its version is bumped;
  - checks 14–15 stay clean.
- REQ-14: `task-clock.sh --status` (with or without `--task`) also reports `RECENT_TASKS`: every task in this repository whose last log line is a `stop` less than 300 seconds old, space-separated. A task with an open interval is never in it, and the call still writes nothing.

## Technical decisions

- **Both hooks follow `post-merge-request.sh` exactly: they read, report and stay quiet.** They use the same script locator (`$CLAUDE_PLUGIN_ROOT/scripts`, then the template layout, then the built one), source `common.sh` for `branch_task_id`, and call `task-clock.sh --status`, the reader that consumes nothing. Neither stops a clock or writes state. Neither exits 2, and the existing "no hook exits 2" assertion already globs `hooks/*.sh`. `notify.sh` prints nothing on stdout: a `Notification` hook has no decision control. Its whole effect is the side effect.
- **The clocks are the noise filter; the branch only narrows** (1 over 3). The task's Risk points at `post-merge-request.sh`, which takes the open clocks and narrows them by the branch, never using the branch alone: an open clock is the precise signal that a flow of this plugin moved a task to `IN PROGRESS` here (AGENTS.md, point 2). A task branch alone is not that signal, since under the `vcs-ops` convention every tracked branch carries an id. A notification with no candidate is left to Claude Code's built-in one, so the hook never doubles it there. With several candidates (a `multi-sdd` fan-out, capped at five) and a branch that names none of them, the title lists them all: the payload does not say which run is asking, and guessing one would be worse than naming the set.
- **A clock stopped in the last five minutes is still a candidate** (2 within 1). The `failed` outcome stops its clock and then makes the one `BLOCKED` update, with the clock's `COMMENT` riding that same call (`clickup-contract.md`, "The work clock": never a second write). So the stop cannot move after the prompt, and an open-clock-only reader would leave the `failed` half of the acceptance criterion silent. `RECENT_TASKS` is a read-only key on the existing reader: it reads the same per-task logs (`stop\t<epoch>\t…`) and writes nothing, so the contract "asking whether work is open must not consume the measurement" holds. 300 seconds covers the seconds between `--stop` and the prompt with room to spare, and is short enough that a task closed earlier in the day is not named on unrelated prompts. The same window also names `ready-for-mr`'s `CODE REVIEW` move, which follows its `--stop`.
- **`notify.sh` speaks on `permission_prompt` only** (1 over 3). Task proposal 1 lists `agent_needs_input` and `agent_completed`, but on 2.1.292 the client raises them only from the agent view, one per background session, as `<session name> needs your input` / `<session name> finished`, and it runs the hook in the agent view's own cwd. `session-title.sh` sets that name to `<TASK_ID> <slug>`, so the client's own notification already names the task, while a branch or clock read from the agent view's checkout could only name the wrong one. A `Workflow` run raises neither. `permission_prompt` is the event that carries REQ-4: both autonomous outcomes reach the developer through an `ask` rule, `ready-for-mr` while its clock is open and `failed` seconds after its stop. The task's worry that it is too noisy is answered by the candidate filter, not by dropping the event: outside a task in play it never makes the hook speak.
- **Delivery is the OS notifier, chosen by `uname -s`, with no terminal bell from the hook.** A hook's stdio is piped to the harness, so a bell written there reaches no terminal. Ringing the terminal is what `preferredNotifChannel: "terminal_bell"` already does, which is why onboarding documents that setting instead of the hook re-implementing it. Choosing by `uname` rather than by which command exists is also the test seam: the suite stubs `uname`, `osascript` and `notify-send` on `PATH` and asserts both paths on any CI host. `osascript` gets the title and body as `argv` (`on run argv`), so a message with quotes cannot break or inject into the AppleScript.
- **The session title is set from two events, not one** (precedence 2 over 3). The task proposes a `SessionStart` hook, and that covers a session opened or resumed on a task branch, which is the acceptance criterion. But the common `sdd` path opens Claude on `next` and cuts the branch mid-session. `SessionStart` has run by then, and the session would never be titled. `UserPromptSubmit` is the other documented carrier of `sessionTitle`. It is narrowed to the prompt that launches a single-task flow, so it acts once per task and only on an explicit command. The cost is one short process per prompt, which exits on the first `case` that does not match.
- **The title is `<TASK_ID> <slug>`, read from git, never from ClickUp.** A hook has no board access and must not get any. The slug is what the branch already carries, in English, as `sdd-start.sh` wrote it, so `claude --resume` shows `DE-123 add-user-auth`.
- **A title that starts with a task id is treated as the hook's own** and may be replaced. Any other title is the developer's and is kept. The `session_title` field exists so a hook can make exactly this check.
- **The phase list lives in `sdd/reference/intake.md`, not `sdd/SKILL.md`.** `sdd/SKILL.md` is at 499 of its 500 words, so the instruction goes where the flow reads it at intake, before the first phase transition. The SKILL.md flow table already names the step boundaries the list follows. The phases are the steps of that table, with the closure split where the stop points split it: Gates (closure 1–5), then the commit step, named after what the stop point makes it do (Commit, Commit and push, Commit and merge request). Phases past the stop point are not listed, because a list promising a merge request the run will not open, or hiding the commit it does make, is the opposite of visible.
- **The next command is a `Next:` line on the last line of the report, never a question.** A question is a stop, and DE-16480 and DE-17076 brought the interactive flow down to three. After a merge request the next thing is its CI, so the line is the host's follow-its-CI command. That is how proposal 5 (follow the CI) lands without adding a stop or a fix loop. `stop-point.md`'s `Resume:` becomes `Next:` so that every closing report has the same last-line shape and one assertion covers them all. `run-outcomes.md` is the single place both launchers handle an outcome, so `auto-sdd` and `multi-sdd` inherit the line without either SKILL.md (at 498 and 499 words) changing.
- **The host command lives once, in `vcs-ops`** (1). The flows are host-agnostic by design: closure step 8 says `vcs-ops` "loads its GitHub or GitLab reference accordingly, so there is nothing to pick here", and `vcs-ops` keeps in those two files "only what differs: the CLI invocations". So the follow-its-CI command is a row in `github.md` / `gitlab.md`, next to the existing `CI runs` / `Pipeline` rows, and the three closing reports point at it. The GitLab row passes `--branch '<BRANCH>'`, because `glab ci status` defaults to the current branch and the `auto-sdd` launcher sits on `next`. One host-agnostic line also costs `quick/SKILL.md` (499/500 words) fewer words than two host variants.
- **Routing at intake points up the weight scale only.** `sdd/SKILL.md` already says "say so in one line when a task looks misrouted". Intake makes that line concrete and exact (`Route: … /dev-setup:quick <id>`) and carries on: `sdd` never switches itself down. `quick`'s existing `Route` question to switch up to `sdd` is unchanged.
- **The UPDATE path.** Hooks reach a project through `dist/dev-setup/hooks/hooks.json`, generated by `scripts/builders/build-claude.sh` from the template's `hooks` block, and `task-clock.sh` and the `vcs-ops` references ship in the plugin. The settings the setup writes carry only `permissions` and `sandbox`. A project picks the change up on the plugin update, and `migrate-settings.sh` has nothing to migrate. `footerLinksRegexes` and `preferredNotifChannel` are user settings: they are documented, and the setup writes neither, because the client ignores `footerLinksRegexes` in project settings and the notification channel is a per-machine choice.
- **Precedence applied.**
  - (1) beat (3) on the acceptance criterion "un `auto-sdd` che termina con `needs-human`". `needs-human` no longer exists: `reference/run-outcomes.md`, "Nothing waits for a person", the DE-16864 decision recorded in AGENTS.md. The outcome the criterion promises (2), a notification naming the task when a run needs the developer, is delivered on the two outcomes that do exist (REQ-4), through `permission_prompt` and the open or just-stopped clock.
  - (1) beat (3) on proposal 1's list of types: `agent_needs_input` and `agent_completed` are not mounted, for the reasons above.
  - (1) beat (3) on proposal 5's "proporre di seguire la CI con Monitor e di correggere i fallimenti". An offer is a stop, and the project removed stops from the flow. What survives is the `Next:` CI command (REQ-11), and the developer runs it or asks for it.
  - (2) extended (3) on proposal 2 "un hook SessionStart": `UserPromptSubmit` is added for the mid-session branch (REQ-7).

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/hooks/notify.sh`
  - `templates/dev-setup/.claude/hooks/session-title.sh`
  - `dist/dev-setup/hooks/scripts/notify.sh` (generated)
  - `dist/dev-setup/hooks/scripts/session-title.sh` (generated)
- **Files to modify**:
  - `templates/dev-setup/.claude/scripts/task-clock.sh` (`--status` reports `RECENT_TASKS`)
  - `templates/dev-setup/.claude/settings.json` (`hooks` block: `Notification`, `SessionStart` `startup|resume`, `UserPromptSubmit`)
  - `templates/dev-setup/manifest.json` (`hooks` list)
  - `templates/dev-setup/.claude/skills/sdd/reference/intake.md` (the phase list, the `Route:` line)
  - `templates/dev-setup/.claude/skills/sdd/reference/stop-point.md` (`Resume:` → `Next:`)
  - `templates/dev-setup/.claude/skills/sdd/reference/closure.md` (step 9 ends on `Next:`)
  - `templates/dev-setup/.claude/skills/quick/SKILL.md` (step 6 ends on `Next:`, word-neutral)
  - `templates/dev-setup/.claude/reference/run-outcomes.md` (`Next:` for both outcomes)
  - `shared/skills/vcs-ops/reference/github.md` (`Follow its CI` row)
  - `shared/skills/vcs-ops/reference/gitlab.md` (`Follow its pipeline` row)
  - `scripts/test-plugin-scripts.sh` (sections 11, 12c, 12d, 15)
  - `docs/onboarding.md`
  - `docs/developer-guide.md`
  - `AGENTS.md`
  - `dist/dev-setup/hooks/hooks.json`, `dist/dev-setup/scripts/task-clock.sh`, `dist/dev-setup/skills/**` (including `skills/vcs-ops/reference/`), `dist/dev-setup/reference/run-outcomes.md` (regenerated by `bash scripts/build-plugin.sh dev-setup`, never edited by hand)
- **Dependencies**: none. Bash and `jq` only, per the script contract. `osascript` and `notify-send` are used when the OS has them, never required.

## Implementation plan

Each step regenerates `dist/` with `bash scripts/build-plugin.sh dev-setup` and commits it with its sources, so the `verify` CI job stays green on every commit.

1. **`feat(hooks): notify the developer with the task id when a flow needs them [DE-17077]`.**
   - `task-clock.sh`: in the repository-wide pass that builds `OPEN_TASKS`, also collect `RECENT_TASKS` (last line a `stop` whose epoch is within 300 s of `NOW_EPOCH`), emit it, and add it to the header comment. Add the section 11 assertions.
   - Write `notify.sh`: locator, `jq` guard, type filter (`permission_prompt` only), `task-clock.sh --status --json` → `OPEN_TASKS` + `RECENT_TASKS` as candidates, none → exit 0; `cwd` → branch → `branch_task_id` narrows to one candidate when it matches; `uname -s` → `osascript` with argv | `notify-send` | nothing, every failure → exit 0.
   - Mount it in `settings.json` under `Notification` with matcher `permission_prompt`, and add it to `manifest.json`.
   - Add section 12c of the suite: Tests 1–4.
2. **`feat(hooks): name the session after the task [DE-17077]`.**
   - Write `session-title.sh`: one script, branching on `hook_event_name`. `SessionStart` reads the `cwd` branch. `UserPromptSubmit` matches the single-task launch prompt and finds a local branch carrying the id with `git for-each-ref refs/heads` + `branch_task_id`. The `session_title` guard applies to both. Output is built with `jq -n`.
   - Mount it under `SessionStart` (matcher `startup|resume`, a second entry next to `compact`) and `UserPromptSubmit`, and add it to `manifest.json`.
   - Add section 12d: Tests 5–9.
3. **`feat(sdd): show the flow's phases as a task list [DE-17077]`.**
   - Add the phase-list section to `intake.md`: when to create it, the phases, the stop-point mapping of REQ-10, the resume rule, the in-progress/completed marks, and the one-line-of-commentary rule.
   - Add the `Route:` line to the brief template and its rule to step 4.
   - Add section 15 assertions: Tests 10 and 12.
4. **`feat(sdd): end every closing report on the next command [DE-17077]`.**
   - `vcs-ops` `github.md` / `gitlab.md`: the follow-its-CI rows.
   - `stop-point.md`: `Resume:` → `Next:`.
   - `closure.md` step 9: the final report ends on `Next:` and the host reference's follow-its-CI command; declined → `Next: /dev-setup:sdd <id>`.
   - `quick/SKILL.md` step 6: the same host-agnostic line, declined → the host reference's open command. Keep it word-neutral by tightening "Expected output", so check 2 stays at or under 500.
   - `run-outcomes.md`: `Next:` for `ready-for-mr`, declined, and each `failed` stage.
   - Add Test 11.
5. **`docs: document notifications, session titles and clickable task ids [DE-17077]`.**
   - `onboarding.md`: a short "Know where a flow is" section with the `preferredNotifChannel` line and the `footerLinksRegexes` user-settings block.
   - `developer-guide.md` §1: one paragraph naming both hooks and when they speak.
   - `AGENTS.md`: one paragraph in "The plugin's scripts and hooks", `RECENT_TASKS` in the `task-clock.sh` row, and the version bump 2.31.0 → 2.32.0.
   - Add Test 13.
   - Run `bash scripts/test-plugin-scripts.sh` and `bash scripts/validate-plugin.sh --strict` green.
   - Then the manual check in a real 2.1.292 session: open on `feat/DE-123_x` → `/resume` lists `DE-123 x`; type `/dev-setup:sdd DE-123` on `next` → title set; a permission prompt with a clock open → a desktop notification `dev-setup · DE-123`. Record the result in the merge request.

## Test strategy

All automated tests live in `scripts/test-plugin-scripts.sh` and run against `templates/dev-setup/.claude/hooks/` (`$PLUGIN_HOOKS`), `templates/dev-setup/.claude/scripts/`, and the generated `$HOOKS_JSON`, in a fixture repository under `$WORK_DIR` like section 12's. External programs are stubbed: a `$WORK_DIR/notify-bin/` holds `uname` (prints `$STUB_OS`), `osascript` and `notify-send`, which append their argv to `$WORK_DIR/notify-calls`, and is prepended to `PATH`. The fail-open tests run with a `PATH` made of a directory of symlinks to `bash`, `git`, `sed`, `grep`, `cat`, `dirname`, `head`, `tr` and the `uname` stub, without `jq`. An aged stop is made by appending `stop\t<now-600>\t…` to the task's log by hand.

- Section 11 (REQ-14): `RECENT_TASKS`.
  - A task started then stopped seconds ago is in `RECENT_TASKS`, and not in `OPEN_TASKS`.
  - An open task is not in it; a task whose last stop is 600 s old is not in it.
  - `--status` leaves every log byte-identical.
- Test 1 (REQ-1): the notification fires.
  - Fixture on `feat/DE-900_thing` with DE-900's clock started, `STUB_OS=Linux`, payload `{hook_event_name: "Notification", notification_type: "permission_prompt", message: "Claude needs your permission to use Bash", cwd}` → `notify-calls` holds exactly one `notify-send` line whose title is `dev-setup · DE-900` and whose body is the message.
  - Same payload with `STUB_OS=Darwin` → one `osascript` call whose argv carries the title and the body as separate arguments.
  - A message containing `"` and `'` arrives verbatim in argv.
- Test 2 (REQ-2): it stays quiet.
  - On `chore/no-task` with no clock open → `notify-calls` empty, stdout empty, exit 0.
  - On `feat/DE-900_thing` with no clock → no call.
  - On `feat/DE-900_thing` with DE-900 open, `notification_type` `idle_prompt`, `auth_success`, `agent_needs_input` and `agent_completed` → no call.
- Test 3 (REQ-3): it fails open.
  - Without `jq` on `PATH` → exit 0, stdout empty.
  - `STUB_OS=Plan9` → exit 0, no call.
  - `cwd` set to a non-repository directory → exit 0, no call.
  - With DE-900 open, a `notify-send` stub that exits 1 → the hook still exits 0.
- Test 4 (REQ-4): a replay of the launcher's order, on a fixture checked out on `next`.
  - `--task DE-901 --start`, then a `permission_prompt` → exactly one call, titled exactly `dev-setup · DE-901` (the `ready-for-mr` prompt).
  - DE-902 also started → the title is exactly `dev-setup · DE-901 DE-902`, and both clocks still report `RUNNING: true`.
  - Checked out on `feat/DE-901_thing` with both still open → exactly `dev-setup · DE-901` (the branch narrows; a resolver that ignores the branch or takes a union fails here).
  - Back on `next`, stop DE-901 and DE-902, then a `permission_prompt` → one call titled `dev-setup · DE-901 DE-902` (the `failed` prompt, after `--stop`).
  - With those stop lines 600 s old → no call, empty stdout, exit 0.
  - In `run-outcomes.md`, the line `Then invoke \`vcs-ops\`` comes before the line holding `--task <taskId> --stop` under `ready-for-mr`, and under `failed` step 3 the stop comes before the `BLOCKED` move. Reordering either would quietly change which half the clocks name.
- Test 5 (REQ-5): the title comes from the branch.
  - `SessionStart`, `source: "startup"`, on `feat/DE-123_add-user-auth` → stdout is one JSON object with `hookEventName` `SessionStart` and `sessionTitle` `DE-123 add-user-auth`.
  - `source: "resume"` → the same.
  - On `feat(auth)/DE-123_add-user-auth` → `DE-123 add-user-auth`.
  - On `feat/DE-124-add-x` → `DE-124 add-x`.
- Test 6 (REQ-6): a title the developer chose is kept.
  - `session_title: "my refactor"` → stdout empty.
  - `session_title: "DE-99 old-thing"` → replaced with `DE-123 add-user-auth`.
  - `session_title: "DE-123 add-user-auth"` → stdout empty.
- Test 7 (REQ-7): the launch prompt sets the title.
  - On `next` with a local branch `feat/DE-125_fix-login`, `UserPromptSubmit` with `prompt: "/dev-setup:sdd DE-125"` → `sessionTitle` `DE-125 fix-login`, `hookEventName` `UserPromptSubmit`.
  - `prompt: "/dev-setup:quick DE-126"` with no such branch → `DE-126`.
  - `prompt: "/dev-setup:multi-sdd DE-1 DE-2"`, `"explain DE-125"` and `"/dev-setup:sdd"` → stdout empty.
  - `prompt: "/dev-setup:sdd DE-125"` with `session_title: "my refactor"` → stdout empty; with `session_title: "DE-125 fix-login"` → stdout empty.
- Test 8 (REQ-8): it is silent off a task branch and fails open.
  - `SessionStart` on `chore/no-task` → stdout empty, exit 0.
  - Without `jq` → exit 0, stdout empty.
  - Non-repository `cwd` → exit 0, stdout empty.
- Test 9 (REQ-9): both hooks ship mounted.
  - `$HOOKS_JSON` has `.hooks.Notification[]` with matcher exactly `permission_prompt` and a command ending `/notify.sh"`.
  - `.hooks.SessionStart[]` has one entry with matcher `startup|resume` → `session-title.sh` and still one `compact` → `on-compact.sh`.
  - `.hooks.UserPromptSubmit[]` → `session-title.sh`.
  - Both scripts exist under `dist/dev-setup/hooks/scripts/`, and `manifest.json`'s `hooks` lists both.
- Test 10 (REQ-10): the phase list is in intake.
  - `intake.md` names the task-list tools (`TaskCreate`, `TodoWrite`) and the phase names Intake, Discovery, Spec, Approval, Development, Gates.
  - It states the stop-point mapping: `review` lists nothing past Gates, `commit` → `Commit`, `push` → `Commit and push`, `merge-request` → `Commit and merge request`.
  - It states the completed-on-resume rule and the one-line commentary rule.
  - `validate-plugin.sh --strict` stays at 0 findings, so the word budgets hold.
- Test 11 (REQ-11): every closing report ends on `Next:`.
  - In `stop-point.md` the last line of the "Ending at a stop point" block starts with `Next: /dev-setup:sdd`, and `Resume:` no longer appears in that block.
  - `shared/skills/vcs-ops/reference/github.md` holds the row `gh pr checks <n> --watch`, and `gitlab.md` the row `glab ci status --live --branch '<BRANCH>'`.
  - `closure.md`, `quick/SKILL.md` and `run-outcomes.md` each contain a `Next:` instruction pointing at the host reference, and none contains `gh pr checks` or `glab ci`.
  - `closure.md`'s declined case contains `Next: /dev-setup:sdd`; `quick/SKILL.md` and `run-outcomes.md` state the declined `Next:` as the host reference's open command.
  - `run-outcomes.md` contains the four `failed` `Next:` forms.
  - `quick/SKILL.md` is at most 500 words.
- Test 12 (REQ-12): the brief routes to `quick` without switching.
  - `intake.md`'s brief template contains `Route: looks like quick — /dev-setup:quick`.
  - The text states that the flow continues in `sdd`.
- Test 13 (REQ-13): the docs say it, and the gates still pass.
  - `docs/onboarding.md` contains `preferredNotifChannel`, `terminal_bell` and `footerLinksRegexes`, plus a sentence saying it is not project `.claude/settings.json`.
  - `docs/developer-guide.md` contains `notify.sh` and `session-title.sh`; `AGENTS.md` contains `RECENT_TASKS`.
  - The existing onboarding cap (≤120 lines) and the checks 14–15 assertions stay green.
  - The existing "no hook exits 2" grep covers both new scripts.

## Notes

- **Not verifiable in CI, verified by hand in plan step 5:**
  - that the client honours `sessionTitle` from a plugin hook on `resume` (the task's own "Da confermare");
  - that `UserPromptSubmit` receives a typed slash command as its `prompt`.

  If `resume` is not honoured, a session titled once keeps its title anyway, and the `UserPromptSubmit` path still titles a new one.
- **Two notifications at once.** In iTerm2, Ghostty and Kitty, Claude Code's built-in notification also fires on a permission prompt, so a task session gets two: the built-in one without the task and the hook's with it. The hook can't suppress the built-in one.
- **A fan-out names the set, not the run.** In a `multi-sdd` fan-out the launcher's checkout narrows nothing, so a prompt is titled with every open or just-stopped task: the run asking is among them, but the hook cannot tell which one.
- **A clock left open is a task in progress.** A clock left open by an early stop point names that task in every permission notification in this repository until the task reaches its merge request. That is accurate, and it is the same signal `post-merge-request.sh` reads. A just-stopped clock does the same for five minutes, on whatever prompt comes next.
- **No title for a fan-out.** A `multi-sdd` session gets no title on purpose: it is not one task, and five ids do not make a name.
- **Worth doing, not in this task:**
  - the mod band could show the current `sdd` phase from the same task list;
  - the `failed` `Next:` for stage `dev` could become a resume command once a workflow resume survives the session.
