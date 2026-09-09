# The approval loop

How the spec gets from `draft` to `approved`, and what each answer means. The
turn rule for the question itself is in
`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## The question

```json
AskUserQuestion({
  "questions": [{
    "question": "How do you want to proceed with the spec?",
    "header": "Spec review",
    "options": [
      { "label": "Approve", "description": "The spec is ready, go ahead with development." },
      { "label": "Change", "description": "Say what to change in the spec." },
      { "label": "Regenerate", "description": "Rebuild the spec from scratch (this calls sdd-spec)." }
    ],
    "multiSelect": false
  }]
})
```

End the turn on the tool call. No filler, no reminders.

## Approve

- set `Status: draft` → `Status: approved` in the spec file;
- set `Approved:` to today's date (`YYYY-MM-DD`);
- confirm:

  ```
  Spec approved: .specs/<filename>
  Status: approved
  Approved: <date>
  ```

## Change

- collect the developer's feedback;
- apply the requested changes to the spec file;
- re-present the updated spec;
- ask again. The loop runs until the developer approves or gives up — this is a
  discussion, and there is no iteration cap on a human conversation.

## Regenerate

The spec has to be rebuilt from the task, not edited. Invoked by the
orchestrator, hand control back so it can re-run `sdd-spec`. Invoked on its own,
tell the developer to call `sdd-spec` with the task id.

## Anything else

The developer may want to discuss a specific decision rather than pick one of
the three. Answer the question, address the concern, suggest alternatives when
asked — then come back to the question. A spec approved without its objections
answered is an approval that will be withdrawn during development.
