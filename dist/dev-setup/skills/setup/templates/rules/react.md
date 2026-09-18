---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React components

A component renders one thing. Props are typed — no `any`, no casts on the props
object. Business logic lives in a hook, a server action or a service; the
component decides what to show, not what is true.

When a component grows a second responsibility, split it before adding the
third. The usual seam is "what changes independently": the parts that re-render
for different reasons belong in different components.

## Design system

The project builds on **ShadCN/UI** rather than hand-rolled primitives. ShadCN
components are copied into the repo, so they are yours to edit — but edits go in
the customization layer (a wrapper, a variant, a `cn()` override), not in the
generated file, which the CLI overwrites on the next `add`.

## Tailwind

Tailwind 4 is CSS-first: **there is no `tailwind.config.ts`**. The theme lives in
an `@theme` block in the entry stylesheet, and the PostCSS plugin is
`@tailwindcss/postcss`.

```css
/* src/app/globals.css */
@import 'tailwindcss';

@theme {
  --color-brand: oklch(0.65 0.2 265);
  --font-sans: 'Inter', sans-serif;
}
```

Tokens are declared once there and used as utilities. Variants and themes are
declared alongside them, never inline in the markup, and a custom CSS file is a
last resort — not the first place to put a colour.

On a project still on Tailwind 3 the same rule points at `tailwind.config.ts`
instead; check which major the project is on before editing theme tokens.
