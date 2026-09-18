---
paths:
  - "**/*.{dto,schema,controller,view}.ts"
---

# NestJS DTOs and the OpenAPI document

A DTO built with `createZodDto` (nestjs-zod) feeds the OpenAPI document, which
NestJS builds at boot with `zod.toJSONSchema()`. Types that have no JSON Schema
representation — `z.date()`, `z.bigint()`, `z.map()`, `z.set()`, `z.symbol()` —
throw there (`Error: Date cannot be represented in JSON Schema`) and the app dies
before it listens. This is a boot crash, not a runtime edge case.

Dates cross the wire as ISO strings and get converted in the entity→view mapper:

```typescript
export const NotificationViewSchema = z.object({
  createdAt: z.iso.datetime(), // → { type: "string", format: "date-time" }
});
export class NotificationView extends createZodDto(NotificationViewSchema) {}
// mapper: createdAt: notification.createdAt.toISOString()
```

The global `ZodSerializerInterceptor` validates the response against the same
schema, so the declared type and the runtime value have to agree — a schema
saying `string` and a mapper handing over a `Date` fails at serialization time,
on the endpoint, not at boot.

One schema per DTO. Two validation sources on the same property — Zod plus
`class-validator` decorators — are two schemas kept in sync by hand, and a hole
opens the first time they diverge. `class-transformer` stays allowed for outbound
serialization only (`@Exclude`, `@Expose`), where it does not overlap.
