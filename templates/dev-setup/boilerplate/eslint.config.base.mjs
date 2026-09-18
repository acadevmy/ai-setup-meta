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
      // Zero `any`: use `unknown` + explicit narrowing.
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // No forgotten `console.log` in a commit.
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      // Errors are not swallowed: no empty blocks.
      'no-empty': ['error', { allowEmptyCatch: false }],
      // A function does one thing. 40 lines is where "one thing" stops being
      // plausible; blank lines and comments do not count against it.
      'max-lines-per-function': [
        'error',
        { max: 40, skipBlankLines: true, skipComments: true, IIFEs: true },
      ],
      // Naming, so the convention is a failing job rather than a review note.
      // `variable` allows PascalCase because a React component declared as a
      // const is one, and UPPER_CASE for module constants.
      // Object and type properties are exempt: their shape is dictated by the
      // API or the schema on the other side of the wire.
      '@typescript-eslint/naming-convention': [
        'error',
        {
          selector: 'default',
          format: ['camelCase'],
          leadingUnderscore: 'allow',
          trailingUnderscore: 'allow',
        },
        {
          selector: 'variable',
          format: ['camelCase', 'UPPER_CASE', 'PascalCase'],
          leadingUnderscore: 'allow',
        },
        { selector: 'parameter', format: ['camelCase'], leadingUnderscore: 'allow' },
        { selector: 'typeLike', format: ['PascalCase'] },
        { selector: 'enumMember', format: ['PascalCase', 'UPPER_CASE'] },
        { selector: ['objectLiteralProperty', 'typeProperty'], format: null },
        { selector: 'import', format: null },
      ],
    },
  },

  // Config files run in Node: Node globals, console allowed, and a config
  // object is one long literal — the function-length rule does not apply.
  {
    files: ['**/*.config.{js,mjs,cjs,ts,mts}', '**/*.cjs', 'scripts/**/*.{js,mjs,ts}'],
    languageOptions: { globals: globals.node },
    rules: { 'no-console': 'off', 'max-lines-per-function': 'off' },
  },

  // Tests get the Jest globals. `describe` bodies are containers, not
  // functions with logic in them, so the length limit would only measure how
  // many cases a suite covers.
  {
    files: ['**/*.{spec,test}.{ts,tsx,js,jsx}', '**/__tests__/**/*.{ts,tsx,js,jsx}'],
    languageOptions: { globals: { ...globals.jest, ...globals.node } },
    rules: { 'max-lines-per-function': 'off' },
  },
);
