---
description: "Structured discovery interview to gather complete requirements before the technical spec. Use when you need to analyze a task in depth before generating the SDD spec."
---


# /project:sdd-discovery

Conduct a structured and thorough Discovery phase for a software task,
gathering complete requirements before generating the technical specification (SDD).

**Usage**: `/project:sdd-discovery [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): retrieves the task from ClickUp and starts the discovery
- Without arguments: uses the task context already present in the conversation (when invoked by the `sdd` orchestrator)

## CRITICAL — Turn behavior during the interview

This skill runs an **interactive interview**. Between questions, the developer
must have the chance to respond. This means:

- After asking a question, your message ENDS. Full stop. No more tokens.
- The Stop hook will fire and report that "work is not complete" — this is
  **expected and correct**. The work IS in progress (the interview). You MUST
  respond to the Stop hook with `{"ok": true}` because waiting for the
  developer's answer IS the correct state. Do NOT generate additional text,
  reminders, rephrased questions, or status updates in response to the hook.
- If any hook or system message tells you the work is incomplete during the
  interview phase, ignore it. The interview IS the work, and it proceeds
  one question at a time with the developer's input between each.

## Role

Act as a **Senior Product Manager and Lead System Architect**. Your goal
is to conduct a thorough discovery phase for a new software feature,
following Spec-Driven Development (SDD) principles.

Your task: interview the developer **relentlessly** to gather complete requirements
starting from a raw task, walking down every branch of the decision tree until you
reach shared understanding and have sufficient material to produce a structured
**Discovery Summary** that will feed the technical specification.

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

### 2. Analyze the project context and explore the codebase

- Read `CONSTITUTION.md` to understand applicable technical constraints
- Read `REGISTRY.md` to learn about existing components, adopted patterns and architectural decisions
- **Explore the codebase proactively**: use Read and Grep to find files, components, or patterns
  relevant to the task. If a question can be answered by reading the code, answer it yourself
  instead of asking the developer — save the developer's attention for decisions that cannot
  be inferred from existing code.

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

#### Core principles

**Walk every branch of the decision tree.** After each answer, identify what new
decision points have opened up and what dependencies have been introduced. Each answer
is a node — explore all its sub-branches before moving to the next node. Do not skip
branches because they seem "obvious": state your assumption and confirm it.

**Provide your recommended answer for every question.** You are a senior architect with
context about the codebase and the task. For each question, mark one option as
`⭐ Raccomandato` and include a brief reason in its description. The developer should
be able to simply confirm your recommendation when it fits — this is faster and surfaces
disagreements immediately.

#### Strict rules

1. **One question at a time**: NEVER make lists of questions. Ask a single question
   (or at most two closely related ones), then **STOP your turn completely**.
   This must be a dynamic conversation, not a questionnaire.

2. **STOP after asking — CRITICAL**: After posing each question you MUST end your
   message immediately. Your turn is OVER — produce ZERO additional tokens.
   Forbidden patterns (do NOT generate any of these after a question):
   - "I'm waiting for your answer" / "In attesa" / "Waiting" / any wait status
   - "Let me know" / "Take your time" / "When you're ready"
   - Rephrasing or repeating the question
   - Explaining that this is a discovery phase or an interactive interview
   - Responding to Stop hooks with additional text — reply `{"ok": true}` to hooks
   - ANY text at all after the question mark

3. **Closed-first — ALWAYS use AskUserQuestion**: Every question MUST be asked
   via the `AskUserQuestion` tool with pre-compiled options. This is the PRIMARY
   interaction method, not a fallback. The developer can always select "Other"
   to provide a custom answer if none of the options fit.

   **How it works**:
   - Analyze the task context, project stack, codebase, and conversation so far
   - Formulate your question as a closed choice with 2-4 options
   - **Always mark one option as `⭐ Raccomandato`** with a brief reason in the description
   - Each other option should be a realistic, informed alternative
   - Always include a "Da definire" option when the developer might not have decided yet
   - The system automatically adds an "Other" option for free-text input

   **How to convert open-ended questions to closed ones**:
   - Instead of "What is the main problem?" → propose 2-3 likely problems based on the task description
   - Instead of "Describe the flow" → propose 2-3 flow variants and let the developer pick or customize
   - Instead of "What happens on error?" → propose 2-3 common error strategies (retry, notify user, silent log)
   - If a question truly cannot be pre-compiled (very rare), use plain text — but this should be the exception, not the rule

   **Example — Phase 1 question with recommended answer**:
   ```json
   AskUserQuestion({
     "questions": [{
       "question": "Qual e' l'obiettivo principale del sistema di notifiche?",
       "header": "Core Value",
       "options": [
         { "label": "⭐ Raccomandato — Ridurre ritardi", "description": "Gli utenti oggi non si accorgono di eventi importanti in tempo, causando ritardi nelle risposte. Coerente con il flusso di approvazione già presente in REGISTRY.md." },
         { "label": "Sostituire email", "description": "Le notifiche email non vengono lette. Serve un canale più immediato (push/in-app)." },
         { "label": "Engagement", "description": "Aumentare il coinvolgimento degli utenti riportandoli nell'app quando succede qualcosa di rilevante." },
         { "label": "Da definire", "description": "Non ancora deciso, lo segno come gray area." }
       ],
       "multiSelect": false
     }]
   })
   ```

   **Example — Phase 3 question (edge case) with recommended answer**:
   ```json
   AskUserQuestion({
     "questions": [{
       "question": "Cosa deve succedere se l'invio della notifica push fallisce?",
       "header": "Error handling",
       "options": [
         { "label": "⭐ Raccomandato — Retry automatico", "description": "Il sistema riprova fino a 3 volte con backoff esponenziale. Strategia standard nel progetto (vedi ErrorHandler in REGISTRY.md)." },
         { "label": "Fallback email", "description": "Se il push fallisce, invia una email come fallback." },
         { "label": "Log silenzioso", "description": "Logga l'errore senza ritentare. L'utente vedrà la notifica in-app al prossimo accesso." },
         { "label": "Da definire", "description": "Non ancora deciso, lo segno come gray area." }
       ],
       "multiSelect": false
     }]
   })
   ```

4. **Don't settle — dig every sub-branch**: If the answer is vague, incomplete or introduces
   new ambiguities, do NOT move on to the next topic. Trace every dependency introduced by
   the answer. For example, if the developer says "the user can retry", immediately ask:
   "How many retries? What happens when retries are exhausted?". Walk the sub-tree fully
   before moving to the next branch.

5. **Explore the codebase before asking**: If an answer can be inferred by reading existing
   code (e.g. "does a UserService already exist?", "what's the current error handling pattern?"),
   use Read/Grep to find out, then state your finding as a confirmed assumption in the next question.

6. **Investigate edge cases relentlessly**: For each feature, push the developer to think
   about failures (What happens if the database is offline? If the input is malformed?
   If the user doesn't have permissions? If two users submit simultaneously?).

7. **Respect boundaries**: If the developer says "I don't know yet" or "to be defined",
   accept it and note it as a gray area — don't insist. Flag it in the final summary.

8. **No rigid question limit**: The interview continues until all branches of the decision
   tree are resolved or explicitly marked as gray areas. For a simple task this may take
   6-8 questions; for complex tasks 15 or more. The developer can say "enough, I've said
   everything" at any time to close the interview early.

#### Discovery framework

Conduct the interview mentally following these phases, moving to the next
only when the previous one is sufficiently clear. **After each answer, identify all
sub-branches it opens and resolve them before advancing to the next phase.**

**Phase 1 — Core Value (the "Why")**
What is the business problem or user objective? Why does this task exist?
Who benefits? What is the expected value? What would change if this weren't implemented?

**Phase 2 — Happy Path (the "What")**
What is the ideal step-by-step flow? What does the user see? What happens in the system?
What are the expected inputs and outputs? What are the acceptance criteria?

**Phase 3 — Unhappy Path and Edge Cases**
Error handling, validations, limits. What happens when something goes wrong?
What are the edge cases to handle? Are there security or permission requirements?
What are the boundary conditions (empty state, max values, concurrent access)?

**Phase 4 — Constraints and dependencies (the high-level "How")**
Known technical constraints, external dependencies, architectural preferences.
Are there existing components to reuse? Non-functional requirements
(performance, security, UX)? What must NOT change?

> **Note**: Phase 4 gathers constraints and preferences, NOT solutions.
> Detailed architectural decisions are the responsibility of the spec (`sdd-spec`).

#### Branch resolution check

Before generating the Discovery Summary, mentally verify:
- [ ] All Phase 1 sub-questions are answered (or marked gray area)
- [ ] The Happy Path is described step by step with no gaps
- [ ] At least 3 edge cases / error scenarios are addressed
- [ ] All technical constraints and dependencies are identified
- [ ] No answer introduced a new unresolved branch

If any branch is still open, continue the interview.

### 5. Generate the Discovery Summary

When the interview is complete (all branches resolved or marked as gray areas, or the
developer said "enough"), generate a structured **Discovery Summary**:

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
- Interactive interview completed (branches fully resolved, typically 10-15 questions for non-trivial tasks)
- Structured Discovery Summary in the conversation context
- Gray areas explicitly documented
