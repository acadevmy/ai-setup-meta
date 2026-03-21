# Profilo: Backend Node.js / NestJS

Stack: **Node.js 20+**, **NestJS 10+**
Validation: Zod + class-validator (NestJS pipes)
Testing: Jest + Supertest
ORM: Prisma (preferito) o TypeORM

## Dipendenze obbligatorie

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
    "@types/supertest": "^6.0.0"
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

## Configurazione ESLint

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

## Configurazione TypeScript

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

## Configurazione Jest

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

## Struttura cartelle NestJS (obbligatoria)

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

## Comandi slash aggiuntivi

- `/project:new-module` — scaffolda modulo NestJS completo (CRUD) con test
- `/project:new-dto` — crea DTO con Zod schema e class-validator
- `/project:api-review` — review dell'API design del controller corrente

## Regole specifiche

- Ogni endpoint valida l'input con un DTO che usa sia Zod che class-validator
- I service non importano mai direttamente dal controller
- I repository sono l'unico layer che conosce il ORM/database
- Usare `Logger` di NestJS — mai `console.log`
- Eccezioni: usare `HttpException` o le eccezioni built-in NestJS
