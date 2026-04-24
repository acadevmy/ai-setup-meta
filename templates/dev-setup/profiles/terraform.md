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

## State

Remote state is mandatory. State locking is mandatory. Encryption at rest is mandatory. Local state is forbidden for anything beyond a throwaway experiment.

Pick the backend that matches the team's infrastructure. Common options — none of these are defaults imposed by this profile:

| Backend | State locking | Typical use |
|---|---|---|
| **GitLab managed Terraform state** (`http` backend to GitLab API) | Native, GitLab-managed | Teams already on GitLab — zero extra infra, state lives with the project, permissions inherit from GitLab roles |
| S3-compatible storage (AWS S3, MinIO, Cloudflare R2, Backblaze B2, Hetzner Object Storage, etc.) | S3-native (`use_lockfile = true`, Terraform 1.10+) or the legacy DynamoDB / external lock | Teams already using object storage with the S3 API |
| Azure Blob Storage | Native lease locking | Azure-first teams |
| Google Cloud Storage | Native locking | GCP-first teams |
| Terraform Cloud / HCP Terraform | Native locking + run history | Teams wanting hosted state and plan/apply UX |
| PostgreSQL / Consul / etcd | Backend-specific | On-prem or niche deployments |

### GitLab managed Terraform state — recommended when on GitLab

GitLab hosts Terraform state natively for every project. No external storage, no separate lock resource, no extra IAM to wire up. Access is controlled by the project's GitLab roles (Developer to read, Maintainer to write/lock).

```hcl
# terraform.tf (or backend.tf)
terraform {
  backend "http" {
    # lock_method / unlock_method are REQUIRED for GitLab state locking
    lock_method   = "POST"
    unlock_method = "DELETE"
    retry_wait_min = 5
  }
}
```

All connection details are passed via environment variables at `terraform init` time — **not** hardcoded in the backend block:

- `TF_HTTP_ADDRESS=https://<gitlab-host>/api/v4/projects/<project-id>/terraform/state/<state-name>`
- `TF_HTTP_LOCK_ADDRESS=$TF_HTTP_ADDRESS/lock`
- `TF_HTTP_UNLOCK_ADDRESS=$TF_HTTP_ADDRESS/lock`
- `TF_HTTP_USERNAME=gitlab-ci-token` (in CI) or your GitLab username (locally)
- `TF_HTTP_PASSWORD=$CI_JOB_TOKEN` (in CI) or a personal access token with `api` scope (locally)

In CI this reduces the auth surface to a single `CI_JOB_TOKEN` that GitLab injects automatically — no cloud credentials needed for state. Cloud provider credentials are still required to actually create/destroy cloud resources (see the CI recipes below), but that's a separate concern from state.

### S3-compatible backend — recommended (modern)

Terraform 1.10+ supports state locking native to the S3 API via `use_lockfile = true`. This is the recommended pattern for S3-compatible storage — HashiCorp has deprecated the legacy DynamoDB lock in favor of it.

```hcl
# terraform.tf (or backend.tf)
terraform {
  backend "s3" {
    bucket       = "<your-state-bucket>"
    key          = "<env>/<component>/terraform.tfstate"
    region       = "<region>"                     # e.g. us-east-1, eu-west-1, or your S3-compatible endpoint region
    encrypt      = true
    use_lockfile = true
  }
}
```

For non-AWS S3-compatible backends, add `endpoint` / `skip_credentials_validation` / `skip_metadata_api_check` / `force_path_style` as documented by the provider you're using (MinIO, R2, etc.).

### S3 with DynamoDB lock — legacy (AWS-only)

If the repo already uses an AWS DynamoDB lock table, keep it until you migrate to `use_lockfile`:

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

### Backend security requirements

Regardless of which backend you pick, the storage container must have:

- **Versioning / object history enabled** — recoverability for accidental state corruption.
- **Encryption at rest** — provider's native encryption or a customer-managed key.
- **Private / default-deny access** — no public reads or writes. On AWS S3 specifically that means all four block-public-access flags; on other backends, the equivalent private-by-default posture.
- **Short-lived credentials via OIDC / workload identity federation** — no long-lived access keys in CI secrets. AWS: `aws-actions/configure-aws-credentials` with a role-to-assume; Azure: OIDC to AAD; GCP: Workload Identity Federation; Terraform Cloud: dynamic provider credentials.

### Local/remote "sync"

There is no sync. The backend **is** the state. `terraform init` hydrates `.terraform/` from the backend on a fresh clone; every `plan` and `apply` reads and writes the backend directly. Do not commit `*.tfstate`, do not email it, do not paste it into Slack.

### Bootstrapping

The state storage (bucket / container / database) and any external lock resource must exist **before** `terraform init` can use the backend. Typical options:

1. Manually create the storage + lock resource once, then let all subsequent modules use them as backend.
2. A separate `bootstrap/` Terraform configuration that uses a local backend to create the remote-state resources, then migrates its own state into the remote backend after the first apply.
3. Cloud-native click-ops or a one-off script for the bootstrap only — documented in the repo's README.

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

The plugin does **not** generate a CI workflow for Terraform projects today. Adapt one of the recipes below to the repo's existing pipeline. Both use short-lived credentials via workload identity / OIDC — **do not** store long-lived access keys in CI secrets.

Where cloud credentials are needed (to create/destroy cloud resources — state access is separate), prefer the cloud SDK's **native** OIDC-to-credentials exchange over hand-rolling `aws sts` / equivalent calls:

