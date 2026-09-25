# bootstrap/

The AWS foundation. Everything else builds on it.

| Area | What |
|---|---|
| State | Encrypted, versioned S3 bucket with native locking |
| Cost | USD 50/month budget, alerts at 50%, 80% and forecast 100% |
| Identity | GitHub OIDC provider, a read-only plan role and a scoped deploy role |
| Audit | Multi-region CloudTrail, VPC flow logs, protected log bucket |
| Alerting | Alarms on break-glass writes and root use, emailed via SNS |
| Databricks | Workspace root bucket, Unity Catalog bucket, private VPC + PrivateLink |

The Databricks network sits behind `enable_databricks_network` (on until 2026-10-06).

## Run

Normally: open a PR, merge, then **Actions → Deploy AWS Bootstrap → `apply`**.

Locally (plan only):

```bash
eval "$(aws configure export-credentials --format env)"   # Terraform can't read `aws login` directly
./scripts/plan-bootstrap-remote.sh
```

Needs `bootstrap/terraform.tfvars` (gitignored; see the `.example`).
Resource-level detail: `cmdb.yml` → `stacks.bootstrap`.
