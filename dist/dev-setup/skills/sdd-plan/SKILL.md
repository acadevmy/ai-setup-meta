---
name: sdd-plan
description: Presents the technical spec to the developer for discussion, iteration and approval
model: sonnet
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-plan

Present a technical specification to the developer for review, discussion and approval.
The developer can comment, request changes or approve the spec.

## CRITICAL — Turn behavior

This skill requires developer input. After asking a question or presenting choices,
your message ENDS — produce ZERO additional tokens. Do NOT add wait messages,
status updates, or rephrase the question. If the Stop hook fires reporting
incomplete work, respond with `{"ok": true}` — waiting for the developer IS the
correct state.

**Usage**: `/project:sdd-plan [SPEC_REF]`
- With path (e.g. `.specs/DE-123-add-auth.md`): opens that spec
- With customId (e.g. `DE-123`): searches for the corresponding spec in `.specs/`
- Without arguments: lists available specs and asks which one to open

## Procedure

### 1. Locate the spec

**If `$ARGUMENTS` contains a path**:
- Read the file at the indicated path
- If the file does not exist, inform the developer and stop

**If `$ARGUMENTS` contains a customId**:
- Search in `.specs/` for a file starting with the customId (e.g. `DE-123-*.md`)
- If found, read the file
- If not found, inform the developer and stop

**If `$ARGUMENTS` is empty**:
- List all `.md` files in `.specs/`
- If there are no specs, inform the developer and stop
- If there is only one, open it directly
- If there are multiple, present them as a numbered list and ask which one to open

### 2. Present the spec

Show the complete spec to the developer with clear formatting.
Highlight the current status (draft/approved/implemented).

### 3. Discussion and iteration

Ask the developer how they want to proceed using the `AskUserQuestion` tool with these options:
- Approve — the spec is ready, proceed with development
- Modify — indicate what to change
- Regenerate — regenerate the spec from scratch (will invoke sdd-spec)

**STOP after asking**: after presenting the question, end your turn immediately.
Do NOT add filler text, reminders, or repeat the question. Your turn is OVER.

**If the developer chooses "Approve"**:
- Update the spec file: change `Status: draft` to `Status: approved`
- Update the `Approved:` field with today's date (YYYY-MM-DD format)
- Confirm the approval:
  ```
  Spec approved: .specs/<filename>
  Status: approved
  Approved: <date>
  ```

**If the developer chooses "Modify"**:
- Gather the developer's feedback
- Apply the requested changes to the spec file
- Re-present the updated spec
- Return to step 3 (discussion loop)

**If the developer chooses "Regenerate"**:
- Inform the developer to invoke `/project:sdd-spec` with the task ID to regenerate
- If invoked by the orchestrator, the orchestrator will handle the regeneration

**If the developer wants to discuss specific aspects**:
- Answer questions and address concerns
- Suggest alternatives when requested
- After the discussion, return to step 3

### 4. Final confirmation

At the end, confirm the spec status and file path:
```
Spec: .specs/<filename>
Status: <updated status>
```

## Expected output
- Spec presented and discussed with the developer
- Spec file updated with agreed changes
- Status updated to `approved` (if approved) with approval date
