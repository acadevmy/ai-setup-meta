---
paths:
  - "**/*.vue"
---

# Vue 3 / Nuxt 3 components

`<script setup lang="ts">` is the only form used here — no Options API. Props and
emits are typed through the generic call:

```vue
<script setup lang="ts">
const props = defineProps<{ userId: string; compact?: boolean }>();
const emit = defineEmits<{ select: [id: string] }>();
</script>
```

Templates render. Anything with a decision in it moves to a composable under
`composables/useXxx.ts`.

Component file names are multi-word (`UserCard.vue`, not `Card.vue`) so they
cannot collide with an HTML element.

## Data fetching

Use `useFetch` / `useAsyncData` / `$fetch`. Fetching inside `onMounted` or a
`watch` skips Nuxt's dedup and payload transfer, so the request runs twice — once
on the server, once again in the browser. Pass an explicit `key` whenever the
call is conditional or parameterised, otherwise the auto-generated key collides.

External backends are reached through `server/api/*`, which is where the Zod
validation of the response lives. A component never talks to a third-party API
directly.

## State

Shared state lives in Pinia stores (`stores/*.ts`, registered via `@pinia/nuxt`).
`provide`/`inject` is for dependency passing, not for application state shared
between distant components. Getters and actions declare their return type.

## SSR and auto-imports

SSR is the default: anything touching `window`, `document`, `localStorage` or a
browser-only library is gated behind `import.meta.client` or `<ClientOnly>`.

Nuxt auto-imports are on — `ref`, `computed`, `useRoute`, `useFetch`,
`navigateTo` and friends are already in scope. Importing them by hand is noise
and, for some of them, a different binding. Tests keep the auto-imports working
through `@nuxt/test-utils` (`environment: 'nuxt'` in Vitest).
