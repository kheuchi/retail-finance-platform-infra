# Infrastructure Context

**Contents:** [This repo owns](#this-repo-owns) · [Operating rules](#operating-rules) · [State (2026-09-25)](#state-2026-09-25) · [Next](#next)

Read first. Program-level context lives in the control-plane repo. Detail is in
[cmdb.yml](cmdb.yml).

## This repo owns

> Detail: [`cmdb.yml`](cmdb.yml) → `stacks`

Terraform state, AWS identity and policies, audit and alerting, network, storage,
Databricks workspace infrastructure, and the CI/CD that deploys them.
Not application code, data pipelines, models or agent logic.

## Operating rules

> Detail: [`cmdb.yml`](cmdb.yml) → `incidents`

1. Work from WSL2. Use the named IAM user, never root.
2. Change code by pull request. Deploy with the gated workflows, not from a laptop.
3. Grant permissions in one apply, use them in the next. Run the IAM policy
   simulator before applies that need new permissions.
4. Wait for post-merge CI to finish before dispatching a deploy (state lock).
5. After any history rewrite, fetch tags and check every tag is reachable from `main`.
6. Before any cloud CLI command, check which account it points at.
7. Record applies, destroys, exceptions and incidents in `cmdb.yml`.

## State (2026-09-25)

> Detail: [`cmdb.yml`](cmdb.yml) → `stacks.bootstrap.flags, stacks.databricks.flags`

| Stack | Flag | State |
|---|---|---|
| bootstrap | `enable_databricks_network = true` | Applied, verified in AWS |
| databricks | `enable_workspace = true` | Workspace RUNNING |
| databricks | `enable_unity_catalog = true` | Storage validated R/W/L/D |

## Next

1. Cluster policies: auto-termination and size limits, before any cluster runs.
2. Alarms on audit-trail tampering and IAM changes (finding F-3).
3. Replace the Databricks secret with GitHub OIDC federation (secret expires ~2026-10-08).
4. **Teardown on 2026-10-06:** see `docs/runbooks/teardown.md`.
