---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
---

# Terraform / HCL

These follow the
[HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style);
the `terraform` stack profile documents the *how*, this is the *what*.

## Versions are pinned

`required_providers` declares every provider with an explicit version
constraint, and `required_version` pins the Terraform core the repository
targets. A bare `>=`, or a `~>` loose at the major level, lets a breaking
provider release land on the next `init` with no diff to review.

## Credentials never appear in a `.tf`

No AWS keys, API tokens, service-account JSON or database passwords in the
configuration. They come from environment variables, CI secrets, a cloud
identity provider (OIDC / assume-role), or a `data` source reading a secret
store. Values that are secret carry `sensitive = true` so they stay out of the
plan output.

## State is remote, locked and encrypted

Local state is for a throwaway experiment and nothing else. Pick the backend
that matches the infrastructure: S3-compatible storage with native locking
(`use_lockfile = true`, Terraform 1.10+), Azure Blob with lease locking, GCS,
HCP Terraform. DynamoDB-based locking on S3 is legacy and HashiCorp has
deprecated it — migrate opportunistically.

The backend **is** the state; there is no local copy to sync. `*.tfstate*` is
never committed and never shared out of band. `.terraform.lock.hcl` **is**
committed — checksum drift between machines is a bug, not a convenience.

## Gates

`terraform fmt -check -recursive` and `terraform validate` pass before a commit
lands, and CI runs the same two plus `terraform plan` on every change to a `.tf`.
The plan output is posted on the PR/MR so a human reads the diff before an apply.
`terraform apply` never runs automatically on merge: it is a manually triggered
job, or a protected branch with a required review.

## Destructive operations need a human go-ahead

`terraform destroy`, `terraform state rm`, `terraform import` against production,
and any plan showing **resource deletions** against production stop and ask, in
the conversation, every time. This is not covered by having run the plan.

## Layout and naming

One module per directory. Configuration splits across `terraform.tf`,
`providers.tf`, `backend.tf`, `variables.tf`, `main.tf`, `locals.tf`,
`outputs.tf` — omitting the ones that would be empty.

Resource, variable, output, local and module identifiers are `snake_case`, and
they do not repeat the resource type: `aws_instance.web`, not
`aws_instance.web_instance`. A module's single primary resource is called `this`.
Every `variable` has a `type` and a `description`; every `output` has a
`description`.

## Legacy modules

Modules that predate these conventions are grandfathered. Apply the rules above
to new modules and to files you are already modifying; do not bulk-refactor a
legacy repository as a side effect of an unrelated change. A version bump, a
backend migration or a provider-block rewrite is its own change with its own
review.
