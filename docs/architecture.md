# Architecture

```text
 GitHub Actions ──OIDC──►  AWS account (eu-central-1)
                           ├─ bootstrap: state · budget · CloudTrail · alarms
                           └─ Databricks VPC (no internet gateway, no NAT)
                               ├─ workspace subnets ── cluster EC2 (ours)
                               └─ endpoint subnets ──► S3 · STS · Kinesis
                                                   └─► PrivateLink ─► Databricks control plane
 Users ──internet──► Databricks web UI (Databricks login)
 Unity Catalog ──IAM role──► governed S3 bucket (our data)
```

## Key choices

| Choice | Why |
|---|---|
| One AWS account, not many | Organizations would forfeit the credit; the multi-account design is documented instead |
| Classic workspace in **our** VPC | It's how regulated firms run Databricks; serverless shows no network controls |
| **No egress path at all** (PrivateLink, Enterprise tier) | Finance figures before publication are price-sensitive. "Can't leave" beats "we'd notice" |
| Two Terraform stacks | A Databricks mistake can't touch state, audit or CI roles |
| AWS-managed encryption, not KMS keys | KMS keys cost monthly; revisit when data is classified |

## Where the data lives

Our clusters (EC2 in our VPC) read and write our S3 buckets. Only commands and small
results cross to Databricks' control plane, and only through PrivateLink.
Finance tables never leave the account.

## What it costs

| Item | USD/month |
|---|---|
| Foundation (trail, logs, alarms, buckets) | ~1 |
| Network: 4 interface endpoints × 2 zones | ~64 |
| Clusters | only while running |
| Databricks licence (DBUs) | trial credit until 2026-10-06 |

A NAT design would be ~38. We pay more on purpose, for the stronger control.

## Not built

Front-end PrivateLink (users reach the UI over the internet) · customer-managed KMS
keys · a separate log-archive account · IP access lists on the workspace.

Detail: `cmdb.yml`. Decisions and their reasons: control-plane `cmdb.yml` → `decisions`.
