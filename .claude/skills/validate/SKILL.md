---
name: validate
description: Pre-release validation of the plugin — manifest references and static checks on skill and workflow quality. Use when you need to verify the repo before a PR or a release, or when CI reports a finding.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

# /project:validate

Runs the meta-repo's two static gates. They are the same commands CI runs
(`.github/workflows/ci.yml`, job `static-checks`): if they pass here, they pass there.

## Procedure

1. Manifest references — every declared file exists:

   ```bash
   bash scripts/validate-setup-urls.sh
   ```

2. Static checks on skill, workflow and documentation quality (16 checks, see the
   script header):

   ```bash
   bash scripts/validate-plugin.sh --fail-on-stale
   ```

3. Report the outcome, keeping the three output categories apart:
   - **new findings** → to fix in this PR; they are the reason the gate failed;
   - **baselined findings** → known debt recorded in `scripts/validate-baseline.txt`;
   - **stale baseline** → defects that have been fixed: remove the matching lines from
     the baseline in the same PR that fixed them.

## Useful options

- `--strict` — ignore the baseline and show the repo's real state.
- `--json` — machine-readable output (UPPER_SNAKE keys) for other scripts.
- `--update-baseline` — rewrite the baseline. **Only** for debt that has been accepted
  explicitly: the baseline shrinks with the PRs of the chain, it does not grow.

## Rules

- Do not widen the baseline to make CI pass: a new finding gets fixed.
- If a check produces a false positive, the fix belongs in the script, not in the
  baseline.
