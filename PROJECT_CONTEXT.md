# Infrastructure Context

**Contents:** [TL;DR](#tldr) · [This repo owns](#this-repo-owns) · [Operating rules](#operating-rules) · [State](#state-2026-09-27) · [Next](#next)

Read first. Program context: [control plane](https://github.com/kheuchi/retail-finance-platform-control-plane).
Inventory: [cmdb.yml](cmdb.yml). Explanations: [stories](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/README.md).

## TL;DR

| Question | Answer |
|---|---|
| Owns | Terraform state, AWS identity, audit, network, storage, Databricks workspace, their CI/CD |
| Does not own | Data pipelines, models, agent code |
| State | All four flags on; everything verified in AWS and via the Databricks API |
| Next | Service principal split (after Gold), F-3 alarms, OIDC for Databricks, teardown 2026-10-06 |

## This repo owns

> **TL;DR:** the platform, not the workloads. Detail: [`cmdb.yml`](cmdb.yml) → `stacks`

Terraform state, AWS identity and policies, audit and alerting, network, storage,
Databricks workspace infrastructure, and the CI/CD that deploys them.
Not application code, data pipelines, models or agent logic.

## Operating rules

> **TL;DR:** seven rules, each learned the hard way. Detail: [`cmdb.yml`](cmdb.yml) → `incidents`

| # | Rule | Learned in |
|---|---|---|
| 1 | Work from WSL2. Use the named IAM user, never root | [1.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.1-aws-account-baseline.md) |
| 2 | Change code by pull request. Deploy with the gated workflows, not from a laptop | [1.2](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.2-passwordless-cicd.md) |
| 3 | Grant permissions in one apply, use them in the next. Run the IAM policy simulator first | [1.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.3-least-privilege-deploy-role.md) |
| 4 | Wait for post-merge CI before dispatching a deploy (state lock) | [2.2](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.2-private-network.md) |
| 5 | After any history rewrite, check every tag is reachable from `main` on the remote | [1.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.5-security-review-going-public.md) |
| 6 | Before any cloud CLI command, check which account it points at | [2.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/2.1-where-databricks-runs.md) |
| 7 | Record applies, destroys, exceptions and incidents in `cmdb.yml` | [X.1](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/X.1-documentation-system.md) |

## State (2026-09-27)

> **TL;DR:** everything on and verified. Detail: [`cmdb.yml`](cmdb.yml) → `stacks.bootstrap.flags`, `stacks.databricks.flags`

| Stack | Flag | State |
|---|---|---|
| bootstrap | `enable_databricks_network = true` | Applied, verified in AWS; endpoint SG admits 8443-8451 since 2026-09-26 |
| databricks | `enable_workspace = true` | Workspace RUNNING |
| databricks | `enable_unity_catalog = true` | Storage validated R/W/L/D; `finance` catalog, 5 schemas, 2 volumes |
| databricks | `enable_guardrails = true` | `finance-small` + `finance-jobs` policies, serverless egress, budget alerts |

## Next

> **TL;DR:** hardening first, teardown on the trial's last day.

| # | Item | Why |
|---|---|---|
| 1 | Split `terraform-platform` into platform, deploy and run-as service principals (after Gold) | One account admin currently also deploys and runs data jobs ([story 4.5](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/4.5-split-service-principals.md)) |
| 2 | Alarms on audit-trail tampering and IAM changes | Finding F-3 |
| 3 | Replace the Databricks secret with GitHub OIDC federation | Secret expires ~2026-10-08 |
| 4 | **Teardown on 2026-10-06** | [Runbook](docs/runbooks/teardown.md) |
