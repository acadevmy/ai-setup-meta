# References a person reads

Specs, summaries, REGISTRY entries, rules, reports and merge requests exist so
a person can understand the work and steer it. They are written in natural
language, for that person — not as notation for the next agent. So every
reference in them has to be readable by someone who was not in the session
that wrote it: often a reviewer weeks later, with the repository, the tracker
and a browser, and nothing else.

This is the one place the rule is written. Every skill, agent and workflow of
the plugin that writes text a person reads follows it, and checks it before
handing the text over.

## Index

- [The three forms](#the-three-forms)
- [Ids a mechanism needs](#ids-a-mechanism-needs)
- [Never](#never)
- [What stays as it is](#what-stays-as-it-is)
- [The test](#the-test)

## The three forms

A reference is one of three things, and nothing else:

- **A document** — a Markdown link whose *text* names the topic in words a
  person understands, and whose *address* reaches the right spot: the
  relative path plus the heading anchor for a file in the repository, the
  specific page for a wiki, a tracker doc or a design file.
  `[the Terraform rule on the lock file](.claude/rules/dev-setup-terraform.md#state-is-remote-locked-and-encrypted)`
  is a reference; `see dev-setup-terraform.md` makes the reader open the file
  to learn what it is about. When the address cannot reach the spot, the text
  says where: `[product brief, section "Personas"](https://…)`.
- **A rule** — cited by its name: the rule file and the heading that states it
  (`dev-setup-typescript.md → Zod is the boundary`), or a sentence that names
  it ("the TypeScript rule that Zod is the boundary"), linked to its heading
  wherever the text renders as Markdown. A section number may appear only
  next to the title it numbers, never alone.
- **A topic with no address** — plain words, when the source has nothing the
  reader can open: "as the developer decided in the discovery", "the export
  screen of the mockup".

## Ids a mechanism needs

Some ids carry a contract: `REQ-N` is how the verification maps a requirement
to its test, the task id is in the branch name and the merge request title, an
ADR has its number, a spec its file name. Keep them where the mechanism reads
them. Wherever a person reads one, it comes with what it names, the first time
in a block:

- `REQ-3 (an expired token is refused)`, then "REQ-3" or "the expired-token
  requirement";
- `[DE-123 Export materials to SCORM](https://…)` — the task's id *and* title
  as the link text, never `[DE-123](…)` alone;
- `[ADR 0007 — server state lives in TanStack Query](docs/adr/0007-server-state.md)`;
- `[the spec for DE-123, Export materials to SCORM](.specs/DE-123-export-scorm.md)`.

## Never

- a section number without its title: `§49`, `CONSTITUTION §49`, `sec. 9`,
  "see 3.2";
- an abbreviation coined while working: `SPEC`, `INV`, `the R14 fix`;
- a bare id where a person reads it: `REQ-4` alone in a report, `DE-123` alone
  as link text, "per ADR-12";
- a bare path or URL used as a pointer — "see `docs/api.md`",
  `https://…/spec.md#export` — instead of a link that says what it points at;
- a file the reader cannot open: a scratch file, something under `/tmp`, a
  digest you made for yourself. Cite the source it derives from;
- "as above", "the previous point", "option B" once the list it numbered is
  out of sight.

## What stays as it is

A path that *is* the subject is not a reference: the files a spec's Impact
lists, the `file:line` of a review finding, the command a test step runs. A
format a parser or a script reads keeps its shape — the review's
`[<rule file> → <heading>]`, the `REQ-<N>` ids the verification maps, a
frontmatter key, a branch name. The rule applies to the words a person reads
around them: add the title next to the id, never change the id.

## The test

Before you hand the text over, read every reference in it once more and ask
two questions. With only the repository, the tracker and a browser, can the
reader tell what the reference is about **before** opening it? Opening it, do
they land on **the spot** that was meant? A no to either is a rewrite.
