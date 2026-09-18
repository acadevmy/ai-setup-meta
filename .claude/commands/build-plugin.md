Build the Claude Code plugin for a template.

Reads the template's `manifest.json` and produces a self-contained plugin under `dist/`.

## Instructions

1. If the user did not name a template, list the ones available in `templates/` and ask which to use
2. Run the build script:
   ```bash
   bash scripts/build-plugin.sh <template-name>
   ```
3. Check the output in `dist/<template-name>/` and report the summary (skills, agents, hooks)
4. If the build fails, read the error and suggest the fix
