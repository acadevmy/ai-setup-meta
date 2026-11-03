# The distill document

Sections with nothing to say are left out, except **Decisions taken**, which
states when there is no source.

```markdown
# <what the work does — not the branch name>

`<branch>` → `<base>` · <n> commits · <short sha> · <date>
<when HEAD is not on the remote: "Permalinks are not live yet: the branch is not pushed.">

## In short

<3–5 plain lines: what the system does now that it did not before, and why. No file names.>

## Map of the change

| Area | What changes |
|---|---|
| <e.g. Checkout (frontend)> | <one line> |

<A Mermaid diagram only when a flow really changes — a new step, a different
order, a new system involved. Draw the flow after the change and mark the new
part.>

## Highlights

### High risk

**<short title>**
- **What**: <what changed>
- **Why it matters**: <what breaks, for whom, if it goes wrong>
- **Where**: [<file>:<lines>](<permalink>)
- **How to check**: <a concrete action>

### Medium risk

### Low risk

## Decisions taken

- **<decision>**: <reason>. _Source: <spec / conversation / commit abc1234 / MR>_

<or: "No decision log found: the non-obvious choices are for whoever did the work to explain.">

## Reviewer checklist

- [ ] <what to try by hand, with concrete data and steps>

## Left out

<One line: e.g. "pnpm-lock.yaml, 14 formatting-only files, generated code in dist/".>
```

## Assigning risk

- **High**: can lose or corrupt data, touches money or payments, opens a
  security or auth hole, breaks a contract others use (API, DTO, events), runs
  a migration that cannot be reversed — or reaches production with no quick way
  back.
- **Medium**: changes behaviour a user sees or a business rule, or changes
  configuration or infrastructure that can be reverted.
- **Low**: local, reversible, and exercised by tests that really reach it.

A point goes up one level when no test reaches it, and the document says so.
Something that looks wrong while reading is not kept quiet: it goes under high
risk, marked "to verify", with the reason in one line.

## Citing code

Permalinks to the commit, so they survive later commits. The web URL comes from
`git remote get-url origin` (SSH → https, no `.git`), the sha from
`git rev-parse HEAD`:

- GitHub: `<web url>/blob/<sha>/<file>#L<from>-L<to>`
- GitLab: `<web url>/-/blob/<sha>/<file>#L<from>-<to>`

When `git branch -r --contains HEAD` is empty the links do not resolve yet:
write `file:line` and the note in the header.

## Proportion

Plain sentences, domain terms explained the first time. A ten-line fix fits in
half a page. No praise, no style remarks.
