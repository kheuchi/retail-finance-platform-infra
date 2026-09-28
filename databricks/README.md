# databricks/

**Contents:** [TL;DR](#tldr) · [Flags](#flags) · [Security in one line each](#security-in-one-line-each) · [Gotchas](#gotchas-provider-1134)

The Databricks side, as a separate stack: if something breaks here, the state
bucket, audit trail and CI roles are out of reach. Inventory: [`../cmdb.yml`](../cmdb.yml) → `stacks.databricks`.

## TL;DR

| Question | Answer |
|---|---|
| What | Cross-account role, workspace, Unity Catalog access, `finance` catalog, groups, guardrails |
| Order | Bootstrap network → workspace → Unity Catalog (enabling too early fails with a clear message) |
| Auth | `terraform-platform` (this stack), OAuth, 14-day secret (target: OIDC); data jobs use the deployer and runner ([identities.tf](identities.tf)) |
| Deploy | PR → merge → **Actions → Deploy Databricks Workspace** → type `apply` |
| Stories | [2.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.3-workspace-as-code.md) · [2.4](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.4-unity-catalog-on-our-s3.md) · [2.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.5-guardrails.md) · [3.2](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/3.2-catalog-and-bundle-deploy.md) |

## Flags

> **TL;DR:** three switches, all on; teardown flips them off in reverse order.

| Flag | Creates | State |
|---|---|---|
| `enable_workspace` | Cross-account role, account registrations, classic Enterprise workspace, admin assignments, serverless egress policy, budget alerts (100/200/300/380) | On |
| `enable_unity_catalog` | Storage credential + IAM role, external location, `finance` catalog (raw, bronze, silver, gold, ops), volumes `raw.landing` and `ops.artifacts`, groups and grants | On |
| `enable_guardrails` | `finance-small` (interactive) and `finance-jobs` (job clusters) policies; users create clusters only through them | On |

## Security in one line each

> **TL;DR:** every trust is pinned to our account, every cluster is small. Detail: [`../cmdb.yml`](../cmdb.yml) → `stacks.databricks`

- Databricks can only use our roles on behalf of **our** account (external IDs,
  principal tag), which blocks the "confused deputy" problem.
- The cross-account role can only launch instances in **our** VPC and security group.
- Clusters: max 2 small workers, spot, no Photon; interactive ones stop after 10–30 min.
  Admins can bypass the policy, so for the owner it's a default; the budget alerts still apply.
- Three identities, one duty each ([story 4.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/4.5-split-service-principals.md)):
  `terraform-platform` runs Terraform, `finance-data-deployer` deploys the data bundle,
  `finance-pipeline-runner` is what jobs run as. The runner cannot grant or administer;
  grants are audited in CI by `scripts/access_audit.py`.

## Gotchas (provider 1.134)

> **TL;DR:** the provider has sharp edges; each one is an incident in the cmdb. Detail: [`../cmdb.yml`](../cmdb.yml) → `incidents`

| Gotcha | Fix |
|---|---|
| `account_id` required on `databricks_mws_*` resources; for VPC endpoints the error says "Unable to load OAuth Config" | Always pass `account_id` |
| Null outputs aren't stored in state | Read bootstrap outputs with `try()` |
| Network policy ID limited to 32 characters (undocumented) | Short ID + a `precondition` |
| Budget shows a diff on every plan | `ignore_changes` on the normalised fields |
| Checkov can't see provider-generated IAM policies | Reviewed by hand |
