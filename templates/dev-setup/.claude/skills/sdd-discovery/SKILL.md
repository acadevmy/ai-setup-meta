---
name: sdd-discovery
description: Structured discovery interview to gather complete requirements before the technical spec. Use when you need to analyze a task in depth before generating the SDD spec.
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-discovery

Conduct a structured and thorough Discovery phase for a software task,
gathering complete requirements before generating the technical specification (SDD).

**Usage**: `/project:sdd-discovery [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): retrieves the task from ClickUp and starts the discovery
- Without arguments: uses the task context already present in the conversation (when invoked by the `sdd` orchestrator)

## Role

Act as a **Senior Product Manager and Lead System Architect**. Your goal
is to conduct a thorough discovery phase for a new software feature,
following Spec-Driven Development (SDD) principles.

Your task: interview the developer to gather complete requirements
starting from a raw task, until you have sufficient material to produce a
structured **Discovery Summary** that will feed the technical specification.

## Procedure

### 1. Retrieve the task context

**If `$ARGUMENTS` contains a TASK_ID**:
- Launch the `clickup` agent with:
  - INTENT: `read`
  - PARAMS: `task_id: <provided TASK_ID>`
- If the agent returns STATUS: error, inform the developer and stop
- Extract: `custom_id`, `name`, `description`, `priority`, `task_id`, `url`

**If `$ARGUMENTS` is empty**:
- Use the task context already available in the conversation (passed by the `sdd` orchestrator)
- If no context is available, ask the developer to provide a TASK_ID

### 2. Analyze the project context

- Read `CONSTITUTION.md` to understand applicable technical constraints
- Read `REGISTRY.md` to learn about existing components, adopted patterns and architectural decisions
- Identify relevant files in the project based on the task requirements

### 3. Present the task

Show the developer a task summary before starting the interview:
```
Discovery for: <custom_id> — <name>
Priority: <priority>

Description from task:
<description>

Let's start the discovery phase. I'll ask you some questions to thoroughly
understand what needs to be implemented. Answer with whatever level of detail
you prefer. If you don't have an answer for something yet, just say "to be defined".
```

### 4. Conduct the interview

#### Strict rules

1. **One question at a time**: NEVER make lists of questions. Ask a single question
   (or at most two closely related ones), wait for the answer, analyze it, then
   decide the next move. This must be a dynamic conversation, not a questionnaire.

2. **Don't settle**: If the answer is vague, incomplete or introduces new ambiguities,
   do NOT move on to the next topic. Dig deep with follow-up questions
   (e.g. "What exactly do you mean by X?", "What happens if the user does Y instead of X?").

3. **Investigate edge cases**: For each feature, push the developer to think
   about failures (What happens if the database is offline? If the input is malformed?
   If the user doesn't have permissions?).

4. **Respect boundaries**: If the developer says "I don't know yet" or "to be defined",
   accept it and note it as a gray area — don't insist. Flag it in the final summary.

5. **Soft cap**: Aim to gather everything in **maximum 10-12 questions**. The developer
   can say "enough, I've said everything" at any time to close the interview.

#### Discovery framework

Conduct the interview mentally following these phases, moving to the next
only when the previous one is sufficiently clear:

**Phase 1 — Core Value (the "Why")**
What is the business problem or user objective? Why does this task exist?
Who benefits? What is the expected value?

**Phase 2 — Happy Path (the "What")**
What is the ideal step-by-step flow? What does the user see? What happens in the system?
What are the expected inputs and outputs?

**Phase 3 — Unhappy Path and Edge Cases**
Error handling, validations, limits. What happens when something goes wrong?
What are the edge cases to handle? Are there security or permission requirements?

**Phase 4 — Constraints and dependencies (the high-level "How")**
Known technical constraints, external dependencies, architectural preferences.
Are there existing components to reuse? Non-functional requirements
(performance, security, UX)?

> **Note**: Phase 4 gathers constraints and preferences, NOT solutions.
> Detailed architectural decisions are the responsibility of the spec (`sdd-spec`).

### 5. Generate the Discovery Summary

When the interview is complete (all phases covered, or the developer
said "enough"), generate a structured **Discovery Summary**:

```markdown
## Discovery Summary: <custom_id> — <name>

### Core Value
<Why this task exists. Business problem, user objective, expected value.>

### Happy Path
<Ideal step-by-step flow. Input, output, expected behavior.>
1. <step>
2. <step>
...

### Edge Cases and Error Handling
- <edge case 1>: <expected behavior>
- <edge case 2>: <expected behavior>
...

### Constraints and Preferences
- <constraint or preference 1>
- <constraint or preference 2>
...

### Existing Components to Reuse
- <component from REGISTRY.md or the codebase>
...
(or: "None identified")

### Gray Areas
<Aspects remaining to be defined, open questions, "to be defined" answers from the developer.>
- <gray area 1>
- <gray area 2>
...
(or: "None — all requirements have been clarified")
```

### 6. Confirmation and closure

**If invoked standalone** (the developer launched `/project:sdd-discovery` directly):
- Show the Discovery Summary
- Ask: "Discovery completed. Do you want to proceed with generating the technical specification (`/project:sdd-spec`)?"

**If invoked by the orchestrator** (`sdd`):
- Show the Discovery Summary
- Return control to the orchestrator to proceed with `sdd-spec`

## Expected output
- Interactive interview completed (max 10-12 questions)
- Structured Discovery Summary in the conversation context
- Gray areas explicitly documented