- **AWS**: set `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` env vars; the AWS SDK exchanges the web-identity token automatically (the same mechanism EKS IRSA uses). No explicit `aws sts assume-role-with-web-identity` call required.
- **Azure**: set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` — the Azure SDK / `azurerm` provider handle the federation.
- **GCP**: use Workload Identity Federation; the Google SDK reads the token via the standard GOOGLE_APPLICATION_CREDENTIALS path.

### GitHub Actions — `.github/workflows/terraform.yml`

Uses `aws-actions/configure-aws-credentials@v4`, which sets the AWS SDK env vars for you (no manual STS call).

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
      - uses: aws-actions/configure-aws-credentials@v4   # sets AWS_* env vars via OIDC
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

### GitLab CI — `.gitlab-ci.yml` job additions

Uses **GitLab managed Terraform state** (no external state backend) and **AWS SDK native OIDC** (no explicit `aws sts` call). The `id_tokens.AWS_TOKEN.aud` value must match the OIDC trust relationship configured on the AWS IAM role.

```yaml
stages:
  - validate
  - apply

variables:
  TF_STATE_NAME: default                                           # one per module/env
  TF_HTTP_ADDRESS: "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${TF_STATE_NAME}"
  TF_HTTP_LOCK_ADDRESS: "${TF_HTTP_ADDRESS}/lock"
  TF_HTTP_UNLOCK_ADDRESS: "${TF_HTTP_ADDRESS}/lock"
  TF_HTTP_USERNAME: "gitlab-ci-token"
  TF_HTTP_PASSWORD: "${CI_JOB_TOKEN}"

.terraform:
  image: hashicorp/terraform:<pin to repo's required_version>
  id_tokens:
    AWS_TOKEN:
      aud: "https://gitlab.com"                                    # must match your AWS IAM role trust policy
  before_script:
    # AWS SDK native OIDC — no explicit `aws sts assume-role-with-web-identity` needed.
    # The SDK reads AWS_WEB_IDENTITY_TOKEN_FILE + AWS_ROLE_ARN and handles the exchange.
    - echo "$AWS_TOKEN" > /tmp/aws_token
    - export AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/aws_token
    - export AWS_ROLE_ARN="${AWS_ROLE_TO_ASSUME}"
    - export AWS_ROLE_SESSION_NAME="gitlab-ci-${CI_JOB_ID}"
    - terraform init

terraform:validate:
  extends: .terraform
  stage: validate
  rules:
    - if: $CI_PIPELINE_SOURCE == 'merge_request_event'
      changes: ['**/*.tf', '**/*.tfvars']
  script:
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
      when: manual                                                 # require human trigger
  script:
    - terraform apply -auto-approve plan.cache
  dependencies: [terraform:validate]
```

**What changed vs. the old pattern**: earlier GitLab + AWS examples (including the official GitLab cloud-services doc) show an explicit `aws sts assume-role-with-web-identity` call followed by exporting `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`. That works, but it hard-codes the token exchange in shell. The SDK-native approach above is shorter, less error-prone, and matches how EKS IRSA and GitHub's `configure-aws-credentials` already work under the hood.

**If Terraform doesn't provision AWS resources** (e.g. you're only managing GitLab resources or on-prem infra), drop the `id_tokens` block and the three AWS env-var exports entirely — you only need the `TF_HTTP_*` vars for state.

### Adapt to your repo

- **Monorepo with multiple modules**: run the validate/plan job per module directory (matrix in GitHub, `parallel:matrix` in GitLab). Give each its own `TF_STATE_NAME` on GitLab-managed state.
- **Per-env pipelines**: key the state name by env (`TF_STATE_NAME: "${CI_ENVIRONMENT_NAME}"`) and gate apply per env.
- **Plan output posted to MR**: GitLab has a first-class Terraform MR widget. See [docs.gitlab.com/ci/terraform](https://docs.gitlab.com/ci/terraform) for the `terraform plan -json | gitlab-terraform-report` integration.
- **Non-AWS clouds**: replace the `AWS_*` env-var block with the Azure (`AZURE_FEDERATED_TOKEN_FILE` / `AZURE_CLIENT_ID` / `AZURE_TENANT_ID`) or GCP (Workload Identity Federation credentials file) equivalents.

## Working with legacy repositories

A legacy Terraform repository typically carries some combination of: an old pinned Terraform version (pre-1.x or very early 1.x), deprecated provider-block syntax, DynamoDB-based state locking that predates `use_lockfile`, per-OS workarounds for older providers (e.g. Rosetta on macOS ARM64 for the archived `template` provider), hand-rolled module structure, or missing `description` / `type` on variables. Don't treat the legacy state as a reference for new work — the conventions above describe current best practice.

When touching a legacy module:

1. Follow the repo's pinned Terraform version (`required_version`) — **do not silently upgrade it** in an unrelated PR.
2. If you're adding a new module in the repo, write it against the conventions above and note in the MR description that the new module deviates from the legacy style on purpose.
3. If you're modifying an existing module, apply conventions only to the parts you're already touching. Do not restyle or re-split files that are outside your change set.
4. Track larger upgrades (TF version bump, backend migration from DynamoDB → S3-native locking, provider block rewrite) as separate PRs with their own review.

## Relationship to CONSTITUTION §X

This profile documents **how** to write Terraform code. CONSTITUTION §X codifies the non-negotiable rules (provider pinning, remote state, no hardcoded creds, CI-gated workflow, legacy grandfather clause, etc.). Read §X first — the profile is the "how" layer on top of §X's "what".

---

*Generated by: ai-base-setup*
