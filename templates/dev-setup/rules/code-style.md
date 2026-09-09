---
paths:
  - "**/*.{ts,tsx,mts,cts,js,jsx,mjs,cjs}"
  - "**/*.{py,go,rs,rb,php,java,kt,swift,cs,scala}"
  - "**/*.{dart,vue,svelte,astro}"
  - "**/*.{tf,tfvars,sql,sh,bash,zsh}"
---

# Writing and changing code

Language-independent. The language's own rule file sits alongside this one and
carries what only applies there.

Anything the toolchain can check — function length, naming, `any`, coverage —
is configured in the linter and the test runner, not repeated here. When one of
them fails, the fix is the code, not a disable comment.

## Design

- A function does one thing, and does not quietly mutate state the caller did not
  hand it. When the linter's `max-lines-per-function` fires, the function is
  doing several — decompose it, do not raise the limit.
- Write the smallest thing that solves the stated problem. No configuration
  options, feature flags or extension points nobody asked for; no guards for
  states the surrounding code cannot produce. Validate at the boundary instead.
- Wait for the second concrete use before extracting a helper, an interface or a
  generic. One caller is not a pattern.
- Duplicated logic is a bug in waiting: extract it when it is genuinely the same
  behaviour, leave it alone when it merely looks alike.
- Constants carry names. `MAX_RETRY_ATTEMPTS`, not `3` at the call site.
- Names are descriptive and in English, and abbreviations are only the universal
  ones — `id`, `url`, `db`. Not `usr`, `btn`, `mgr`.

## Editing someone else's file

- Every changed line traces back to what was asked. Adjacent code, comments and
  formatting stay as they are even when you would have written them differently.
- Boy Scout Rule, scoped: inside a file you are already editing, fix trivial
  decay you run into — an unused import, a typo in a comment, a dead local. Do
  not rename symbols, restyle unrelated sections or refactor neighbours as a side
  effect. A larger cleanup is its own change.
- If your edit orphans something (an import, a variable, a helper), remove that.
  Pre-existing dead code gets mentioned, not deleted.

## Errors

- An empty `catch` is never acceptable. Every error is logged with enough context
  to find it, then handled — fallback, retry, or propagation as a typed error.
- Failures cross layer boundaries as domain-typed errors, not as whatever the
  driver, the HTTP client or the ORM happened to throw.

## Input that came from outside

Every external datum — request body, form input, environment variable, third
party response — is validated at the boundary before it is used, with the
stack's schema validator. Downstream code can then assume it is well formed.

Validated is not the same as safe to interpolate. A value that reaches a query,
a shell command, a file path or a template goes through the mechanism that
escapes it — a parameterised query, an argument array, a path join — never
string concatenation, however well the value parsed.
