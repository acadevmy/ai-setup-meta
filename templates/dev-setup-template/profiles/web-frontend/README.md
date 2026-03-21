# Profilo: Web Frontend

Stack: **Next.js 14+**, **Angular 17+**, **React 18+**
UI: ShadCN/UI + Tailwind CSS
Validation: Zod
Testing: Jest + Testing Library

## Dipendenze obbligatorie

```bash
npm install zod @hookform/resolvers react-hook-form
npm install -D @typescript-eslint/eslint-plugin @typescript-eslint/parser \
  eslint eslint-config-next eslint-plugin-react eslint-plugin-react-hooks \
  prettier prettier-plugin-tailwindcss \
  @testing-library/react @testing-library/jest-dom @testing-library/user-event \
  jest jest-environment-jsdom \
  semantic-release @semantic-release/changelog @semantic-release/git \
  @semantic-release/github conventional-changelog-conventionalcommits
```

## Regole specifiche (in aggiunta alla Costituzione)

- Usare `'use client'` solo quando necessario — preferire Server Components
- Le chiamate API avvengono in Server Components o Route Handlers, non nel client
- Ogni form usa `react-hook-form` + Zod resolver
- Nessun `useEffect` per fetch — usare `async/await` in Server Components o SWR/TanStack Query

## File di configurazione inclusi

- `.eslintrc.json` — estende la config base con regole React/Next.js
- `tsconfig.json` — TypeScript strict con supporto DOM
- `jest.config.ts` — Jest con jsdom e soglie di copertura
