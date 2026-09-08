# Profile: Web Frontend

Stack: **Next.js 16+**, **Angular 22+**, **React 19+**
UI: ShadCN/UI + Tailwind CSS 4
Validation: Zod 4
Testing: Jest 30 + Testing Library

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
    "eslint-config-next": "^16.3.0",
    "eslint-plugin-react": "^7.37.0",
    "eslint-plugin-react-hooks": "^7.1.0",
    "eslint-plugin-jsx-a11y": "^6.10.0",
    "globals": "^17.12.0",
    "prettier": "^3.9.0",
    "prettier-plugin-tailwindcss": "^0.8.0",
    "tailwindcss": "^4.3.0",
    "@tailwindcss/postcss": "^4.3.0",
    "@testing-library/react": "^16.3.0",
    "@testing-library/jest-dom": "^7.0.0",
    "@testing-library/user-event": "^14.6.0",
    "@types/react": "^19.2.0",
    "@types/react-dom": "^19.2.0",
    "@types/node": "^24.13.0",
    "jest": "^30.5.0",
    "jest-environment-jsdom": "^30.5.0",
    "@types/jest": "^30.0.0",
    "semantic-release": "^25.0.0",
    "@semantic-release/changelog": "^7.0.0",
    "@semantic-release/git": "^11.0.0",
    "@semantic-release/npm": "^13.1.0",
    "@semantic-release/github": "^12.0.0",
    "@semantic-release/gitlab": "^13.3.0",
    "conventional-changelog-conventionalcommits": "^10.4.0"
  },
  "dependencies": {
    "next": "^16.3.0",
    "react": "^19.2.0",
    "react-dom": "^19.2.0",
    "zod": "^4.5.0",
    "@hookform/resolvers": "^5.9.0",
    "react-hook-form": "^7.87.0"
  }
}
```

**Notes on the pins**

- `eslint` stays on **9.x**: `eslint-plugin-react`, `eslint-plugin-jsx-a11y` and
  `eslint-plugin-import` declare `eslint: ^9` as their peer ceiling. On ESLint 10
  the install fails with `ERESOLVE`.
- `typescript` stays on **5.9**: `typescript-eslint@8` declares
  `typescript: >=4.8.4 <6.1.0`. TypeScript 7 is not supported by the linter yet.
- Of the two VCS-specific semantic-release plugins keep **only the one for your
  provider** (`@semantic-release/github` **or** `@semantic-release/gitlab`),
  matching the `.releaserc.json` the setup generates.
- Angular: replace `eslint-config-next` + the React plugins with
  `angular-eslint@^22.5.0` (peers `eslint: ^9 || ^10`, `typescript-eslint: ^8`).

## ESLint configuration (flat config, extends base)

`eslint.config.mjs` at the project root — it imports the base the setup
distributes (`eslint.config.base.mjs`) and adds the profile rules:

```javascript
// eslint.config.mjs
import nextCoreWebVitals from 'eslint-config-next/core-web-vitals';
import nextTypescript from 'eslint-config-next/typescript';

import base from './eslint.config.base.mjs';

// Named, not anonymous: `import/no-anonymous-default-export` (enabled by
// `eslint-config-next`) flags exporting an array literal directly.
const config = [
  ...base,
  ...nextCoreWebVitals,
  ...nextTypescript,
  {
    files: ['**/*.{ts,tsx}'],
    rules: {
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off',
      'react-hooks/exhaustive-deps': 'warn',
      '@typescript-eslint/no-explicit-any': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
];

export default config;
```

As of `eslint-config-next@16` both entrypoints export **native flat arrays**:
spread them directly, no `FlatCompat`/`@eslint/eslintrc` needed. The same holds
for Angular — `angular-eslint` exports flat configs and spreads the same way.

### `max-lines-per-function` on components

The base config caps functions at 40 lines. A component that trips it is a
component doing more than one thing — split it before reaching for a disable
comment. If a team decides JSX deserves more room, that decision belongs in this
project's `eslint.config.mjs`, as an explicit override with a reason:

```javascript
{
  files: ['**/*.tsx'],
  rules: { 'max-lines-per-function': ['error', { max: 60, skipBlankLines: true, skipComments: true }] },
}
```

## Prettier configuration

The setup copies `.prettierrc.tailwind.json` as `.prettierrc.json`: it is the
variant that declares `prettier-plugin-tailwindcss` (automatic class sorting).
The plugin must be installed, otherwise Prettier exits with an error.

## TypeScript configuration

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": false,
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

## Jest configuration

The config file is **`jest.config.mjs`**, not `.ts`: Jest cannot parse a
TypeScript config on its own and `jest.config.ts` makes it demand `ts-node`
(`Jest: 'ts-node' is required for the TypeScript configuration files`). Native
ESM avoids the extra dependency.

On Next.js go through `next/jest`, which wires up transform and module mapping:

```javascript
// jest.config.mjs
import nextJest from 'next/jest.js';

const createJestConfig = nextJest({ dir: './' });

export default createJestConfig({
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  // Without collectCoverageFrom the threshold is computed only over files the
  // tests touch: a never-imported component lowers nothing and the threshold
  // gates nothing. With the list, a file without tests fails the job.
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.spec.{ts,tsx}',
    '!src/**/*.d.ts',
    // Framework shells, not logic: layout/loading/error carry no unit tests.
    // `page.tsx` and `route.ts` stay in — they are application surface.
    '!src/app/**/{layout,loading,error,not-found,template,default}.tsx',
  ],
  coverageThreshold: {
    global: { lines: 70, functions: 70, branches: 60 },
    // Per-layer thresholds — uncomment each entry once the
    // directory exists. Jest hard-fails with "Coverage data for <path> was not
    // found" on any path or glob that matches nothing, which would break a
    // greenfield on its very first `test:cov`.
    // './src/services/': { lines: 80 },
    // './src/utils/': { lines: 90 },
  },
});
```

`setupFilesAfterEnv` is the only valid key for post-environment setup files:
`setupFilesAfterFramework` and `setupFilesAfterEach` do not exist in Jest and
are silently ignored.

## Tailwind CSS 4

Tailwind 4 is **CSS-first**: there is no `tailwind.config.ts` any more. The
theme is declared in the stylesheet with `@theme`, and the PostCSS plugin is
`@tailwindcss/postcss`.

```css
/* src/app/globals.css */
@import 'tailwindcss';

@theme {
  --color-brand: oklch(0.65 0.2 265);
  --font-sans: 'Inter', sans-serif;
}
```

```javascript
// postcss.config.mjs
export default { plugins: { '@tailwindcss/postcss': {} } };
```

## Specific rules (in addition to the Constitution)

- Use `'use client'` only when necessary — prefer Server Components
- API calls happen in Server Components or Route Handlers, not on the client
- Every form uses `react-hook-form` + Zod resolver
- No `useEffect` for fetching — use `async/await` in Server Components or SWR/TanStack Query
- Next.js 16+: consult the bundled docs in `node_modules/next/dist/docs/` before
  writing Next-specific code (see `nextjs.md`)
