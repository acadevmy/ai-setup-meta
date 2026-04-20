# Profile: Web Frontend — Nuxt 3 / Vue 3

Stack: **Nuxt 3.13+**, **Vue 3.4+**, **Nitro** server engine
UI: shadcn-vue + Tailwind CSS
Validation: Zod (+ VeeValidate resolver for forms)
State: Pinia
Testing: Vitest + `@vue/test-utils` + `@nuxt/test-utils`

## Required dependencies

```json
{
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0",
    "eslint": "^8.57.0",
    "@nuxt/eslint-config": "^0.5.0",
    "eslint-plugin-vue": "^9.27.0",
    "prettier": "^3.2.0",
    "prettier-plugin-tailwindcss": "^0.5.0",
    "@vue/test-utils": "^2.4.0",
    "@nuxt/test-utils": "^3.14.0",
    "vitest": "^2.0.0",
    "@vitest/coverage-v8": "^2.0.0",
    "happy-dom": "^15.0.0",
    "@nuxt/eslint": "^0.5.0",
    "@nuxtjs/tailwindcss": "^6.12.0",
    "semantic-release": "^24.0.0",
    "@semantic-release/changelog": "^6.0.3",
    "@semantic-release/git": "^10.0.1",
    "@semantic-release/github": "^10.0.0",
    "conventional-changelog-conventionalcommits": "^8.0.0"
  },
  "dependencies": {
    "nuxt": "^3.13.0",
    "vue": "^3.4.0",
    "vue-router": "^4.4.0",
    "@pinia/nuxt": "^0.5.0",
    "pinia": "^2.2.0",
    "zod": "^3.23.0",
    "vee-validate": "^4.13.0",
    "@vee-validate/zod": "^4.13.0"
  }
}
```

## ESLint configuration (extends base)

```json
{
  "extends": [
    "./.eslintrc.base.json",
    "@nuxt/eslint-config",
    "plugin:vue/vue3-recommended"
  ],
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "vue/multi-word-component-names": "error",
    "vue/component-api-style": ["error", ["script-setup"]],
    "vue/define-macros-order": ["error", {
      "order": ["defineOptions", "defineProps", "defineEmits", "defineSlots"]
    }],
    "no-console": ["warn", { "allow": ["warn", "error"] }]
  }
}
```

## TypeScript configuration

`tsconfig.json` extends the auto-generated `.nuxt/tsconfig.json`:

```json
{
  "extends": "./.nuxt/tsconfig.json",
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "target": "ES2022",
    "paths": {
      "~/*": ["./*"],
      "@/*": ["./*"]
    }
  }
}
```

## Vitest configuration

```typescript
// vitest.config.ts
import { defineVitestConfig } from '@nuxt/test-utils/config';

export default defineVitestConfig({
  test: {
    environment: 'nuxt',
    globals: true,
    coverage: {
      provider: 'v8',
      thresholds: {
        lines: 70,
        functions: 70,
        branches: 60,
      },
    },
  },
});
```

## Nuxt folder structure (mandatory)

```
./
├── pages/              # file-based routing
├── layouts/
├── components/         # auto-imported
│   └── ui/             # shadcn-vue components
├── composables/        # auto-imported (useXxx.ts)
├── stores/             # Pinia stores
├── server/
│   ├── api/            # server routes (h3)
│   ├── middleware/
│   └── utils/
├── schemas/            # Zod schemas (shared client/server)
├── types/
├── utils/              # auto-imported
├── assets/
├── public/
└── nuxt.config.ts
```

## Additional slash commands

- `/project:new-page` — scaffolds a Nuxt page with layout, `definePageMeta`, and test
- `/project:new-component` — scaffolds a shadcn-vue/Tailwind component with `<script setup>` and test
- `/project:new-composable` — scaffolds a typed composable under `composables/`
- `/project:new-server-route` — scaffolds a `server/api/*` route with Zod validation
- `/project:review-a11y` — reviews accessibility of the current component

## Specific rules (in addition to the Constitution)

- `<script setup lang="ts">` è obbligatorio — niente Options API
- Data fetching tramite `useFetch` / `useAsyncData` — mai dentro `onMounted` o in `watch`
- Stato globale in store Pinia — no `provide/inject` ad-hoc per state condiviso
- Ogni form usa `vee-validate` con Zod resolver; schema condiviso tra client e `server/api`
- Le chiamate a backend esterni passano da `server/api/*` (proxy) — no fetch diretti al BE dai componenti
- Auto-imports di Nuxt attivi: non importare manualmente `ref`, `computed`, `useRoute`, `useFetch`, ecc.
- SSR by default: verificare l'uso di API browser-only tramite `import.meta.client` / `<ClientOnly>`
- Componenti multi-word (`UserCard.vue`, non `Card.vue`) per evitare conflitti con elementi HTML
