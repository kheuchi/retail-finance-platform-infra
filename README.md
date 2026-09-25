# Retail Finance Platform: Infrastructure

**Contents:** [What's deployed (eu-central-1)](#whats-deployed-eu-central-1) · [Layout](#layout) · [Rules](#rules)

Terraform for the AWS and Databricks side of the
[retail finance platform](https://github.com/kheuchi/retail-finance-platform-control-plane):
a private Databricks lakehouse for a large retailer's accounting department.

## What's deployed (eu-central-1)

> Detail: [`cmdb.yml`](cmdb.yml) → `stacks`

- **Foundation:** state bucket, USD 50 budget, CI roles via GitHub OIDC, CloudTrail,
  alarms on break-glass and root use.
- **Network:** private VPC, **no internet gateway, no NAT**, PrivateLink to Databricks.
- **Databricks:** classic Enterprise workspace in that VPC, Unity Catalog on our own S3.

Running cost: ~USD 2/day while the network is on. Teardown due **2026-10-06**.

## Layout

| Path | What |
|---|---|
| `bootstrap/` | AWS foundation, network, buckets |
| `databricks/` | Databricks roles, workspace, Unity Catalog (reads `bootstrap/` outputs) |
| `docs/architecture.md` | How it fits together |
| `docs/ci-cd.md` | How changes get deployed |
| `docs/runbooks/` | Break-glass and teardown |
| `docs/security/checkov-exceptions.md` | Scanner findings we accept, and why |
| `cmdb.yml` | Full detail: resources, IAM, costs, incidents |

## Rules

> Detail: [`cmdb.yml`](cmdb.yml) → `ci_cd`

- Every change goes through a pull request; `main` is protected, admins included.
- Deploys run from GitHub Actions with short-lived OIDC credentials. No stored keys.
- Never commit credentials, state, plans or `*.tfvars`.
- Use Conventional Commits (`feat:`, `fix:`); releases are automatic.
