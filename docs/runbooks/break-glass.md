# Runbook: Break-Glass

**Contents:** [Steps](#steps) · [Used so far](#used-so-far) · [Known weaknesses](#known-weaknesses)

Use only when the pipeline **cannot fix itself**, e.g. the deploy role lacks the very
permission it needs to plan. If the pipeline still runs, fix it by PR instead.

Every use raises an alarm by email (tested). That's intended.

## Steps

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

> Detail: [`../../cmdb.yml`](../../cmdb.yml) → `incidents`

Twice on 2026-09-16: missing read permissions, then a CloudTrail action with no
resource type. Both are in `cmdb.yml`.

## Known weaknesses

Broad admin identity, same person as the normal path, never rehearsed on purpose.
Target: a separate MFA-only emergency role, paged on use, rehearsed on a schedule.
