# Databricks workspace stack

## TL;DR

A second Terraform stack, separate from `bootstrap/`, that creates the Databricks
side of the platform: the IAM roles Databricks assumes, the registrations in the
Databricks account, a classic Enterprise workspace inside the customer-managed VPC,
and Unity Catalog access to the governed bucket.

It consumes the foundation rather than redefining it. The VPC, subnets, security
groups, PrivateLink endpoints and buckets are owned by `bootstrap/` and read here
from its state outputs. Dependency runs one way: `bootstrap/` never reads this stack.

## Why a separate stack

- **Blast radius.** A mistake here cannot touch the state bucket, the audit trail,
  the alarms or the CI roles.
- **Different credentials.** This stack needs Databricks account credentials;
  `bootstrap/` does not, and should not.
- **Different lifecycle.** The workspace is torn down after the trial. The
  foundation stays.

## What it creates

| Phase | Flag | Creates |
|---|---|---|
| Workspace | `enable_workspace` | Cross-account IAM role (restricted to this VPC and security group), Databricks credential, storage and network registrations, both PrivateLink endpoint registrations, private access settings, the Enterprise workspace, and admin assignments for the Terraform service principal and the human owner |
| Unity Catalog | `enable_unity_catalog` | Storage credential, its IAM role, and an external location over the governed bucket |

Both flags default to `false`. The workspace URL must exist before Unity Catalog
objects can be created through it, so the second phase is a separate apply.

Nothing here bills by itself. A workspace costs nothing until compute starts in it.
The running network cost belongs to `bootstrap/`.

## Order of operations

1. `bootstrap/`: set `enable_databricks_network = true`, merge, deploy.
2. `databricks/`: set `enable_workspace = true`, merge, deploy.
3. `databricks/`: set `enable_unity_catalog = true`, merge, deploy.

Enabling the workspace before the network fails with a readable precondition
message rather than a provider error.

## Authentication

The Databricks providers authenticate as the `terraform-platform` service
principal using OAuth machine-to-machine. The client ID and secret are read from
`DATABRICKS_CLIENT_ID` and `DATABRICKS_CLIENT_SECRET`:

- in CI, from the `DATABRICKS_CLIENT_ID` Actions variable and the
  `DATABRICKS_CLIENT_SECRET` Actions secret;
- on a workstation, from `~/.databrickscfg`, outside the repository and readable
  only by its owner.

The secret was issued with a 14-day lifetime, matching the trial. The planned
replacement is a Databricks federation policy trusting GitHub's OIDC tokens, which
removes the stored secret altogether, the same pattern already used for AWS.

## Confused-deputy defences

Databricks runs one AWS account for all its customers, so every trust here names
our Databricks account, not just Databricks:

- The cross-account role requires `sts:ExternalId` equal to our Databricks
  account ID.
- The Unity Catalog role requires the external ID Databricks issues for our
  storage credential, and is self-assuming as Databricks now requires.
- The root bucket grant requires `aws:PrincipalTag/DatabricksAccountId` to match.

## A known blind spot in the scanner

Checkov reports only three checks on this stack. The IAM policies are generated at
plan time by the Databricks provider's data sources, which track Databricks'
published policies, so static analysis cannot see them. That is a real gap, not a
clean bill of health. The mitigation is that the policies are Databricks' own
documented least-privilege set, using the `restricted` variant that pins EC2
actions to this VPC and security group. To inspect them, run a plan and read the
rendered JSON.

## Provider notes

- `account_id` is still needed on `databricks_mws_storage_configurations`,
  `databricks_mws_networks`, `databricks_mws_workspaces` and
  `databricks_mws_vpc_endpoint` in provider 1.134, even though the account-level
  provider block also carries it. For the VPC endpoint the schema does not mark it
  required, so `terraform validate` passes and the apply fails with the misleading
  `Unable to load OAuth Config`.
- Terraform does not store null outputs in state, so while the bootstrap network is
  off its network outputs are absent rather than null. They are read through
  `try()` in `main.tf` for that reason.
