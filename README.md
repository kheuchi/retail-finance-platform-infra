# Retail Finance Platform Infrastructure

Terraform infrastructure for the AWS and Databricks retail-finance platform.

This repository owns deployable cloud infrastructure only. Application code,
data transformations, ML models, and agent implementations belong in separate
repositories listed by the control plane's `REPOSITORIES.md`.

## Current contents

- `bootstrap/`: remote Terraform state, AWS Budget alerts, and the IAM account
  password policy.
- `docs/architecture/`: infrastructure-specific architecture decisions.
- `.github/workflows/ci.yml`: Terraform checks, advisory Checkov, and automated
  semantic releases.

No Terraform configuration has been applied to AWS yet.

## Safety rule

Run `terraform plan` and review persistent-cost resources before every apply.
Never commit credentials, generated plans, state files, or local variable files.

Use Conventional Commits because semantic-release derives versions from commit
history. See `docs/ci-cd.md` for pipeline behavior and GitHub settings.
