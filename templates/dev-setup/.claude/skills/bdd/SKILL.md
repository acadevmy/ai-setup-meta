---
name: bdd
description: Start a BDD cycle (Given/When/Then) for frontend development (components, pages, user flows)
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:bdd

Start a BDD cycle for the feature or bugfix described by the user.
This methodology is designed for **frontend** development: UI components, pages, user flows.

## Procedure

1. **Specification** — Define scenarios in natural language
   - Write one or more scenarios using the Gherkin format:
     ```gherkin
     Feature: <feature name>

       Scenario: <behavior description>
         Given <initial state>
         When <user action>
         Then <expected result>
     ```
   - Use `And` to add additional steps
   - Use `Scenario Outline` with `Examples` for parametric variants
   - Present the scenarios to the developer for confirmation before proceeding

2. **Implement tests** — Translate scenarios into executable tests
   - Each `Given` prepares the initial state (component render, data mocks)
   - Each `When` simulates the user action (click, input, navigation)
   - Each `Then` verifies the result visible to the user
   - Keep test names aligned with the Gherkin scenarios

3. **Implement code** — Develop the minimum necessary
   - Implement components and logic to make the scenarios pass
   - Focus on user-visible behavior, not implementation details

4. **Refactor** — Improve the code while keeping scenarios green
   - Extract reusable components
   - Improve names
   - Apply CONSTITUTION.md rules

5. **Final verification**
   - Run the project tests:
     - If `package.json` exists with a `test` script: `npm test`
     - If `pubspec.yaml` exists: `flutter test`
     - Otherwise: ask the developer which command to use
   - Run the project linter (if configured):
     - If `package.json` exists with a `lint` script: `npm run lint`
     - If `analysis_options.yaml` exists: `dart analyze`

## Expected input
Description of the feature or bug to fix: $ARGUMENTS
