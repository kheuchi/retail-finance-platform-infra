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
- Bootstrap is deployed and managed from encrypted remote state.
- Management, bootstrap, workload and AI region: `eu-central-1` (Frankfurt).
- Monthly personal-spend ceiling: USD 50.
- AWS Organizations and Control Tower must not be enabled while preserving the
  current AWS Free plan credits.

## Verified local toolchain

All infrastructure work runs inside WSL2 (Ubuntu 22.04) against the Windows working
copy at `/mnt/c/Users/cheik/.vscode/retail-finance-platform-infra`. Plain words: the
repository lives on Windows, but every Terraform, AWS and Git command is executed by
the Linux environment so the tooling matches the CI runner.

Verified present on 2026-09-15; nothing needed installing:

| Tool | Version | Used for |
|---|---|---|
| AWS CLI | 2.36.44 (`~/.local/bin/aws`) | Identity, S3 backend operations, short-lived credential export |
| Terraform | 1.14.6 (`/usr/bin/terraform`) | Plan, apply, state migration |
| GitHub CLI | authenticated as `kheuchi` | Workflow runs, logs, Actions secrets and variables |
| jq | 1.6 | Backend inspection and S3 version manifests |
| python3 | 3.10.12 | Workflow YAML validation in `scripts/validate-local.sh` |

Two operating notes for anyone reproducing this:

- `aws` is installed under `~/.local/bin`, so non-login shells must export
  `PATH="$HOME/.local/bin:$PATH"` first. Every script in `scripts/` already does.
- A second, expired `gh` account (`stale-work-account`) is still present in
  `~/.config/gh/hosts.yml`. `kheuchi` is the active account; the stale entry reports
  an invalid token and should be removed with `gh auth logout` to avoid confusion.

## Operating rules

1. Use the `retail-platform-admin` AWS CLI profile; never use root.
2. Never store credentials or state in Git.
3. Review plans before applies and require an explicit human gate for production.
4. Avoid persistent hourly resources unless their cost is documented and approved.
5. Do not use the default VPC for workloads.
6. Keep reusable modules separate from environment compositions.
7. Record every apply, destroy, exception and residual cost in this file.

## Communication rules

- Start user-facing updates with a plain-language `TL;DR`.
- Introduce the correct technical terms and explain what they mean in practice.
- Clearly distinguish completed, verified work from work that is planned or blocked.
- Report security, cost and destructive-change implications in human-readable terms.

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
- Selected Frankfurt for workloads after verifying that neither Stockholm nor Paris
  supports required Databricks custom model and agent serving. The existing small
  state backend remains in Paris.
- Added GitHub Actions CI with Terraform formatting/validation, shell checks, an
  explicitly non-blocking Checkov 3.3.17 job, and semantic-release 25.0.9 on `main`.
- Published the private GitHub repository. The first run passed Terraform checks and
  created semantic release `v1.0.0`. Checkov exposed a missing pip cache dependency
  path before scanning; added `requirements-ci.txt` and wired the cache to it.
- Verified the repaired workflow on GitHub. Terraform checks passed; Checkov ran 37
  controls (32 passed, 5 findings) and remained advisory; semantic-release created
  `v1.0.1`. Findings cover incomplete-upload cleanup, access logging, event
  notifications, cross-region replication, and KMS encryption for the state bucket.
- Migrated the versioned Terraform backend from Paris to Frankfurt. Created and
  protected the destination first, copied state, rebound Terraform ownership, and
  applied a reviewed plan of 6 additions, 1 in-place update, and 0 deletions.
- Verified a post-migration refresh plan had no changes, then emptied all versions
  from the old Paris bucket and deleted it. All project infrastructure now uses
  `eu-central-1`; IAM and AWS Budgets remain global services.
- Provisioned the GitHub Actions OIDC provider plus separate plan and deploy roles.
  The plan role is read-only except for its exact S3 lock object and trusts only
  this repository's `main` branch. The deploy role is limited to bootstrap-owned
  resources and trusts only the `aws-bootstrap` GitHub Environment.
- Created the GitHub Environment, repository/environment role variables, and masked
  budget-email secret. The current private-repository plan does not support reviewer
  protection, so manual workflow dispatch from `main` is the present human gate.
- Added a real AWS refresh-plan job to CI and a manual plan-then-apply workflow. Both
  use short-lived OIDC sessions and immutable action SHAs; no AWS keys are stored.
- Tested the first OIDC cloud-plan run. Static Terraform checks passed and Checkov
  remained advisory, but AWS role assumption failed safely. A temporary diagnostic
  exposed only non-sensitive claims and confirmed GitHub's hardened subject includes
  immutable owner and repository IDs. Updated the trust policy locally and removed
  the diagnostic; deployment and a successful CI retest are still pending.

### 2026-09-15

- Recovered the exact `sub` claim from the retained diagnostic log of run
  `35006377469` rather than trusting the locally prepared fix. The claim is
  `repo:kheuchi@47268855/retail-finance-platform-infra@1371524439:ref:refs/heads/main`.
  Independently confirmed both numeric IDs through the GitHub API.
- Applied the corrected trust policies for the plan and deploy roles: 0 added,
  2 changed, 0 destroyed. Both changes are trust-policy strings only, so no
  resources were created and no cost was added.
- Removed the now-unused `github_repository` local and committed the previously
  untracked `scripts/plan-bootstrap-remote.sh` planning helper.
- Confirmed the fix end to end: GitHub Actions assumed the plan role through OIDC,
  initialized the Frankfurt remote backend, refreshed all bootstrap resources, and
  reported `No changes. Your infrastructure matches the configuration.`
- The successful role assumption exposed a second, previously masked defect. The
  `TF_VAR_BUDGET_ALERT_EMAIL` Actions secret did not reach Terraform as a usable
  value, so the run failed on the `budget_alert_email` validation. Plain words: the
  pipeline had two faults stacked on top of each other, and only fixing the first
  one made the second visible.
- Re-set that secret from the Git-ignored local `bootstrap/terraform.tfvars` with no
  trailing newline. The address was never printed, committed, or logged.
- Rewrote the validation error message to name the secret and explain that a blank
  secret arrives as an empty string, not as `null`. This matters because treating it
  as `null` would silently plan to delete the three Budget notifications.
- Re-ran CI: Terraform checks passed, the AWS plan reported no drift, Checkov
  remained advisory at 89 passed and 7 findings, and semantic-release cut `v1.1.0`.

## Verified security and cost position

- No AWS access keys exist in GitHub. Both workflows use short-lived OIDC sessions.
- The plan role is read-only apart from its single Terraform state lock object, and
  is trusted only from `main` in this exact repository by immutable numeric ID.
- The deploy role is trusted only from the `aws-bootstrap` Environment, also by
  immutable ID. It has not yet been exercised by a real apply.
- A repository rename, deletion and name reuse, or an account rename can no longer
  inherit either role's trust.
- Resources created to date: one S3 state bucket, one AWS Budget, one IAM password
  policy, one OIDC provider and two IAM roles. None are hourly-billed.

## Next action

1. Exercise the deploy role once through `deploy-bootstrap.yml` to prove the apply
   path, since only the plan role has been verified against AWS so far.
2. Triage the seven Checkov findings and record justified exceptions or fixes.
3. Design and cost the Frankfurt network, audit and Databricks foundations.
