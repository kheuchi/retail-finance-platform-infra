# databricks/

**Contents:** [Security in one line each](#security-in-one-line-each) · [Gotchas (provider 1.134)](#gotchas-provider-1134)

The Databricks side, as a separate stack: if something breaks here, the state
bucket, audit trail and CI roles are out of reach.

| Flag | Creates | State |
|---|---|---|
| `enable_workspace` | Cross-account role, account registrations, classic Enterprise workspace, admin assignments | On |
| `enable_unity_catalog` | Storage credential, its IAM role, external location on the governed bucket | On |
| `enable_guardrails` | `finance-small` cluster policy; users can create clusters only through it | On |

Always with the workspace: serverless egress restricted to the governed bucket, and
Databricks budget alerts at USD 100 / 200 / 300 / 380 (see `guardrails.tf`).

Order: bootstrap network first, then workspace, then Unity Catalog (it needs the
workspace URL). Enabling too early fails with a clear message.

## Security in one line each

> Detail: [`../cmdb.yml`](../cmdb.yml) → `stacks.databricks, iam`

- Databricks can only use our roles on behalf of **our** account (external IDs,
  principal tag), which blocks the "confused deputy" problem.
- The cross-account role can only launch instances in **our** VPC and security group.
- Auth is a service principal with a 14-day secret; target is OIDC with no secret.
- Clusters stop after 10–30 min, max 2 small workers, spot, no Photon. Admins can
  bypass the policy, so for the owner it's a default; the budget alerts still apply.

## Gotchas (provider 1.134)

> Detail: [`../cmdb.yml`](../cmdb.yml) → `incidents`

- `account_id` must be set on several `databricks_mws_*` resources even though the
  provider has it. For VPC endpoints, validate passes and apply fails.
- Null outputs aren't stored in state; bootstrap outputs are read with `try()`.
- Checkov can't see the IAM policies the provider generates.

Deploy: **Actions → Deploy Databricks Workspace → `apply`**. Detail: `cmdb.yml`.
