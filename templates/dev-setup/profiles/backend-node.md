# Profile: Backend Node.js / NestJS

Stack: **Node.js 24+**, **NestJS 11+**
Validation: **Zod 4** via `nestjs-zod` (single source of truth — see below)
Testing: Jest 30 + Supertest
ORM: Prisma (preferred) or TypeORM

> Versions verified on npm on 2026-09-08. When bumping them, re-check the peer
> ranges: they are the constraint that decides whether the install succeeds on
> the first try.

## Required dependencies

```json
{
  "devDependencies": {
    "typescript": "^5.9.3",
    "typescript-eslint": "^8.70.0",
    "@eslint/js": "^9.39.0",
    "eslint": "^9.39.0",
    "eslint-plugin-import": "^2.32.0",
    "eslint-plugin-boundaries": "^7.2.0",
    "globals": "^17.12.0",
    "prettier": "^3.9.0",
    "@nestjs/cli": "^12.0.0",
    "@nestjs/testing": "^11.2.3",
    "jest": "^30.5.0",
    "@types/jest": "^30.0.0",
    "@types/node": "^24.13.0",
    "ts-jest": "^29.4.0",
    "supertest": "^7.2.0",
    "@types/supertest": "^7.2.0",
    "semantic-release": "^25.0.0",
    "@semantic-release/changelog": "^7.0.0",
    "@semantic-release/git": "^11.0.0",
    "@semantic-release/npm": "^13.1.0",
    "@semantic-release/github": "^12.0.0",
    "@semantic-release/gitlab": "^13.3.0",
    "conventional-changelog-conventionalcommits": "^10.4.0"
  },
  "dependencies": {
    "@nestjs/common": "^11.2.3",
    "@nestjs/core": "^11.2.3",
    "@nestjs/platform-express": "^11.2.3",
    "@nestjs/swagger": "^11.4.7",
    "nestjs-zod": "^5.5.0",
    "zod": "^4.5.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.2"
  }
}
```

**Notes on the pins**

- NestJS stays on **11.x**: `nestjs-zod@5` declares peers
  `@nestjs/common: ^10 || ^11` and `@nestjs/swagger: ^7.4.2 || ^8 || ^11`. On
  NestJS 12 the install fails with `ERESOLVE`. Raise the pin once `nestjs-zod`
  widens its peer range.
- `eslint` stays on **9.x**: `eslint-plugin-import` declares `eslint: ^9` as its
  peer ceiling.
- `eslint-plugin-boundaries` stays on **7.x**: `boundaries/dependencies` with
  `policies` and file categories is the v7 API (v6 spelled it `boundaries/element-types`
  with `rules`, still accepted but deprecated). It declares `eslint: >=6` and
  brings no resolver of its own — it reuses the `import/resolver` that
  `eslint-plugin-import`'s TypeScript flat config already sets, which is why the
  two configs must both be scoped to `**/*.ts`.
- `typescript` stays on **5.9**: `typescript-eslint@8` declares
  `typescript: >=4.8.4 <6.1.0`.
- `ts-jest@29.4` covers Jest 30 (peer `jest: ^29 || ^30`).
- Of the two VCS-specific semantic-release plugins keep **only the one for your
  provider**, matching the `.releaserc.json` the setup generates.
- ORM: `prisma` + `@prisma/client` `^7.10.0` (the 8.x `latest` is still a
  release candidate), or `typeorm` `^1.1.0`.

## Validation: Zod as the single source of truth

A DTO has **one** validation source. `class-validator` is not used alongside Zod
on the same DTO: two decorators on the same property mean two schemas kept in
sync by hand, and the moment they diverge a hole opens. The schema-first rule in
`.claude/rules/dev-setup-typescript.md` mandates Zod, and `z.iso.datetime()` is
**Zod 4** API.

`nestjs-zod` bridges to the NestJS pipes and generates the OpenAPI schema:

```typescript
// modules/user/schemas/user.schema.ts
import { z } from 'zod';

export const createUserSchema = z.object({
  email: z.email(),
  name: z.string().min(2).max(120),
  createdAt: z.iso.datetime(), // Zod 4 — { type: "string", format: "date-time" }
});

export type CreateUser = z.infer<typeof createUserSchema>;
```

```typescript
// modules/user/dto/create-user.dto.ts
import { createZodDto } from 'nestjs-zod';

import { createUserSchema } from '../schemas/user.schema';

export class CreateUserDto extends createZodDto(createUserSchema) {}
```

```typescript
// main.ts
import { ZodValidationPipe } from 'nestjs-zod';

app.useGlobalPipes(new ZodValidationPipe());
```

`class-transformer` stays allowed only for outbound serialization
(`@Exclude`/`@Expose`), where it does not overlap with validation.

## ESLint configuration (flat config, extends base)

`eslint.config.mjs` at the project root — it imports the base the setup distributes:

