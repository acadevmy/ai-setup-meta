# Development methodologies and the per-step check

The three ways a plan step gets implemented, and how each one is checked before
the next step starts.

## Index

- [TDD — Red, Green, Refactor](#tdd--red-green-refactor)
- [BDD — Given, When, Then](#bdd--given-when-then)
- [No methodology](#no-methodology)
- [The per-step check](#the-per-step-check)

## TDD — Red, Green, Refactor

For backend work: business logic, APIs, services, the data layer.

- **Red** — write the test that describes the expected behaviour.
  - `describe` / `it` structure, descriptive names
  - one behaviour per test case
  - the test must fail, and fail for the right reason
- **Green** — write the minimum code that makes it pass.
  - only enough to pass; no premature optimisation
- **Refactor** — improve the code while the tests stay green.
  - remove duplication, improve names
  - apply the rules in `.claude/rules/`

One Red-Green-Refactor cycle per behaviour, simplest case first.

## BDD — Given, When, Then

For frontend work: UI components, pages, user flows.

- **Specification** — write the scenarios in Gherkin:

  ```gherkin
  Feature: <feature name>

    Scenario: <behavior description>
      Given <initial state>
      When <user action>
      Then <expected result>
  ```

  `And` adds steps; `Scenario Outline` with `Examples` covers parametric
  variants. Present the scenarios to the developer before implementing them.

- **Test** — translate each scenario into an executable test. Every `Given`
  prepares the state (render, mocks), every `When` performs the user action
  (click, input, navigation), every `Then` asserts what the user can see. Keep
  the test names aligned with the scenario names.
- **Implement** — the minimum needed to make the scenarios pass. Focus on
  user-visible behaviour, not implementation detail.
- **Refactor** — extract reusable components, improve names, apply the rules in
  `.claude/rules/`.

## No methodology

Implement directly from the spec, then write the tests the spec's test strategy
asks for. "No methodology" means no test-first cycle — it does not mean no
tests.

## The per-step check

After every step, run the project's own test and lint commands. They are already
resolved for you:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh --json
```

`TEST_CMD`, `LINT_CMD` and `TYPECHECK_CMD` hold what this project uses; an empty
value means the project has none. What the script resolves, per stack:

| Stack marker | `TEST_CMD` | `LINT_CMD` |
|---|---|---|
| `package.json` with a `test` / `lint` script | `npm test` (or `npx vitest`) | `npm run lint` |
| `pytest.ini`, or `pyproject.toml` with `[tool.pytest]` | `pytest` | `ruff check .` with `[tool.ruff]` |
| `go.mod` | `go test ./...` | `golangci-lint run` with `.golangci.yml` |
| `pubspec.yaml` | `flutter test` | `dart analyze` |
| `Cargo.toml` | `cargo test` | `cargo clippy` |
| Terraform | `terraform validate` | `terraform fmt -check -recursive` |

If both come back empty, ask the developer which commands to use rather than
guessing one.

A red test or a lint error stops the step: fix it before announcing the next
one. Do not carry a failure forward "to fix at the end" — the commit gate will
refuse it anyway, and by then the cause is three steps back.
