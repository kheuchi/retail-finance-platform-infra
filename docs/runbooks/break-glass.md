# Runbook: Break-Glass

**Contents:** [TL;DR](#tldr) · [Steps](#steps) · [Used so far](#used-so-far) · [Known weaknesses](#known-weaknesses)

Why it exists: [story 1.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.3-least-privilege-deploy-role.md).

## TL;DR

| Question | Answer |
|---|---|
| When | Only when the pipeline **cannot fix itself** (e.g. the deploy role lacks the permission it needs to plan) |
| Who | The named admin `cheikh-platform-admin` with MFA, **never root** |
| Side effect | Every write raises an alarm by email (tested). That's intended |
| After | Prove the pipeline works again, record the incident in `cmdb.yml` |

## Steps

> **TL;DR:** log in, plan one resource, apply that plan, hand back to CI.

1. **Log in as the named admin, never root.**
   ```bash
   aws login
   aws sts get-caller-identity --query Arn --output text   # must end in user/cheikh-platform-admin
   ```
2. **Plan and read the plan.** Target only the broken resource.
   ```bash
   cd bootstrap && eval "$(aws configure export-credentials --format env)"
   terraform plan -target=<resource.address> -out=bootstrap.tfplan
   ```
3. **Apply exactly that plan.** `terraform apply bootstrap.tfplan`, then delete the file.
4. **Prove the pipeline works again** by dispatching the deploy workflow.
5. **Record it** in `cmdb.yml` → `incidents`: what broke, why, what you applied.

## Used so far

> **TL;DR:** twice, both on 2026-09-16. Detail: [`../../cmdb.yml`](../../cmdb.yml) → `incidents`

Missing read permissions, then a CloudTrail action with no resource type.
Since then the two-phase apply and the IAM simulator have kept it unused.

## Known weaknesses

> **TL;DR:** honest gaps, with the target state.

Broad admin identity, same person as the normal path, never rehearsed on purpose.
Target: a separate MFA-only emergency role, paged on use, rehearsed on a schedule.
