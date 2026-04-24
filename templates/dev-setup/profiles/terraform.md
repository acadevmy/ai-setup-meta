# Profile: Infrastructure as Code (Terraform)

Stack: **Terraform** (HCL) — follow the repository's pinned version; do not auto-upgrade.
Validation: `terraform validate` (built-in), optionally `tflint`, `tfsec` / `checkov` for security scanning.
Formatting: `terraform fmt` (built-in).
Source of truth for conventions: [HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style).

> **Legacy repositories**: existing modules following older conventions (e.g. deprecated provider-block syntax, older Terraform minor versions) are **grandfathered**. Apply the conventions below to **new modules** and to **files you are already touching**. Do not bulk-refactor a legacy repository in an unrelated PR (Boy Scout Rule, scoped — see `CONSTITUTION.md §X` rule 8).

## Required tooling

| Tool | Purpose | Install hint |
|---|---|---|
| `terraform` CLI | core — follow repo's `required_version` | `brew install terraform` or `tfenv` for multiple versions |
| `tflint` (optional) | static analysis beyond `validate` | `brew install tflint` |
| `tfsec` or `checkov` (optional) | security scanning | `brew install tfsec` / `pipx install checkov` |
| `terraform-docs` (optional) | auto-generate module docs from variables + outputs | `brew install terraform-docs` |

> None of the optional tools are mandated by CONSTITUTION §X. Add them to the team's CI gradually.

## File layout (HashiCorp style guide)

One module = one directory. Inside each module, split configuration into dedicated files:

| File | Contents |
|---|---|
| `terraform.tf` | `terraform { required_version, required_providers }` block — version constraints live here |
| `providers.tf` | `provider "<name>" { ... }` configuration blocks |
| `backend.tf` | `terraform { backend "<name>" { ... } }` — state backend (often co-located in `terraform.tf` on small modules) |
| `variables.tf` | `variable` blocks with `type` and `description` mandatory |
| `main.tf` | `resource` and `data` blocks — the module's primary content |
| `locals.tf` | `locals { ... }` blocks for computed values |
| `outputs.tf` | `output` blocks with `description` mandatory |
| `override.tf` | temporary overrides (rare; discouraged — prefer variables) |

For trivial modules a single `main.tf` is acceptable. Split as soon as the module grows past ~100 lines or introduces multiple resource types.

## Naming conventions

- **snake_case** for resource identifiers, variables, outputs, locals, modules. Never camelCase or kebab-case.
- **Do not repeat the resource type** in the identifier. `resource "aws_instance" "web"` ✅, not `resource "aws_instance" "web_instance"` ❌.
- For resources that represent a single logical thing, use `this`: `resource "aws_s3_bucket" "this"`.
- Module directory names: snake_case (`modules/vpc_peering/`, not `modules/vpcPeering/`).

## Dependency management

- `required_providers` with **explicit version constraints** — pin to a known-good minor. Avoid loose `>= X` or unbounded `~>` at the major level that would let a breaking upgrade slip in silently.
- `required_version` for Terraform itself pinned to the repo's target. Mismatch triggers an error on `terraform init`.
- `.terraform.lock.hcl` is **committed to VCS**. It records exact provider versions + checksums; CI `terraform init` uses it to reproduce the same provider set across machines.
- `.terraform/` (local plugin cache + working files) and `*.tfstate*` are **gitignored**.

## State (S3 default for AWS, weebora-aligned)

Remote state is mandatory. State locking is mandatory. Local state is forbidden for anything beyond a throwaway experiment.

### S3 backend — recommended (modern)

Terraform 1.10+ supports S3-native locking via `use_lockfile = true`. **Prefer this over DynamoDB** — HashiCorp marked DynamoDB locking deprecated.

```hcl
# terraform.tf (or backend.tf)
terraform {
  backend "s3" {
    bucket       = "<your-state-bucket>"
    key          = "<env>/<component>/terraform.tfstate"
    region       = "<aws-region>"
    encrypt      = true
    use_lockfile = true
  }
}
```

