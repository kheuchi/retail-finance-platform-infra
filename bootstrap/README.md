# bootstrap/

**Contents:** [TL;DR](#tldr) · [What it creates](#what-it-creates) · [Run](#run)

The AWS foundation. Everything else builds on it. Inventory: [`../cmdb.yml`](../cmdb.yml) → `stacks.bootstrap`.

## TL;DR

| Question | Answer |
|---|---|
| What | State, budget, CI identities, audit, alerting, Databricks buckets and private network |
| Switch | `enable_databricks_network` (on until 2026-10-06) |
| Deploy | PR → merge → **Actions → Deploy AWS Bootstrap** → type `apply` |
| Stories | [1.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.1-aws-account-baseline.md) · [1.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.3-least-privilege-deploy-role.md) · [1.4](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.4-audit-and-alarms.md) · [2.2](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.2-private-network.md) |

## What it creates

> **TL;DR:** six areas, all in eu-central-1. Diagrams: [LLD 1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-network.md), [LLD 4](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-observability-cost.md)

| Area | What |
|---|---|
| State | Encrypted, versioned S3 bucket with native locking |
| Cost | USD 50/month budget, alerts at 50%, 80% and forecast 100% |
| Identity | GitHub OIDC provider, a read-only plan role and a scoped deploy role |
| Audit | Multi-region CloudTrail, VPC flow logs, protected log bucket |
| Alerting | Alarms on break-glass writes and root use, emailed via SNS |
| Databricks | Workspace root bucket, Unity Catalog bucket, private VPC + PrivateLink |

## Run

> **TL;DR:** the pipeline applies; locally you only plan. Detail: [`../cmdb.yml`](../cmdb.yml) → `iam.deploy_role`

Normally: open a PR, merge, then **Actions → Deploy AWS Bootstrap → `apply`**.

Locally (plan only):

```bash
eval "$(aws configure export-credentials --format env)"   # Terraform can't read `aws login` directly
./scripts/plan-bootstrap-remote.sh
```

Needs `bootstrap/terraform.tfvars` (gitignored; see the `.example`).
