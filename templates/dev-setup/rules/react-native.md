---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React Native (Expo)

The project is on the **Expo managed workflow**. Ejecting to the bare workflow is
a decision with a written reason behind it, not something that happens because a
package's README suggested it.

Navigation goes through **Expo Router**: a screen is a file under `app/`, and the
route is its path. Adding a navigator by hand alongside it produces two sources
of truth for the same navigation state.

Network access lives in a custom hook or in TanStack Query, never inside a
component body. Components in React Native are still React components — the
composition and typed-props rules do not change because the renderer does.

Anything platform-specific (`Platform.OS` branches, `.ios.tsx` / `.android.tsx`
files) is worth a comment saying which platform behaviour forced it.
