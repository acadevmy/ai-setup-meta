---
description: "Start a TDD cycle (Red-Green-Refactor) for backend development (logic, APIs, services)"
---


# /project:tdd

Start a classic TDD cycle for the feature or bugfix described by the user.
This methodology is designed for **backend** development: business logic, APIs, services, data layer.

## Procedure

1. **Red** — Write the test describing the expected behavior
   - Use `describe` / `it` structure with descriptive names
   - Test a single behavior per test case
   - The test must fail for the right reason

2. **Green** — Implement the minimum necessary code
   - Only enough code to make the test pass
   - No premature optimizations

3. **Refactor** — Improve the code while keeping tests green
   - Eliminate duplication
   - Improve names
   - Apply CONSTITUTION.md rules

4. **Repeat** — Move on to the next behavior
   - One Red-Green-Refactor cycle per behavior
   - Proceed from the simplest case to the most complex

5. **Final verification**
   - Run the project tests:
     - If `package.json` exists with a `test` script: `npm test`
     - If `pytest.ini` or `pyproject.toml` with `[tool.pytest]` exists: `pytest`
     - If `go.mod` exists: `go test ./...`
     - If `pubspec.yaml` exists: `flutter test` (for Dart backend packages)
     - If `Cargo.toml` exists: `cargo test`
     - Otherwise: ask the developer which command to use
   - Run the project linter (if configured):
     - If `package.json` exists with a `lint` script: `npm run lint`
     - If ruff configuration exists: `ruff check .`
     - If `.golangci.yml` exists: `golangci-lint run`
     - If `analysis_options.yaml` exists: `dart analyze`
     - If `Cargo.toml` exists: `cargo clippy`

## Expected input
Description of the feature or bug to fix: $ARGUMENTS