### S3 backend — legacy (DynamoDB lock)

If the repo is older and already uses a DynamoDB lock table, keep it until you migrate:

```hcl
terraform {
  backend "s3" {
    bucket         = "<your-state-bucket>"
    key            = "<env>/<component>/terraform.tfstate"
    region         = "<aws-region>"
    encrypt        = true
    dynamodb_table = "<your-lock-table>"
  }
}
```

### State bucket requirements

Whatever backend you use, the bucket must have:

- **Versioning enabled** — recoverability for accidental state corruption.
- **Encryption at rest** (SSE-S3 or SSE-KMS).
- **Public access blocked** (all four block-public-access flags on).
- **Access control via IAM role** — ideally assumed via OIDC in CI, short-lived credentials. No long-lived access keys in CI secrets.

### Local/remote "sync"

There is no sync. The backend **is** the state. `terraform init` hydrates `.terraform/` from the backend on a fresh clone; every `plan` and `apply` reads and writes the backend directly. Do not commit `*.tfstate`, do not email it, do not paste it into Slack.

### Alternative backends

Azure Blob Storage + lease locking, GCS, and Terraform Cloud are acceptable for non-AWS stacks. Same rules apply: remote, locked, encrypted, private.

### Bootstrapping

The S3 bucket and DynamoDB lock table (if used) must exist **before** `terraform init` can use them. Typical options:

1. Manually create the bucket + table once, then let all subsequent modules use them as backend.
2. A separate `bootstrap/` Terraform configuration that uses a local backend to create the remote-state resources, then migrate its own state into S3 after the first apply.
3. CloudFormation / click-ops for the bootstrap only — documented in the repo's README.

## Module structure

- **Root modules** are the entry point per environment (`dev/`, `staging/`, `prod/`). They configure providers, declare the backend, and call reusable modules.
- **Reusable modules** live in `modules/<name>/` inside the repo, or in an external registry (Terraform Registry, git URL). Each reusable module has its own `variables.tf` + `outputs.tf` + `main.tf` split.
- **Variable contracts**: every `variable` block declares `type` and `description`. Use `validation` for non-trivial constraints. Use `sensitive = true` for secrets.
- **Output contracts**: every `output` block declares `description`. Mark `sensitive = true` when appropriate.

## Environment separation

Pick **one** model per repo and stick to it. Do not mix.

- **Directory per environment** (`environments/dev/`, `environments/staging/`, `environments/prod/`) — each with its own root module, backend config, and tfvars. Most explicit, recommended for multi-env production stacks.
- **Workspace per environment** (`terraform workspace new prod`) — single root module, state keyed by workspace. Simpler, but harder to read at a glance and easy to mis-target.

Never run `terraform apply` against production without confirming the workspace / directory you're in. CONSTITUTION §X rule 7 requires explicit human go for destructive ops and prod changes.

## Quality gate

Before committing any change:

```bash
terraform fmt -check -recursive    # formatting
terraform validate                  # schema + provider validation
# optionally
tflint                             # extra static checks
tfsec .                            # security findings
```

In CI, the same three commands run on every PR/MR (plus `terraform plan`). `terraform apply` is never automatic — see the CI recipes below.

## CI/CD recipes (reference text, not auto-generated)

The plugin does **not** generate a CI workflow for Terraform projects today. Adapt one of the recipes below to the repo's existing pipeline. Both assume the runner obtains AWS credentials via OIDC (GitHub: `aws-actions/configure-aws-credentials@v4` with `role-to-assume`; GitLab: `id_tokens` + `aws sts assume-role-with-web-identity`). **Do not** store long-lived access keys in CI secrets.

### GitHub Actions — `.github/workflows/terraform.yml`

