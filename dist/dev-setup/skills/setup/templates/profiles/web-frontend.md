# Profile: Web Frontend

Stack: **Next.js 14+**, **Angular 17+**, **React 18+**
UI: ShadCN/UI + Tailwind CSS
Validation: Zod
Testing: Jest + Testing Library

## Required dependencies

```json
{
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0",
    "eslint": "^8.57.0",
    "eslint-config-next": "^14.0.0",
    "eslint-plugin-react": "^7.34.0",
    "eslint-plugin-react-hooks": "^4.6.0",
    "prettier": "^3.2.0",
    "prettier-plugin-tailwindcss": "^0.5.0",
    "@testing-library/react": "^15.0.0",
    "@testing-library/jest-dom": "^6.4.0",
    "@testing-library/user-event": "^14.5.0",
    "jest": "^29.7.0",
    "jest-environment-jsdom": "^29.7.0",
    "semantic-release": "^24.0.0",
    "@semantic-release/changelog": "^6.0.3",
    "@semantic-release/git": "^10.0.1",
    "@semantic-release/github": "^10.0.0",
    "conventional-changelog-conventionalcommits": "^8.0.0"
  },
  "dependencies": {
    "zod": "^3.23.0",
    "@hookform/resolvers": "^3.3.0",
    "react-hook-form": "^7.51.0"
  }
}
```

## ESLint configuration (extends base)

```json
{
  "extends": [
    "./.eslintrc.base.json",
    "next/core-web-vitals",
    "plugin:react/recommended",
    "plugin:react-hooks/recommended"
  ],
  "rules": {
    "react/react-in-jsx-scope": "off",
    "react/prop-types": "off",
    "react-hooks/exhaustive-deps": "warn",
    "@typescript-eslint/no-explicit-any": "error",
    "no-console": ["warn", { "allow": ["warn", "error"] }]
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

```typescript
// jest.config.ts
export default {
  testEnvironment: 'jsdom',
  setupFilesAfterFramework: ['<rootDir>/jest.setup.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  coverageThreshold: {
    global: { lines: 70, functions: 70, branches: 60 },
    './src/services/': { lines: 80 },
    './src/utils/': { lines: 90 },
  },
};
```

## Additional slash commands

- `/project:new-component` — scaffolds a ShadCN/Tailwind component with tests
- `/project:new-page` — scaffolds a Next.js page with layout and metadata
- `/project:review-a11y` — reviews accessibility of the current component

## Specific rules (in addition to the Constitution)

- Use `'use client'` only when necessary — prefer Server Components
- API calls happen in Server Components or Route Handlers, not on the client
- Every form uses `react-hook-form` + Zod resolver
- No `useEffect` for fetching — use `async/await` in Server Components or SWR/TanStack Query
