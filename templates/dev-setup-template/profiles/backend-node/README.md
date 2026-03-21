# Profilo: Backend Node.js / NestJS

Stack: **Node.js 20+**, **NestJS 10+**
Validation: Zod + class-validator (NestJS pipes)
Testing: Jest + Supertest
ORM: Prisma (preferito) o TypeORM

## Dipendenze obbligatorie

```bash
npm install zod @nestjs/common @nestjs/core @nestjs/platform-express class-validator class-transformer
npm install -D @typescript-eslint/eslint-plugin @typescript-eslint/parser \
  eslint eslint-plugin-import prettier \
  jest @types/jest ts-jest supertest @types/supertest \
  semantic-release @semantic-release/changelog @semantic-release/git \
  @semantic-release/github conventional-changelog-conventionalcommits
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
│       ├── schemas/              # Zod schemas
│       └── __tests__/
├── common/
│   ├── filters/
│   ├── guards/
│   ├── interceptors/
│   └── pipes/
└── main.ts
```

## Regole specifiche

- Ogni endpoint valida l'input con un DTO che usa sia Zod che class-validator
- I service non importano mai direttamente dal controller
- I repository sono l'unico layer che conosce il ORM/database
- Usare `Logger` di NestJS — mai `console.log`
- Eccezioni: usare `HttpException` o le eccezioni built-in NestJS

## File di configurazione inclusi

- `.eslintrc.json` — estende la config base con regole import ordering
- `tsconfig.json` — TypeScript strict con decorators per NestJS
- `jest.config.ts` — Jest con ts-jest e soglie di copertura