```javascript
// eslint.config.mjs
import boundaries from 'eslint-plugin-boundaries';
import importPlugin from 'eslint-plugin-import';

import base from './eslint.config.base.mjs';

// The `eslint-plugin-import` configs are scoped to TypeScript sources only:
// applied to everything, its resolver fails on "exports-only" packages
// (e.g. `typescript-eslint`, imported by the base) and would fire
// import/no-unresolved on the config file itself.
const config = [
  ...base,
  { ...importPlugin.flatConfigs.recommended, files: ['**/*.ts'] },
  { ...importPlugin.flatConfigs.typescript, files: ['**/*.ts'] },
  {
    files: ['**/*.ts'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/explicit-function-return-type': 'warn',
      'import/order': [
        'error',
        {
          groups: ['builtin', 'external', 'internal', 'parent', 'sibling'],
          'newlines-between': 'always',
          alphabetize: { order: 'asc' },
        },
      ],
      'no-console': 'error',
    },
  },

  // Layer separation, enforced. A controller that imports the repository, or a
  // repository that reaches back up into a service, is a lint error instead of a
  // review comment. The layers are read off the NestJS file-suffix convention,
  // so nothing has to move into layer directories for this to work.
  {
    files: ['**/*.ts'],
    plugins: { boundaries },
    settings: {
      'boundaries/files': [
        { pattern: '**/*.controller.ts', category: 'controller' },
        { pattern: '**/*.service.ts', category: 'service' },
        { pattern: '**/*.repository.ts', category: 'repository' },
      ],
    },
    rules: {
      'boundaries/dependencies': [
        'error',
        {
          // Everything else (module, dto, schema, entity, main) is uncategorised
          // and must keep working: only the three transitions below are refused.
          default: 'allow',
          policies: [
            {
              from: { file: { categories: 'controller' } },
              disallow: { to: { file: { categories: 'repository' } } },
              message: 'A controller calls a service, never the repository.',
            },
            {
              from: { file: { categories: 'repository' } },
              disallow: { to: { file: { categories: { anyOf: ['service', 'controller'] } } } },
              message: 'The repository is the bottom layer: it does not call back upwards.',
            },
            {
              from: { file: { categories: 'service' } },
              disallow: { to: { file: { categories: 'controller' } } },
              message: 'A service does not import its controller.',
            },
          ],
        },
      ],
    },
  },
];

export default config;
```

`eslint-plugin-import` exposes its flat configs under `flatConfigs.*`: they are
objects (not arrays), so copy them with a spread and add `files`.

`boundaries/dependencies` needs `default` set explicitly: omit it and every
dependency that matches no policy is refused, which on a NestJS project means
modules, DTOs and `main.ts` all light up. Hence `default: 'allow'` plus the three
transitions that are genuinely forbidden.

The rule can only compare the two sides of an import once the import path
resolves to a file, so it depends on the `import/resolver` that
`importPlugin.flatConfigs.typescript` installs above. Drop that config object and
`boundaries/dependencies` silently reports nothing.

## TypeScript configuration

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true,
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "outDir": "./dist",
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

## Jest configuration

The config file is **`jest.config.mjs`**, not `.ts`: with `jest.config.ts` Jest
demands `ts-node` (`Jest: 'ts-node' is required for the TypeScript
configuration files`). The source transform stays `ts-jest`.

```javascript
// jest.config.mjs
export default {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  // Without collectCoverageFrom the threshold is computed only over files the
  // tests touch: a never-imported file lowers nothing and the threshold gates
  // nothing. With the list, a module without tests fails the job.
  collectCoverageFrom: ['**/*.ts', '!**/*.spec.ts', '!**/*.module.ts', '!**/*.dto.ts', '!main.ts'],
  coverageDirectory: '../coverage',
  testEnvironment: 'node',
  coverageThreshold: {
    global: { lines: 80, functions: 80, branches: 70 },
    // Per-layer thresholds — uncomment each entry once the
    // directory exists. Jest hard-fails with "Coverage data for <path> was not
    // found" on any path or glob that matches nothing, which would break a
    // greenfield on its very first `test:cov`.
    // './services/': { lines: 80 },
    // './utils/': { lines: 90 },
  },
};
```

## NestJS folder structure (mandatory)

```
src/
├── modules/
│   └── <feature>/
│       ├── <feature>.module.ts
│       ├── <feature>.controller.ts
│       ├── <feature>.service.ts
│       ├── <feature>.repository.ts
│       ├── dto/
│       │   ├── create-<feature>.dto.ts
│       │   └── update-<feature>.dto.ts
│       ├── schemas/              # Zod schemas
│       │   └── <feature>.schema.ts
│       └── __tests__/
│           ├── <feature>.service.spec.ts
│           └── <feature>.controller.spec.ts
├── common/
│   ├── filters/
│   ├── guards/
│   ├── interceptors/
│   └── pipes/
└── main.ts
```

## Specific rules

- Every endpoint validates input with a `createZodDto` DTO — **one** schema per DTO
- Services never import from the controller
- The repository is the only layer that knows the ORM/database
- Use the NestJS `Logger` — never `console.log`
- Exceptions: `HttpException` or the NestJS built-in exceptions
