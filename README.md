# Retail Finance Platform: Infrastructure

**Contents:** [TL;DR](#tldr) · [Architecture](#architecture) · [What's deployed](#whats-deployed-eu-central-1) · [Layout](#layout) · [Rules](#rules) · [How it was built](#how-it-was-built)

Terraform for the AWS and Databricks side of the
[retail finance platform](https://github.com/kheuchi/retail-finance-platform-control-plane):
a private Databricks lakehouse for a large retailer's accounting department.
Inventory: [`cmdb.yml`](cmdb.yml).

## TL;DR

| Question | Answer |
|---|---|
| What is here? | Two Terraform stacks: `bootstrap/` (AWS foundation, network) and `databricks/` (workspace, Unity Catalog, guardrails) |
| What does it build? | A classic Databricks Enterprise workspace in our own VPC, with **no internet gateway and no NAT** |
| How do changes ship? | Pull request → checks (Terraform, Checkov) → merge → gated deploy with short-lived OIDC credentials |
| What does it cost? | ~USD 2/day while the network is on; teardown due **2026-10-06** |
| Where is the why? | [Architecture docs](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/hld.md) and [build stories](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/README.md) in the control plane |

## Architecture

> **TL;DR:** code in GitHub, data and compute in our AWS account, orchestration in Databricks' account.

![High-level design](https://raw.githubusercontent.com/kheuchi/retail-finance-platform-control-plane/main/docs/architecture/hld.png)

Zoom in: [network](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-network.md) ·
[identity & CI/CD](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-identity-cicd.md) ·
[observability & cost](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-observability-cost.md).
Short version in this repo: [docs/architecture.md](docs/architecture.md).

## What's deployed (eu-central-1)

> **TL;DR:** foundation, private network, workspace. Detail: [`cmdb.yml`](cmdb.yml) → `stacks`

| Layer | Contents |
|---|---|
| Foundation | State bucket, USD 50 budget, CI roles via GitHub OIDC, CloudTrail, alarms on break-glass and root use |
| Network | Private VPC, no internet gateway, no NAT, PrivateLink to Databricks, flow logs |
| Databricks | Classic Enterprise workspace, Unity Catalog on our S3, `finance` catalog, cluster policies, budget alerts |

## Layout

> **TL;DR:** one folder per stack, docs for how and why, cmdb for facts.

| Path | What |
|---|---|
| [`bootstrap/`](bootstrap/README.md) | AWS foundation, network, buckets |
| [`databricks/`](databricks/README.md) | Databricks roles, workspace, Unity Catalog, guardrails (reads `bootstrap/` outputs) |
| [`docs/architecture.md`](docs/architecture.md) | How it fits together, key choices, cost |
| [`docs/ci-cd.md`](docs/ci-cd.md) | How changes get deployed |
| [`docs/runbooks/`](docs/runbooks/) | [Break-glass](docs/runbooks/break-glass.md) and [teardown](docs/runbooks/teardown.md) |
| [`docs/security/checkov-exceptions.md`](docs/security/checkov-exceptions.md) | Scanner findings we accept, and why |
| [`cmdb.yml`](cmdb.yml) | Inventory: resources, IAM, costs, incidents (each linked to its story) |

## Rules

> **TL;DR:** PR only, no stored keys, nothing secret in Git. Detail: [`cmdb.yml`](cmdb.yml) → `ci_cd`

- Every change goes through a pull request; `main` is protected, admins included.
- Deploys run from GitHub Actions with short-lived OIDC credentials. No stored keys.
- Never commit credentials, state, plans or `*.tfvars`.
- Use Conventional Commits (`feat:`, `fix:`); releases are automatic.

## How it was built

> **TL;DR:** every hard part is written up as a story: symptom, cause, fix, lesson.

| Story | Covers |
|---|---|
| [1.2 Passwordless CI/CD](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.2-passwordless-cicd.md) | GitHub OIDC, the hardened subject claim |
| [1.3 Least-privilege deploy role](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.3-least-privilege-deploy-role.md) | Two-phase apply, break-glass, IAM simulator |
| [1.4 Audit trail and alarms](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.4-audit-and-alarms.md) | CloudTrail, the filter that never fired |
| [2.2 Fully private network](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.2-private-network.md) | Build gated off, Checkov blind spots |
| [2.3 Workspace as code](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.3-workspace-as-code.md) | Service principal, misleading errors |
| [2.4 Unity Catalog on our S3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.4-unity-catalog-on-our-s3.md) | External IDs, the non-obvious create order |
| [2.5 Guardrails](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.5-guardrails.md) | Cluster policies, undocumented API limits |
| [3.3 First job in the private VPC](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/3.3-first-job-in-the-private-vpc.md) | Flow logs named the blocked port |
