# Architecture

**Contents:** [TL;DR](#tldr) · [Diagram](#diagram) · [Key choices](#key-choices) · [Where the data lives](#where-the-data-lives) · [What it costs](#what-it-costs) · [Not built](#not-built)

Full design: [HLD and LLDs](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/hld.md) in the control plane.
Inventory: [`../cmdb.yml`](../cmdb.yml).

## TL;DR

| Question | Answer |
|---|---|
| Shape | One AWS account, one VPC, classic Databricks workspace inside it |
| Internet access for clusters | None: PrivateLink to Databricks, gateway endpoint to S3 |
| Where finance data lives | Only in our S3 buckets; Databricks gets commands, not data |
| Blast radius | Two Terraform stacks: a Databricks mistake cannot touch state, audit or CI roles |
| Cost | ~USD 65/month with the network on, ~1 without |

## Diagram

> **TL;DR:** the network in detail. The editable draw.io source lives in the control plane.

![Network LLD](https://raw.githubusercontent.com/kheuchi/retail-finance-platform-control-plane/main/docs/architecture/lld-network.png)

Explained in [LLD 1 · Network](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-network.md).

## Key choices

> **TL;DR:** private and reviewable by default. Decisions: control-plane `cmdb.yml` → `decisions`

| Choice | Why | Story |
|---|---|---|
| One AWS account, not many | Organizations would forfeit the credit; the multi-account design is documented instead | [1.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.1-aws-account-baseline.md) |
| Classic workspace in **our** VPC | How regulated firms run Databricks; serverless shows no network controls | [2.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.1-where-databricks-runs.md) |
| **No egress path at all** (PrivateLink, Enterprise tier) | Finance figures before publication are price-sensitive. "Can't leave" beats "we'd notice" | [2.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.1-where-databricks-runs.md) |
| Two Terraform stacks | A Databricks mistake can't touch state, audit or CI roles | [2.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.3-workspace-as-code.md) |
| AWS-managed encryption, not KMS keys | KMS keys cost monthly; revisit when data is classified | [Checkov exceptions](security/checkov-exceptions.md) |

## Where the data lives

> **TL;DR:** our EC2, our S3; only commands cross to Databricks. Detail: [`../cmdb.yml`](../cmdb.yml) → `stacks.databricks`

Our clusters (EC2 in our VPC) read and write our S3 buckets. Only commands and small
results cross to Databricks' control plane, and only through PrivateLink.
Finance tables never leave the account.

## What it costs

> **TL;DR:** the private network is the bill. Detail: [`../cmdb.yml`](../cmdb.yml) → `costs_usd_month`

| Item | USD/month |
|---|---|
| Foundation (trail, logs, alarms, buckets) | ~1 |
| Network: 4 interface endpoints × 2 zones | ~64 |
| Clusters | only while running |
| Databricks licence (DBUs) | trial credit until 2026-10-06 |

A NAT design would be ~38. We pay more on purpose, for the stronger control.

## Not built

> **TL;DR:** known gaps, stated rather than hidden.

Front-end PrivateLink (users reach the UI over the internet) · customer-managed KMS
keys · a separate log-archive account · IP access lists on the workspace ·
separate service principals per duty (planned, [story 4.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/4.5-split-service-principals.md)).
