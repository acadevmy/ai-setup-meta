---
description: "Performs code review of the current branch verifying CONSTITUTION compliance and updating REGISTRY"
---


# /project:review

Perform a code review of the modified code in the current branch via the Review Agent.

## Procedure

### 1. Launch the Review Agent

Launch the `review` agent with:
- BASE_BRANCH: `main`
- CONSTITUTION_PATH: `./CONSTITUTION.md`
- REGISTRY_PATH: `./REGISTRY.md`
- TASK_ID: extracted from the current branch name (e.g. `feat/DE-123-desc` → `DE-123`), if present

### 2. Analyze the result

Parse the `---REVIEW-RESULT---` output returned by the agent.

**If STATUS = fail**:
- Show all VIOLATIONS with file, line and violated rule
- Show WARNINGS as suggestions
- Inform the developer that the review did not pass
- Stop — the code must be fixed before proceeding

**If STATUS = pass-with-warnings**:
- Show WARNINGS as improvement suggestions
- Proceed to the next step

**If STATUS = pass**:
- Confirm that the code is compliant
- Proceed to the next step

### 3. Apply REGISTRY updates

If the agent returned non-empty REGISTRY_UPDATES:

1. Read the current `REGISTRY.md`
2. For each entry with ACTION: `add`:
   - Add the ENTRY block in the indicated SECTION
   - Remove any placeholder `_No ... registered._` from the section
3. For each entry with ACTION: `update`:
   - Find the existing entry in the section and update the modified fields
4. Commit the update: `docs(registry): update REGISTRY.md`

### 4. Track the outcome in the spec

Locate the spec for the current task:
- Extract the customId from the current branch name (e.g. `feat/DE-123-desc` → `DE-123`)
- Find `.specs/<customId>-*.md`
- If no spec exists, skip this step (the review was likely invoked outside the SDD flow)

Update the `## Review phase` section of the spec with:
- `Stato`: `completata`
- `Data`: data odierna in formato `YYYY-MM-DD`
- `Esito`: il valore di STATUS restituito dal Review Agent (`pass`, `pass-with-warnings`, `fail`)
- `Violazioni`: numero di violazioni CONSTITUTION rilevate
- `Warning`: elenco sintetico dei warning con motivazione (es. `W-1: missing test for X`), oppure `nessuno`
- `REGISTRY updates`: numero di entry applicate + breve riassunto add/update per sezione, oppure `nessuna`

Sovrascrivi la sezione esistente preservando il resto dello spec. Se sono già stati prodotti commit di REGISTRY (`docs(registry): update REGISTRY.md`), includi l'aggiornamento dello spec in un commit aggiuntivo `docs(spec): track review outcome` oppure aggiungilo allo stesso commit di REGISTRY se la stage è ancora aperta.

### 5. Final report

Show a summary:
```
Review: <STATUS>
Violations: <count>
Warnings: <count>
REGISTRY updated: <yes/no>
Spec updated: <yes/no>

<SUMMARY from agent>
```

## Expected output
- CONSTITUTION compliance report
- `REGISTRY.md` updated with new entries (if any)
- Commit `docs(registry): update REGISTRY.md` (if registry changes)
- Spec file aggiornato con la sezione `## Review phase` compilata (se lo spec esiste)