```yaml
name: Terraform

on:
  pull_request:
    paths: ['**/*.tf', '**/*.tfvars']
  push:
    branches: [main]
    paths: ['**/*.tf', '**/*.tfvars']

permissions:
  contents: read
  id-token: write          # for OIDC
  pull-requests: write     # to comment the plan on the PR

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: <pin to repo's required_version>
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: <region>
      - run: terraform fmt -check -recursive
      - run: terraform init
      - run: terraform validate
      - name: Plan
        id: plan
        run: terraform plan -no-color -out=plan.bin
      - name: Post plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('plan.bin', 'utf8').slice(0, 60000);
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '```\n' + plan + '\n```'
            });

  apply:
    needs: validate
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production    # environment protection rule = manual approval
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: <region>
      - run: terraform init
      - run: terraform apply -auto-approve
```

### GitLab CI — job additions to an existing `.gitlab-ci.yml`

```yaml
stages:
  - validate
  - apply

.terraform:
  image: hashicorp/terraform:<pin to repo's required_version>
  before_script:
    - terraform init

terraform:validate:
  extends: .terraform
  stage: validate
  rules:
    - if: $CI_PIPELINE_SOURCE == 'merge_request_event'
      changes: ['**/*.tf', '**/*.tfvars']
  id_tokens:
    AWS_TOKEN:
      aud: https://gitlab.com
  script:
    - aws sts assume-role-with-web-identity
        --role-arn "$AWS_ROLE_TO_ASSUME"
        --role-session-name "gitlab-ci-$CI_JOB_ID"
        --web-identity-token "$AWS_TOKEN" > /tmp/creds.json
    - export AWS_ACCESS_KEY_ID=$(jq -r .Credentials.AccessKeyId /tmp/creds.json)
    - export AWS_SECRET_ACCESS_KEY=$(jq -r .Credentials.SecretAccessKey /tmp/creds.json)
    - export AWS_SESSION_TOKEN=$(jq -r .Credentials.SessionToken /tmp/creds.json)
    - terraform fmt -check -recursive
    - terraform validate
    - terraform plan -out=plan.cache
  artifacts:
    paths: [plan.cache]
    expire_in: 1 week

terraform:apply:
  extends: .terraform
  stage: apply
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes: ['**/*.tf', '**/*.tfvars']
      when: manual             # require human trigger
  script:
    - terraform apply -auto-approve plan.cache
  dependencies: [terraform:validate]
```

### Adapt to your repo

- **Monorepo with multiple modules**: run the validate/plan job per module directory (matrix in GitHub, `parallel:matrix` in GitLab).
- **Per-env pipelines**: add environment to the cache key (`key = "<env>/<component>/terraform.tfstate"`) and gate apply per env.
- **Plan output posted to MR**: GitLab has a built-in `$CI_MERGE_REQUEST_IID` and Terraform integration (`terraform plan -json | ...` piped to the merge-request widget).

## Working with legacy repositories

`iac_weebora` is an example of a legacy Terraform repo: pinned to Terraform 1.2.0 (2022), uses deprecated provider-block syntax, requires a Rosetta workaround on macOS ARM64 for the `template` provider. Don't treat it as a reference — the conventions above describe current best practice.

When touching a legacy module:

1. Follow the repo's pinned Terraform version (`required_version`) — **do not silently upgrade it** in an unrelated PR.
2. If you're adding a new module in the repo, write it against the conventions above and note in the MR description that the new module deviates from the legacy style on purpose.
3. If you're modifying an existing module, apply conventions only to the parts you're already touching. Do not restyle or re-split files that are outside your change set.
4. Track larger upgrades (TF version bump, backend migration from DynamoDB → S3-native locking, provider block rewrite) as separate PRs with their own review.

## Relationship to CONSTITUTION §X

This profile documents **how** to write Terraform code. CONSTITUTION §X codifies the non-negotiable rules (provider pinning, remote state, no hardcoded creds, CI-gated workflow, legacy grandfather clause, etc.). Read §X first — the profile is the "how" layer on top of §X's "what".

---

*Generated by: ai-base-setup*
