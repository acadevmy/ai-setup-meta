# Profile: Backend Node.js / NestJS

Stack: **Node.js 20+**, **NestJS 10+**
Validation: Zod + class-validator (NestJS pipes)
Testing: Jest + Supertest
ORM: Prisma (preferred) or TypeORM

## Required dependencies

```json
{
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0",
    "eslint": "^8.57.0",
    "eslint-plugin-import": "^2.29.0",
    "prettier": "^3.2.0",
    "jest": "^29.7.0",
    "@types/jest": "^29.5.0",
    "ts-jest": "^29.1.0",
    "supertest": "^7.0.0",
    "@types/supertest": "^6.0.0",
    "semantic-release": "^24.0.0",
    "@semantic-release/changelog": "^6.0.3",
    "@semantic-release/git": "^10.0.1",
    "@semantic-release/github": "^10.0.0",
    "conventional-changelog-conventionalcommits": "^8.0.0"
  },
  "dependencies": {
    "zod": "^3.23.0",
    "@nestjs/common": "^10.0.0",
    "@nestjs/core": "^10.0.0",
    "@nestjs/platform-express": "^10.0.0",
    "class-validator": "^0.14.0",
    "class-transformer": "^0.5.0"
  }
}
```

## ESLint configuration

```json
{
  "extends": [
    "./.eslintrc.base.json",
    "plugin:import/recommended",
    "plugin:import/typescript"
  ],
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/explicit-function-return-type": "warn",
    "import/order": ["error", {
      "groups": ["builtin", "external", "internal", "parent", "sibling"],
      "newlines-between": "always",
      "alphabetize": { "order": "asc" }
    }],
    "no-console": "error"
  }
}
```

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

```typescript
// jest.config.ts
export default {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  coverageDirectory: '../coverage',
  testEnvironment: 'node',
  coverageThreshold: {
    global: { lines: 80, functions: 80, branches: 70 },
    './services/': { lines: 80 },
    './utils/': { lines: 90 },
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

## Additional slash commands

- `/project:new-module` — scaffolds a complete NestJS module (CRUD) with tests
- `/project:new-dto` — creates a DTO with Zod schema and class-validator
- `/project:api-review` — reviews the API design of the current controller

## Specific rules

- Every endpoint validates input with a DTO that uses both Zod and class-validator
- Services never import directly from the controller
- Repositories are the only layer that knows the ORM/database
- Use NestJS `Logger` — never `console.log`
- Exceptions: use `HttpException` or NestJS built-in exceptions
