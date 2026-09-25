# Runbook: Teardown

**When:** by 2026-10-06, when the Databricks trial ends. Stops ~USD 2/day of network
cost and avoids pay-as-you-go DBU charges.

Order matters: Unity Catalog → workspace → network. Each step is one PR plus one deploy.

## Steps

1. **Unity Catalog off.** In `databricks/variables.tf` set `enable_unity_catalog = false`.
   PR, merge, **Deploy Databricks Workspace**. (Must run while the workspace still exists.)
2. **Workspace off.** Set `enable_workspace = false`. PR, merge, deploy again.
3. **Network off.** In `bootstrap/variables.tf` set `enable_databricks_network = false`.
   PR, merge, **Deploy AWS Bootstrap**. (The VPC can't be deleted while a workspace uses it.)
4. **Databricks account:** delete the starter serverless workspace, then cancel the
   AWS Marketplace subscription.
5. **Credentials:** revoke the `terraform-platform` secret, delete `~/.databrickscfg`,
   remove `DATABRICKS_CLIENT_SECRET` from GitHub.

## Check it worked

```bash
aws ec2 describe-vpc-endpoints --region eu-central-1 --query 'length(VpcEndpoints)'   # expect 0
```

Then Cost Explorer a day later: no VPC endpoint charges.

## What stays (~USD 1/month)

State bucket, budget, CloudTrail, alarms, the two data buckets (empty or near-empty).
Everything can be rebuilt by flipping the flags back.
