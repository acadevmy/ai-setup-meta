// Shared ESLint config in flat config format (ESLint 9+).
// Stack profiles import it from `eslint.config.mjs` and extend it.
//
// Why ESLint 9 and not 10: `eslint-plugin-react`, `eslint-plugin-import` and
// `eslint-plugin-jsx-a11y` still declare `eslint: ^9` as their peer ceiling, so
// installing a frontend project on ESLint 10 fails with ERESOLVE. Once those
// plugins widen the peer range, raise the pin in the profiles.
import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  // Never linted: build output, dependencies, coverage.
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/build/**',
      '**/coverage/**',
      '**/.next/**',
      '**/out/**',
      '**/*.min.js',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    files: ['**/*.{ts,tsx,mts,cts}'],
    languageOptions: {
      parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
    },
    rules: {
      // CONSTITUTION §2 — zero `any`: use `unknown` + explicit narrowing.
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // CONSTITUTION §17 — no forgotten `console.log` in a commit.
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      // CONSTITUTION §3 — errors are not swallowed: no empty blocks.
      'no-empty': ['error', { allowEmptyCatch: false }],
    },
  },

  // Config files run in Node: Node globals, and console is allowed.
  {
    files: ['**/*.config.{js,mjs,cjs,ts,mts}', '**/*.cjs', 'scripts/**/*.{js,mjs,ts}'],
    languageOptions: { globals: globals.node },
    rules: { 'no-console': 'off' },
  },

  // Tests get the Jest globals.
  {
    files: ['**/*.{spec,test}.{ts,tsx,js,jsx}', '**/__tests__/**/*.{ts,tsx,js,jsx}'],
    languageOptions: { globals: { ...globals.jest, ...globals.node } },
  },
);
