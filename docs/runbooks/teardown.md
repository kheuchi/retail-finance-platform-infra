# Runbook: Teardown

**Contents:** [TL;DR](#tldr) · [Steps](#steps) · [Check it worked](#check-it-worked) · [What stays](#what-stays-usd-1month)

Why the order matters: [story 2.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.5-guardrails.md) (teardown order).

## TL;DR

| Question | Answer |
|---|---|
| When | By **2026-10-06**, the day the Databricks trial ends |
| Why | Stops ~USD 2/day of network cost and avoids pay-as-you-go DBU charges |
| Order | Unity Catalog + guardrails → workspace → network. One PR + one deploy each |
| After | ~USD 1/month left; everything rebuilds by flipping the flags back |

## Steps

> **TL;DR:** three flag flips, then account and credential clean-up. Detail: [`../../cmdb.yml`](../../cmdb.yml) → `stacks.bootstrap.flags`, `stacks.databricks.flags`

1. **Workspace objects off.** In `databricks/variables.tf` set `enable_unity_catalog = false`
   and `enable_guardrails = false`. PR, merge, **Deploy Databricks Workspace**.
   (Must run while the workspace still exists.)
2. **Workspace off.** Set `enable_workspace = false`. PR, merge, deploy again. This also
   removes the serverless network policy and the Databricks budget.
3. **Network off.** In `bootstrap/variables.tf` set `enable_databricks_network = false`.
   PR, merge, **Deploy AWS Bootstrap**. (The VPC can't be deleted while a workspace uses it.)
4. **Databricks account:** delete the starter serverless workspace, then cancel the
   AWS Marketplace subscription.
5. **Credentials:** revoke every service principal secret, delete `~/.databrickscfg`,
   remove `DATABRICKS_CLIENT_SECRET` from GitHub (infra and data-products repos).

## Check it worked

> **TL;DR:** zero endpoints now, zero endpoint charges tomorrow.

```bash
aws ec2 describe-vpc-endpoints --region eu-central-1 --query 'length(VpcEndpoints)'   # expect 0
```

Then Cost Explorer a day later: no VPC endpoint charges.

## What stays (~USD 1/month)

> **TL;DR:** the cheap foundation. Detail: [`../../cmdb.yml`](../../cmdb.yml) → `costs_usd_month`

State bucket, budget, CloudTrail, alarms, the two data buckets (empty or near-empty).
