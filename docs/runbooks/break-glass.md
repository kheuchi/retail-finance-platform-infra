# Runbook: Break-Glass Administrator Access

## TL;DR

Normally nothing is deployed by hand: GitHub Actions authenticates to AWS with a
short-lived token and runs Terraform. This runbook covers the case where that
automation cannot fix itself and a human has to step in directly.

Use it sparingly, record every use, and prefer the pipeline whenever the pipeline
still works.

## What "break-glass" means

An emergency access path that bypasses the normal controlled route. The name is the
fire-alarm metaphor: it is available, it is obvious when it has been used, and using
it is an event worth explaining afterwards.

The important property is not that it exists — it is that it has been *tested*. An
untested emergency path is a plan, not a control.

## When this applies

Use break-glass only when the deployment pipeline cannot complete and cannot be
repaired by a normal commit. In practice that means one of:

1. **The CI role's own permissions are the blocker.** The deploy role cannot grant
   itself a missing permission, because the missing permission is what stops its
   plan. This is the failure we actually hit, described below.
2. **The remote state is damaged or locked** and must be inspected or rolled back to
   a previous S3 object version.
3. **GitHub Actions, the OIDC provider, or the trust policy is broken**, so no
   workflow can authenticate at all.
4. **A cost emergency** requires stopping spend faster than a review cycle allows.

If the pipeline still runs, do not use this. Commit the fix and dispatch the
workflow.

## What does NOT apply

- Routine changes. Use `deploy-bootstrap.yml`.
- Impatience with the pipeline. The pipeline being slow is not an emergency.
- Anything you have not first attempted through a reviewed plan.

## Preconditions

- The named IAM user `cheikh-platform-admin`. Never the root account.
- WSL2 with the AWS CLI and Terraform on `PATH` (`PROJECT_CONTEXT.md` lists versions).
- `bootstrap/terraform.tfvars` present locally. It is Git-ignored and supplies the
  Budget alert address.

There are no stored AWS access keys anywhere in this path. Authentication is a
short-lived browser-based session that expires on its own.

## Procedure

### 1. Authenticate

```bash
wsl -d Ubuntu
aws login --profile retail-platform-admin
aws sts get-caller-identity --profile retail-platform-admin --query Arn --output text
```

Confirm the ARN is the named IAM user, not root. Stop if it is root.

### 2. Plan, and read the plan

```bash
cd /mnt/c/Users/cheik/.vscode/retail-finance-platform-infra
./scripts/plan-bootstrap-remote.sh
```

Read the output before continuing. Specifically check the counts on the `Plan:` line
and confirm nothing is being destroyed that you did not intend to destroy.

To repair one resource without dragging unrelated pending changes along, scope the
plan:

```bash
cd bootstrap
eval "$(aws configure export-credentials --profile retail-platform-admin --format env)"
terraform plan -target=<resource.address> -out=bootstrap.tfplan
```

Terraform will warn that `-target` is not for routine use. That warning is correct and
this is one of the exceptions it names: recovering from an error.

### 3. Apply the exact plan you just read

```bash
cd /mnt/c/Users/cheik/.vscode/retail-finance-platform-infra
./scripts/apply-bootstrap.sh
```

The script refuses to run without a saved plan file, so it cannot apply something you
have not seen.

### 4. Return to the pipeline and prove it recovered

```bash
rm -f bootstrap/bootstrap.tfplan
git add -A && git commit && git push origin main
gh workflow run deploy-bootstrap.yml --ref main -f confirmation=apply
```

The repair is not finished when the apply succeeds. It is finished when the pipeline
works again without you. Delete the local plan file so a stale plan cannot be applied
later by accident.

### 5. Record it

Add an entry to `PROJECT_CONTEXT.md` covering what broke, why the pipeline could not
fix it, exactly what you applied by hand, and what changed so it does not recur.

## Worked example: the failure this runbook came from

On 2026-09-16 the first real dispatch of `deploy-bootstrap.yml` failed during plan.
The deploy role could modify the state bucket and the Budget but lacked
`s3:GetAccelerateConfiguration` and `budgets:ListTagsForResource`, so it could not
finish *reading* them — and Terraform refreshes before it plans.

The role could not grant itself those permissions, because the plan that would have
done so was the thing being blocked. Recovery used this runbook: authenticate as the
named IAM user, `-target` the single role policy, apply, push, re-dispatch. The
pipeline then planned and applied on its own.

Two lessons worth keeping:

- A role needs **read** permission on everything it manages, not just write. Wildcards
  like `s3:GetBucket*` silently miss actions whose names do not share that prefix.
- Fixing one fault can reveal a second that it was masking. The same run then failed
  on an unrelated Budget-email secret defect, which had been invisible while role
  assumption was failing earlier in the job.

## Known weaknesses of the current path

This is a portfolio-scale implementation, and the gaps are deliberate rather than
hidden:

- The break-glass identity is a broad administrator, not a narrowly scoped emergency
  role.
- One person holds both the normal and the emergency path.

Two weaknesses listed here previously are now closed. A multi-region CloudTrail
retains the API-level evidence of a break-glass session, and a CloudWatch metric
filter raises an alarm on any write performed by this identity, delivered by email.
Use of this runbook is therefore noticed, not merely recorded.

That detection was verified on 2026-09-17 by performing a write as this identity and
confirming the alarm fired, rather than by assuming the filter was correct. Expect a
few minutes between the API call and the alarm; CloudTrail delivery is not instant,
so an operator using this path should not expect to be paged immediately.

## Enterprise target

- A dedicated emergency-access role, assumable only with MFA, separate from any
  day-to-day identity.
- An EventBridge rule on its assumption that pages a human, so use is noticed
  immediately rather than discovered later.
- CloudTrail in an account the role cannot write to, so the evidence survives the
  incident.
- Time-boxed elevation with automatic expiry, and a second approver for production.
- Scheduled rehearsal. An emergency path that has not been exercised recently should
  be assumed broken.
