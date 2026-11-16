# Spec mode — where the answers land

When the subject of the grilling is a spec — `grill-me` on the branch's draft,
or `sdd-plan` before the approval — the answers do not stay in the
conversation. After each round, before the next one:

- every settled decision goes into the section of the spec it changes —
  requirement, technical decision, plan step, test case — and a reference you
  add follows `${CLAUDE_PLUGIN_ROOT}/reference/readable-references.md`;
- every non-obvious one also goes into `## Decision log`, in the spec's own
  format, with today's date (`date +%F`), the reason and the alternative
  discarded;
- an answer of "I don't know" becomes an open question in `## Notes`.

The tree grows from the spec's requirements, technical decisions, plan and
`## Notes`, and from what the conversation already settled (the Discovery
Summary). Do not ask again what the spec already states, and do not grill
again what this conversation already grilled.

Nothing is committed here. A grilled spec is still a `draft`: only the
approval in `sdd-plan` changes its status.
