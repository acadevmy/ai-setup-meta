---
paths:
  - "{{SERVICES_GLOB}}"
---

# Service layer

The glob above was resolved from this project's layout at setup time, so this
rule loads on the files that actually hold the business logic here.

## Layers

```
Controller / route handler  →  parse the request, call the service
Service                     →  business logic
Repository                  →  data access
```

The chain is not skipped. A controller that queries the database directly moves
the transaction boundary into the HTTP layer and makes the logic untestable
without a request object. A repository that decides *whether* something may
happen has taken the service's job.

The repository is the only layer that knows the ORM, the query builder or the
driver. Nothing above it imports a database type.

## Dependencies

Collaborators arrive through dependency injection — NestJS's container, or a
constructor parameter in a plain Node project. `new SomeClient()` inside a
function hard-wires the implementation and its lifetime into the caller, so
nothing above can substitute it.

Depend on the abstraction, not the implementation: the service names the
repository interface it needs, and the container decides which one it gets.

## Boundaries between modules

- One reason to change per class or module. When a service grows a second
  unrelated reason, it is two services.
- Extend by composition or by a new implementation of an existing interface,
  not by editing the class every caller already depends on.
- A subtype has to work everywhere its base type does — no method that throws
  "not supported" to satisfy a signature.
- Small, purpose-shaped interfaces over one wide one. A consumer that needs one
  method should not have to know about eight.

## What crosses the boundary

Errors leave the service as domain-typed errors, never as the driver's
exception. Input has already been validated at the controller boundary, so the
service can assume its arguments are well formed and does not re-validate them
defensively.
