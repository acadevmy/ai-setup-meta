# Hand-off between skills run on their own

The SDD sub-skills are steps of a flow. Inside `sdd` the orchestrator chains
them. Run on their own, they chain through this rule: each one ends by offering
the next step, so the chain continues from wherever it was entered and the
developer does not have to know which command comes next.

## When it applies

Only when the skill was **invoked on its own** — by the developer, or by the
model on its own judgement. Invoked by a flow (`sdd`, `quick`, `auto-sdd`,
`multi-sdd`, `auto-dev`), the flow decides what follows: do nothing here.

It applies on a result that can go forward. A `fail`, an `error` or a refused
approval is not handed off: show what has to change and end there.

## The rule

1. Show the skill's own summary, as it already does.
2. End the turn on **one** `AskUserQuestion` with two options: the next step
   (first, recommended, naming the skill and what it will do) and "stop here".
   `turn-discipline.md` governs the turn: after the call, nothing else.
3. On the next step, invoke that skill **in the same turn**, with the context
   already in the conversation — the task, the spec path, the result. Do not
   ask again for what the previous step already established.

**A command only a person starts.** `sdd` and `quick` carry
`disable-model-invocation: true`, so the model cannot invoke them. When one of
them is the next step there is no question: end with a `Next:` line and the
exact command to type — the same last line `sdd`'s stop points end on.

The question is the only checkpoint the hand-off adds. It replaces none of the
existing ones: the spec approval in `sdd-plan`, and the `ask` rules on commit,
push and merge request creation, stay where they are.

## The chain

| Ends | On | Next |
|---|---|---|
| `sdd-discovery` | the Discovery Summary | `sdd-spec` |
| `sdd-spec` | a spec in `draft` | `sdd-plan` |
| `sdd-plan` | `Status: approved` | `sdd-dev` |
| `sdd-dev` | tests and linter passing | with a task id, `Next: /dev-setup:sdd <id>` — it resumes at closure (gates, commit, merge request) from what is on disk. Without one, `verify` |
| `verify` | `pass`, or `pass-with-warnings` confirmed | `review` |
| `review` | `pass` or `pass-with-warnings` | the commit and the merge request through `vcs-ops` |

From `sdd-dev` on, a task id means the work belongs to a tracked task: the
resume through `sdd` is preferred because closure also moves the task and stops
its clock. The manual `verify` → `review` → `vcs-ops` path is for work with no
task behind it.
