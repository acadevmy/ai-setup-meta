---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mts"
  - "**/*.cts"
---

# TypeScript

`strict: true` is on in every `tsconfig.json`, and the linter rejects `any`. The
replacement is `unknown` plus an explicit narrowing — usually the schema parse
below, which narrows and validates in one step.

```typescript
function parsePayload(raw: unknown): ParsedPayload {
  return PayloadSchema.parse(raw);
}
```

A cast (`as User`, `as unknown as T`) asserts something the compiler cannot see.
If the value comes from outside the process, parse it instead.

## Zod is the boundary

Every external datum — API response, form input, environment variable, public
function parameter — goes through a Zod schema before anything reads it. The
inferred type is the type the rest of the code uses, so schema and type cannot
drift apart.

```typescript
const UserSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  role: z.enum(['admin', 'developer', 'viewer']),
});
type User = z.infer<typeof UserSchema>;
```

The project is on **Zod 4**: `z.uuid()`, `z.email()` and `z.iso.datetime()` are
top-level, and the `z.string().uuid()` chained form is deprecated.

## DTOs must survive JSON Schema

A DTO built with `createZodDto` (nestjs-zod) feeds the OpenAPI document, which
NestJS builds at boot with `zod.toJSONSchema()`. Types that have no JSON Schema
representation — `z.date()`, `z.bigint()`, `z.map()`, `z.set()`, `z.symbol()` —
throw there (`Error: Date cannot be represented in JSON Schema`) and the app dies
before it listens.

Dates cross the wire as ISO strings and get converted in the entity→view mapper:

```typescript
export const NotificationViewSchema = z.object({
  createdAt: z.iso.datetime(), // → { type: "string", format: "date-time" }
});
export class NotificationView extends createZodDto(NotificationViewSchema) {}
// mapper: createdAt: notification.createdAt.toISOString()
```

The global `ZodSerializerInterceptor` validates the response against the same
schema, so the declared type and the runtime value have to agree.

## Errors carry context

```typescript
try {
  return await fetchUser(id);
} catch (error) {
  logger.error('fetchUser failed', { userId: id, error });
  throw new AppError('USER_NOT_FOUND', { cause: error });
}
```

`cause` keeps the original stack reachable; the log line carries the identifiers
somebody will grep for. A bare rethrow loses both.

## Naming

The linter enforces `camelCase` for values, `PascalCase` for types and classes,
and allows `UPPER_CASE` for module constants. What it cannot check: file names
are `kebab-case.ts`, and the file is named after the thing it exports
(`user-repository.ts` → `UserRepository`).
