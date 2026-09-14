# Infrastructure Repository Context

## Purpose

Provision the cost-controlled AWS and Databricks foundation for the retail finance
Data, ML and Agentic AI platform. This file is agent-agnostic and supplements the
program-level context in the control-plane repository.

## Ownership boundary

This repository owns:

- Terraform bootstrap and remote state;
- AWS identity roles and resource policies;
- audit, security, encryption, storage, networking and cost controls;
- Databricks account/workspace cloud infrastructure and Unity Catalog foundations;
- infrastructure CI/CD and policy-as-code.

It does not own application source code, data transformations, ML training code,
agent prompts/tools, dashboards, or business documentation.

## Current state

- Terraform 1.14.6 verified locally.
- HashiCorp AWS provider 6.64.0 selected in the dependency lock file.
- Bootstrap code passes formatting and validation.
- No Terraform plan or apply has run.
- No AWS resources have been created by this repository.
- Approved primary region: `eu-west-3` (Paris).
- Monthly personal-spend ceiling: USD 50.
- AWS Organizations and Control Tower must not be enabled while preserving the
  current AWS Free plan credits.

## Operating rules

1. Use the `retail-platform-admin` AWS CLI profile; never use root.
2. Never store credentials or state in Git.
3. Review plans before applies and require an explicit human gate for production.
4. Avoid persistent hourly resources unless their cost is documented and approved.
5. Do not use the default VPC for workloads.
6. Keep reusable modules separate from environment compositions.
7. Record every apply, destroy, exception and residual cost in this file.

## Progress

### 2026-09-14

- Created the bootstrap stack for secure S3 state, a USD 50 monthly budget, and the
  IAM account password policy.
- Initialized providers and passed `terraform fmt -check` and `terraform validate`.
- Split infrastructure ownership out of the control-plane repository.
- Reviewed the first bootstrap plan: 9 additions, 0 changes, 0 deletions.
- Changed budget accounting to measure gross usage before credits and refunds.
- AWS cannot expose the standalone account's primary email through the available
  API. A real locally configured recipient is used from ignored Terraform variables;
  no email address is stored in Git.
- Applied the reviewed bootstrap plan: 9 resources added, 0 changed, 0 destroyed.
- Direct S3 backend initialization cannot consume AWS CLI `login_session` in
  Terraform 1.14. Added a documented helper that exports the existing short-lived
  session into process-only environment credentials for state migration.
- Migrated bootstrap state to the encrypted and versioned S3 backend at
  `bootstrap/terraform.tfstate` with native S3 lockfile support.
- Verified the remote object uses AES-256 server-side encryption and versioning.
- Verified the monthly gross-cost Budget is healthy at USD 50 with current observed
  actual spend of USD 0.
- Verified the IAM password policy: 14-character minimum, character-class rules,
  90-day maximum age, and 24-password reuse prevention.
- Ran a post-apply refresh plan against remote state: no changes and no drift.
- Added and applied actual-spend alerts at 50% and 80%, plus a forecasted-spend alert
  at 100%, using the locally configured recipient; 0 resources added, 1 changed, 0
  destroyed.

## Next action

Supply the local budget notification email, run a bootstrap plan, review it, and
obtain explicit approval before the first apply.
