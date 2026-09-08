---
paths:
  - "**/*.spec.*"
  - "**/*.test.*"
  - "**/*_test.dart"
  - "**/__tests__/**"
  - "**/test/**"
  - "**/tests/**"
---

# Tests

The coverage floors are configured in the test runner (`coverageThreshold` in the
Jest/Vitest config, the analyzer for Dart) — they fail the job, so there is
nothing to remember here beyond: a module without tests drags the number down,
and lowering the threshold to get green is not a fix.

## Which cycle

The layer decides, not the ticket.

**Backend — logic, APIs, services — is TDD.** Write the test that describes the
behaviour, watch it fail for the right reason, write the least code that makes it
pass, then refactor with the test as the net.

```typescript
describe('UserService', () => {
  describe('createUser', () => {
    it('should create a user with a valid email', async () => { /* … */ });
    it('should throw ValidationError if email is invalid', async () => { /* … */ });
    it('should throw ConflictError if email already exists', async () => { /* … */ });
  });
});
```

**Frontend — components, pages, user flows — is BDD.** Describe the scenario in
Given/When/Then first, then translate it into an executable test, then implement.

```gherkin
Feature: User login

  Scenario: Login with valid credentials
    Given the user is on the login page
    When they enter a valid email and password
    And click the "Sign In" button
    Then they are redirected to the dashboard
```

A scenario names user-visible behaviour. `renders correctly` is not a scenario.

## Shape

- One assertion subject per test. Three `it` blocks beat one with three
  unrelated expects, because the failure tells you which behaviour broke.
- Tests are independent: no shared mutable state, no ordering assumption, no
  leaking a mock between files. A test that only passes as part of the suite is
  already broken.
- Test names say what should happen, not what the code does.
- Query the way a user does — role, label, text — before reaching for a test id.
- Mock at the boundary the test owns (the repository, the HTTP client), not
  three layers down inside the implementation.

## Flutter

Many unit tests, fewer widget tests, a few integration tests. `flutter_test`
plus `mocktail` for UseCases, Notifiers and repositories; `pumpWidget` + `find` +
`expect` for screens and reusable widgets; `matchesGoldenFile` for the
design-critical ones; `integration_test` for the critical flows. The test file is
`<source_file>_test.dart` under a `test/` tree mirroring `lib/`.
