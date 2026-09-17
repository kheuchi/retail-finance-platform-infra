# Retail Finance Platform Infrastructure

Terraform infrastructure for the AWS and Databricks retail-finance platform.

This repository owns deployable cloud infrastructure only. Application code,
data transformations, ML models, and agent implementations belong in separate
repositories listed by the control plane's `REPOSITORIES.md`.

## Current contents

- `bootstrap/`: remote Terraform state, AWS Budget alerts, and the IAM account
  password policy.
- `docs/architecture/`: infrastructure-specific architecture decisions, including
  the costed Frankfurt network, audit and Databricks foundation proposal.
- `docs/security/checkov-exceptions.md`: every accepted policy-scan exception, with
  its residual risk and the trigger that would make us revisit it.
- `docs/runbooks/break-glass.md`: what to do when the deployment pipeline cannot
  repair itself and a human must intervene directly.
- `docs/architecture/databricks-prerequisites.md`: what the lakehouse needs from
  AWS, what is already built, and the one value still required to finish it.
- `.github/workflows/ci.yml`: Terraform checks, advisory Checkov, and automated
  semantic releases.
- `.github/workflows/deploy-bootstrap.yml`: manually gated, OIDC-authenticated
  bootstrap deployment from `main`.

The bootstrap stack is deployed in `eu-central-1` and uses a protected remote
backend. GitHub plans and deployments use temporary OIDC role sessions; no AWS
access keys are stored in GitHub.

## Safety rule

Run `terraform plan` and review persistent-cost resources before every apply.
Never commit credentials, generated plans, state files, or local variable files.

Use Conventional Commits because semantic-release derives versions from commit
history. See `docs/ci-cd.md` for pipeline behavior and GitHub settings.
