---
name: sdd-spec
description: Generates a technical specification and implementation plan for a ClickUp task following the Spec-Driven Development approach
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-spec

Generates a complete technical specification and implementation plan for a task.
This skill analyzes the task, the project context and produces a structured spec document
in the `.specs/` directory.

**Usage**: `/project:sdd-spec [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): retrieves the task from ClickUp and generates the spec
- Without arguments: uses the context already present in the conversation (when invoked by the `sdd` orchestrator)

## Procedure

### 1. Retrieve the task context

**If `$ARGUMENTS` contains a TASK_ID**:
- Launch the `clickup` agent with:
  - INTENT: `read`
  - PARAMS: `task_id: <provided TASK_ID>`
- If the agent returns STATUS: error, inform the developer and stop
- Extract: `custom_id`, `name`, `description`, `priority`, `task_id`, `url`

**If `$ARGUMENTS` is empty**:
- Use the task context already available in the conversation (passed by the orchestrator)
- If no context is available, ask the developer to provide a TASK_ID

### 2. Analyze the project

- Read `CONSTITUTION.md` to understand applicable technical constraints
- Read `REGISTRY.md` to learn about existing components, adopted patterns and architectural decisions
- Identify relevant files in the project based on the task requirements
- Check `.specs/` to verify a spec doesn't already exist for the same task

### 3. Discovery (conditional)

**If a Discovery Summary is present in the conversation context** (passed by the `sdd` orchestrator or from a previous invocation of `/project:sdd-discovery`):
- Use the Discovery Summary as the base for spec generation
- Do not repeat the interview

**If a Discovery Summary is NOT present**:
- Invoke `/project:sdd-discovery` passing the task context
- Wait for the discovery to complete before proceeding to generation

Do not proceed with generation until a Discovery Summary is available.

### 4. Create the specs directory

If `.specs/` does not exist in the project root:
```bash
mkdir -p .specs
```

### 5. Generate the spec document

Create the file `.specs/<customId>-<slug>.md` where `<slug>` is a short kebab-case version of the task title.

The document must follow this format:

```markdown
# Spec: <Task Title> [<customId>]

> Status: draft
> Task: <ClickUp task URL>
> Branch: <branch name, if already created>
> Created: <today's date YYYY-MM-DD>
> Approved: pending

## Context
<Why this task exists. Background and motivation extracted from the
ClickUp task description and the developer interview.>

## Requirements
<Requirements extracted from the ClickUp task description, structured as bullet points.
Each requirement must be verifiable.>

- REQ-1: <requirement>
- REQ-2: <requirement>
- ...

## Technical decisions
<Architectural and technical decisions made for this implementation.
Include: chosen approach, patterns to use, libraries, motivations.
Reference patterns already present in REGISTRY.md where applicable.>

## Impact
- **Files to create**: <list of new files with relative path>
- **Files to modify**: <list of existing files to modify with relative path>
- **Dependencies**: <new dependencies to install, or "none">

## Implementation plan
<Ordered sequence of steps to implement the solution.
Each step must be atomic and verifiable.>

1. <Step 1> — <detailed description>
2. <Step 2> — <detailed description>
...

## Test strategy
<Recommended testing approach (TDD/BDD/none) with rationale.
List of main test cases to implement.>

- Test 1: <description>
- Test 2: <description>
- ...

## Simplify phase
<Stato di esecuzione della skill `simplify` dopo lo sviluppo.
Da compilare dal flusso `/project:sdd-dev` (step Simplify) al termine dell'esecuzione.>

- **Stato**: pending | completata | skipped
- **Data**: <YYYY-MM-DD quando eseguita, altrimenti "—">
- **Esito**: <`changes-applied` | `no-changes` | `skipped` quando completata, altrimenti "—">
- **Modifiche applicate**: <elenco sintetico dei file/refactor applicati, oppure "nessuna">
- **Note**: <eventuali osservazioni, file fuori scope, motivi di skip>

## Review phase
<Stato di esecuzione della skill `/project:review` dopo lo sviluppo.
Da compilare dal flusso `/project:review` al termine dell'esecuzione.>

- **Stato**: pending | completata
- **Data**: <YYYY-MM-DD quando eseguita, altrimenti "—">
- **Esito**: <`pass` | `pass-with-warnings` | `fail` quando completata, altrimenti "—">
- **Violazioni**: <numero di violazioni CONSTITUTION rilevate, oppure 0>
- **Warning**: <elenco sintetico W-1, W-2, ... con motivazione, oppure "nessuno">
- **REGISTRY updates**: <numero entry applicate + breve riassunto add/update per sezione, oppure "nessuna">

## Notes
<Risks, open questions, additional considerations, useful references.>
```

**Guidelines for generation**:
- Requirements must be faithfully extracted from the ClickUp task description
- Technical decisions must comply with CONSTITUTION.md
- The implementation plan must be ordered by dependencies (foundations first, then features)
- Reuse components and patterns already present in REGISTRY.md
- Test cases must cover the listed requirements
- Le sezioni `## Simplify phase` e `## Review phase` devono essere generate sempre con stato `pending` (placeholder "—" nei campi data/esito): verranno compilate automaticamente dai flussi `/project:sdd-dev` e `/project:review` al termine dell'esecuzione

### 6. Show the spec

Present the complete spec to the developer and confirm the file path:
```
Spec generated: .specs/<customId>-<slug>.md
Status: draft

<spec content>
```

## Expected output
- Spec file created in `.specs/<customId>-<slug>.md` with status `draft`
- Spec shown in full to the developer
