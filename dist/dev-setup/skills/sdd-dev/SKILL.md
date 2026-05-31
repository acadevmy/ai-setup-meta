---
name: sdd-dev
description: Executes development following the approved technical spec, with TDD/BDD or direct development support
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-dev

Executes feature development following the approved technical spec.
Supports three modes: TDD (backend), BDD (frontend), or direct development.

**Usage**: `/project:sdd-dev <SPEC_REF> [METHODOLOGY]`
- `SPEC_REF`: spec path (e.g. `.specs/DE-123-add-auth.md`) or customId (e.g. `DE-123`)
- `METHODOLOGY` (optional): `tdd`, `bdd`, or `none` (default: asks the developer)

Example: `/project:sdd-dev DE-123 tdd`

## Procedure

### 1. Load the spec

**If `$ARGUMENTS` contains a path**:
- Read the file at the indicated path

**If `$ARGUMENTS` contains a customId**:
- Search in `.specs/` for a file starting with the customId (e.g. `DE-123-*.md`)

If the file does not exist, inform the developer and stop.

**Verify status**: If the spec status is not `approved`, warn the developer:
```
Warning: the spec is not yet approved (status: <status>).
Do you want to proceed with development anyway?
```
If the developer does not confirm, stop.

### 2. Determine the methodology

If the methodology was not specified in `$ARGUMENTS`, ask the developer:
```
Development methodology:
1. TDD (Red-Green-Refactor) — recommended for backend, business logic, APIs, services
2. BDD (Given/When/Then) — recommended for frontend, UI components, user flows
3. None — direct development without test-first cycle
```

### 3. Create the task breakdown

Parse the "Implementation plan" section from the spec.
For each step in the plan, create an internal task with:
- Sequential number
- Step description
- Involved files

Present the breakdown to the developer:
```
Task breakdown from spec:
[ ] 1. <Step 1> — <involved files>
[ ] 2. <Step 2> — <involved files>
...

Do you want to proceed or change the order?
```

Wait for confirmation before starting.

### 4. Execute development

For each step in the plan, in the agreed order:

1. **Announce** the current step:
   ```
   Step <N>/<total>: <description>
   ```
2. **Read documentation** if needed: retrieve up-to-date docs for libraries and frameworks. Prefer the `ctx7` CLI (`ctx7 library <name> <query>` then `ctx7 docs <libraryId> <query>`) if available in PATH; fall back to the Context7 MCP otherwise

3. **Implement** according to the chosen methodology:

   **If TDD**:
   - **Red** — Write the test describing the expected behavior
     - Use `describe` / `it` structure with descriptive names
     - Test a single behavior per test case
     - The test must fail for the right reason
   - **Green** — Implement the minimum code necessary to make the test pass
     - Only enough code to make the test pass
     - No premature optimizations
   - **Refactor** — Improve the code while keeping tests green
     - Eliminate duplication
     - Improve names
     - Apply CONSTITUTION.md rules

   **If BDD**:
   - **Specification** — Define scenarios in Gherkin format:
     ```gherkin
     Feature: <feature name>

       Scenario: <behavior description>
         Given <initial state>
         When <user action>
         Then <expected result>
     ```
   - **Test** — Translate scenarios into executable tests
     - Each `Given` prepares the initial state
     - Each `When` simulates the user action
     - Each `Then` verifies the visible result
   - **Implement** — Develop the minimum necessary to make scenarios pass
   - **Refactor** — Improve the code applying CONSTITUTION.md

   **If no methodology**:
   - Implement directly following the spec
   - Write tests after implementation (if the spec's test strategy requires it)

4. **Verify** — After each step, run tests and linter:
   - **Tests**:
     - If `package.json` exists with a `test` script: `npm test`
     - If `pytest.ini` or `pyproject.toml` with `[tool.pytest]` exists: `pytest`
     - If `go.mod` exists: `go test ./...`
     - If `pubspec.yaml` exists: `flutter test`
     - If `Cargo.toml` exists: `cargo test`
     - Otherwise: ask the developer which command to use
   - **Linter**:
     - If `package.json` exists with a `lint` script: `npm run lint`
     - If ruff configuration exists: `ruff check .`
     - If `.golangci.yml` exists: `golangci-lint run`
     - If `analysis_options.yaml` exists: `dart analyze`
     - If `Cargo.toml` exists: `cargo clippy`

5. **Update** the task breakdown:
   ```
   [x] 1. <Step 1> — completed
   [x] 2. <Step 2> — completed
   [ ] 3. <Step 3> — in progress
   ...
   ```

### 5. Simplify

After all steps are completed, run the `simplify` skill to:
- Look for opportunities to reuse existing code
- Improve quality and efficiency
- Fix any issues found
- If there are changes, commit them: `refactor(<scope>): simplify implementation`

**Track the outcome in the spec**: at the end of the simplify run, update the `## Simplify phase` section of the loaded spec file with:
- `Stato`: `completata` (oppure `skipped` se la skill non è stata eseguita per qualche motivo documentato)
- `Data`: data odierna in formato `YYYY-MM-DD`
- `Esito`: `changes-applied` se sono state committate modifiche, `no-changes` se il diff era già minimale, `skipped` con motivo
- `Modifiche applicate`: elenco sintetico dei file modificati o `nessuna`
- `Note`: eventuali file fuori scope, osservazioni o motivi di skip

Sovrascrivi la sezione esistente preservando il resto dello spec. Non creare un commit dedicato per questa annotazione: includila nel commit successivo, oppure committala insieme al `refactor(<scope>): simplify implementation` se ci sono modifiche.

### 6. Summary

Present a summary of what was implemented:
```
Development completed for spec: <customId> — <title>

Steps completed: <N>/<total>
Methodology: <tdd/bdd/none>
Files created: <list>
Files modified: <list>
Tests: <result>
Linter: <result>
```

## Expected output
- Code implemented following the approved spec
- Tests executed and passing
- Linter executed without errors
- Code optimized via simplify
- Summary of completed development
