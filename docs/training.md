# Team session — rules that are enforced, not read

Facilitator material for a 45-minute session introducing dev-setup v3 to a team
that used v2. Three live demos carry it; the rest is framing. Everything here is
runnable on a throwaway branch of a real project.

**What people should leave with**: one sentence, and the reflex that goes with
it.

> A rule is a mechanism or it is not a rule.

## Index

- [Why this session exists](#why-this-session-exists)
- [The mental model, in one slide](#the-mental-model-in-one-slide)
- [Demo 1 — the gate on the commit](#demo-1--the-gate-on-the-commit)
- [Demo 2 — the ask on the merge request](#demo-2--the-ask-on-the-merge-request)
- [Demo 3 — the rules that load themselves](#demo-3--the-rules-that-load-themselves)
- [What this changes in your day](#what-this-changes-in-your-day)
- [Objections you will get](#objections-you-will-get)
- [Agenda](#agenda)
- [Before the session](#before-the-session)

---

## Why this session exists

v2 was a governance written in prose. Roughly 13,000 words of skills and a
621-line constitution described gates — verify, review, approval — that **no
mechanism enforced**. The model declared itself compliant and nobody checked.

That is not a criticism of anyone's writing. It is a structural fact about
prose: a paragraph is a request, and a request is only as good as whatever reads
it next. Compaction drops it. A long session forgets it. A charitable reading
turns "max 3 iterations" into four.

v3 keeps the same intentions and moves them into things that cannot be
reinterpreted: a hook that exits non-zero, an OS-level sandbox, a permission
rule that stops and asks, a script that returns exit 3, a rule file the harness
injects on a path match.

The visible consequence, and the one to lead with: **you will now be interrupted
by things that used to pass silently.** That is the feature. The session exists
so those interruptions read as design rather than as bugs.

---

## The mental model, in one slide

```
        v2                                     v3
        ──                                     ──

  "always run the tests"      →   PreToolUse hook runs them and
  in a skill body                 denies the commit with the output

  "ask before opening          →  an `ask` permission rule on
   the MR"                        `gh pr create` — the real command

  621-line constitution        →  .claude/rules/*.md with `paths:`;
  read in full, every session     the harness injects the ones that
                                  match the file you just opened

  "never read .env"            →  OS-level sandbox deny; the shell
  in a deny list a `sed`          cannot go around it either
  walked around

  "max 3 iterations"           →  `objections.length >= 2` in a
  in a prose orchestrator         workflow script the model never reads
```

Three questions decide where a rule belongs, and they are worth putting on the
wall:

1. **Can a machine check it?** Then it is ESLint, the test runner, or branch
   protection — not a document. A lint error arrives at the moment of the
   mistake.
2. **Is it unsafe to discover late?** Secrets, untrusted content, supply chain.
   Then it loads unconditionally, and it is capped at 150 lines because everyone
   pays for it on every session.
3. **Otherwise** it arrives with the file it applies to.

---

## Demo 1 — the gate on the commit

*The point: the gate runs the real command and shows the real output.*

On a throwaway branch, break something on purpose — a stray `const x: any = 1`
in a strict project, or a test with the assertion flipped. Then ask Claude to
commit.

**What people see.** The commit does not happen. The refusal carries the tail of
the actual lint or test output — not "the checks failed", the failure itself.

**Say out loud:**

- The hook is `PreToolUse` on `Bash`. It is not the model deciding to be
  careful; the model does not get to run the command.
- It is **adaptive**. If the project has husky or lefthook, your own tooling
  already runs the per-commit checks, so the hook drops to refusing the ways
  around them — `HUSKY=0`, a `core.hooksPath` override. Checks run once, not
  twice.
- `--no-verify` is denied separately, at the permission layer. There is no
  polite way to skip this.
- It is **fail-open**: no `jq`, no gate, and it warns on stderr. That is
  deliberate — it is a quality gate, not a security boundary, and blocking every
  commit on a broken toolchain would be worse than reporting it.

**The question someone will ask**: "does it run the whole suite every time?" No.
The full suite belongs at the merge-request boundary and in CI, which stays the
final word.

---

## Demo 2 — the ask on the merge request

*The point: the checkpoint moved from a summary to the command itself.*

Take the branch to the point of opening a merge request — `/dev-setup:quick` on
a one-line change is the fastest way to get there live.

**What people see.** A permission prompt naming the actual
`gh pr create` / `glab mr create` invocation, with its arguments.

**Say out loud:**

- v2 ended with "shall I open the PR?" in chat — a summary written by the same
  model that was about to run the command. v3 shows you the command.
- The same rule covers mutating `gh api` / `glab api` calls and every ClickUp
  write. The pattern is uniform: **reads are free, outward-facing writes ask.**
- This is why `sdd` lost its final OK. It was not deleted — it was moved
  somewhere it cannot be paraphrased.
- Declining is a normal outcome. The branch and the commit stay exactly where
  they are.

**Worth showing next to it**, if you have a minute: try
`git push --force` and let people watch it be denied outright. Not asked —
denied. Then `git push origin main`. Same.

---

## Demo 3 — the rules that load themselves

*The point: nobody reads the governance; it arrives.*

Start a fresh session. Ask something unrelated to code — "what does this repo
do?" Then open a `.tsx` file (or a `.dart`, whatever the project has) and ask
for a small change.

**What people see.** The rule for that file type is in context for the second
question and was not for the first.

**Say out loud:**

- The match is on the `paths:` glob in the rule's frontmatter. It is
  deterministic, it costs nothing on a session that never opens those files, and
  it survives compaction — which a 621-line document pasted at session start
  does not.
- `dev-setup-core.md` is the only file with no `paths:`. Everyone pays for it on
  every session, which is why it is capped and why it holds only what is unsafe
  to discover late.
- Only the rules your stack needs exist at all. Show `ls .claude/rules/` on two
  different projects side by side if you have them.
- **The `dev-setup-` prefix is the contract.** Files with it are generated and
  get overwritten on an update. Files without it are yours and are never
  touched. Adding a team rule is creating `.claude/rules/<name>.md` with a
  `paths:` frontmatter — show one being written, it takes 30 seconds.

---

## What this changes in your day

| Before | Now |
|---|---|
| 11 commands, unclear which | 6: `setup`, `quick`, `sdd`, `auto-sdd`, `multi-sdd`, `review` |
| Choose TDD or BDD when asked | Never asked — the layer decides, the rule states it |
| Approve the spec, then approve again per step, then approve the PR in chat | One approval: the spec. The merge request asks at the command |
| Four commits per task, three of them bookkeeping | One |
| A vague "the agent reviewed it" | An adversarial verifier that has to *refute*, and a real test output pasted into the merge request |
| Two parallel tasks meant two clones and a port collision | `claude --worktree DE-123`, and up to five unsupervised runs from one chat |

The routing decision is the one thing that stays entirely yours: at most three
files and no new component, dependency or public interface → `quick`; anything
else → `sdd`. Claude may say a task looks misrouted. The command you type is the
decision.

---

## Objections you will get

**"It is going to interrupt me constantly."** Three interruption classes, and
they are bounded: the commit gate (only when something is actually red), the
merge request (once per task), and a network host outside the allowlist (once
ever — "don't ask again" records it). Everything else is denied silently or
allowed silently.

**"The sandbox will break my dev server."** It can, and there is a documented
fix: if the project's own command loads a file the sandbox denies, remove that
filename from `sandbox.filesystem.denyRead`. Say this before someone discovers
it at 6pm.

**"I liked reading the constitution — now I do not know the rules."** The rules
are still readable, in `.claude/rules/`, and they are shorter because everything
a machine can check moved into the machine. What you have lost is the obligation
to remember them.

**"Can I still just work normally with git?"** Yes. None of this is a git
wrapper. The deny rules cover force push, pushes straight to the reference
branches, and `--no-verify` — three things nobody should be doing on a shared
branch anyway.

**"What if the autonomous run gets it wrong?"** It stops itself: two of three
adversarial lenses refusing the spec halts the run before any code is written.
When you overrule a lens, the overrule is recorded in the outcome and quoted in
the merge request, so the reviewer sees it. That is one more checkpoint than v2
had, not one fewer.

---

## Agenda

| Time | Item |
|---|---|
| 0:00 | Why: prose describes, mechanisms enforce. The one sentence |
| 0:05 | The mental model slide, and the three questions |
| 0:10 | Demo 1 — the gate on the commit |
| 0:18 | Demo 2 — the ask on the merge request, plus the force-push deny |
| 0:26 | Demo 3 — the rules that load themselves, plus writing a team rule live |
| 0:34 | What changes in your day: the six commands, the routing bar |
| 0:40 | Objections, questions |
| 0:45 | Where to read: onboarding, the guide, the migration page |

---

## Before the session

- A throwaway branch on a real project the team recognises, already configured
  with `/dev-setup:setup`.
- The project's own lint and tests actually passing on that branch, so demo 1's
  failure is the one you introduced.
- A ClickUp task id you do not mind moving, for demo 2.
- Two terminals open, if you want to show worktrees.
- Send [onboarding.md](./onboarding.md) round beforehand and
  [developer-guide.md](./developer-guide.md) afterwards. People migrating an
  existing project need [migration-v2-to-v3.md](./migration-v2-to-v3.md) in
  front of them when they run the UPDATE.
