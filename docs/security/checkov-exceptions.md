# Checkov Exception Register

## Purpose

Checkov is a policy-as-code scanner: it reads the Terraform source and reports where
it deviates from a library of security controls. It runs on every CI build and is
deliberately non-blocking while the baseline matures.

Plain words: it is a security checklist applied to the infrastructure code before
anything is deployed. A finding is not automatically a defect. Some controls do not
apply to this project, and some cost more than the risk they remove. What matters is
that every remaining finding is a decision someone made on purpose, not an oversight.

This file is that record. Every `#checkov:skip=` annotation in the Terraform must have
an entry here, and every entry must state what would make us revisit it.

## Status

Baseline at triage (2026-09-16): 89 passed, 7 failed, 0 skipped.

| Check | Resource | Disposition |
|---|---|---|
| CKV_AWS_300 | State bucket lifecycle | Fixed |
| CKV_AWS_356 | Deploy role policy | Partly fixed, remainder accepted |
| CKV_AWS_111 | Deploy role policy | Partly fixed, remainder accepted |
| CKV_AWS_18 | State bucket | Deferred to the audit work item |
| CKV2_AWS_62 | State bucket | Not applicable |
| CKV_AWS_144 | State bucket | Rejected on cost and architecture grounds |
| CKV_AWS_145 | State bucket | Accepted risk, cost-driven |

## Fixed

### CKV_AWS_300 — abort incomplete multipart uploads

A failed or interrupted upload leaves multipart fragments in the bucket. They are
billed as storage but do not appear in a normal object listing, so they accumulate
silently. The lifecycle rule now aborts them 7 days after initiation.

This one was worth fixing outright: it costs nothing, removes a small unbounded cost
leak, and needs no trade-off discussion.

### CKV_AWS_356 and CKV_AWS_111 — partly fixed

Both checks object to `"*"` in the resource field of an IAM policy, which grants an
action across every resource of that type in the account rather than a named one.

The AWS Budgets statement did not need `"*"`. Budgets supports resource-level
permissions, so the deploy role is now scoped to the single project budget ARN. That
was a genuine over-grant and is closed.

## Accepted

### CKV_AWS_356 / CKV_AWS_111 — residual `"*"` on the account password policy

`iam:GetAccountPasswordPolicy` and `iam:UpdateAccountPasswordPolicy` act on an
account-wide setting that has no ARN. AWS does not accept a resource-qualified
statement for them, so `"*"` is the only expressible form.

Residual risk: a caller holding this role can weaken the account password policy.
Bounded by the fact that the role is assumable only from the `aws-bootstrap`
environment of one GitHub repository, identified by immutable numeric ID.

Revisit when: the account joins an AWS Organization, at which point a Service Control
Policy can set a floor the role cannot lower.

### CKV_AWS_18 — no S3 server access logging

Server access logging records every request made to the bucket, and requires a second
bucket to receive those logs.

Deferred rather than rejected. There is no audit baseline in this account yet: no
CloudTrail trail and no Config recorder. Adding one logging bucket in isolation would
produce evidence nobody reviews while implying broader coverage than exists.

Residual risk: no record of who read or wrote Terraform state.

Revisit when: the CloudTrail and audit foundation is built. CloudTrail data events on
this bucket are the better control and should be evaluated first, since they land in
the same audit store as everything else.

### CKV2_AWS_62 — no S3 event notifications

Event notifications publish object-change events to SNS, SQS or Lambda. There is no
consumer for them here, and none is planned. State changes are driven by CI runs that
already produce logs and a plan artifact.

Adding a notification target with no subscriber would create a resource to maintain
and pay for that improves nothing.

Revisit when: a consumer genuinely exists, for example automated drift detection
triggered by out-of-band state writes.

## Rejected

### CKV_AWS_144 — no cross-region replication

Replication would continuously copy the state bucket to a second region.

Rejected on two grounds. It contradicts decision D-013, which standardised all
regional resources on `eu-central-1` specifically to reduce the number of residency
boundaries to govern and explain. It also roughly doubles storage cost plus
cross-region transfer, against a USD 50 monthly ceiling, to protect a single small
file that is already versioned and, in the worst case, reconstructible by importing
live resources.

Residual risk: total loss of an AWS region loses the state file. Accepted. Versioning
protects against the realistic failure, which is a bad write, not a region outage.

Revisit when: the state file backs production workloads whose recovery time objective
cannot tolerate a rebuild.

### CKV_AWS_145 — SSE-S3 instead of SSE-KMS

The bucket is encrypted at rest with AES-256 using S3-managed keys, and the bucket
policy denies any request not using TLS. Checkov wants a KMS key instead.

The practical difference is control over the key: a customer-managed KMS key gives an
independent audit trail of decryption and the ability to revoke access by key policy.
That is the right answer for regulated data. It is not obviously the right answer for
a bootstrap state file, because a customer-managed key carries a fixed monthly charge
plus per-request cost, and every role touching state needs matching `kms:Decrypt` and
`kms:GenerateDataKey` grants.

Residual risk: no independent key-level audit trail or revocation path for state.

Revisit when: the state file contains data classified above `internal`, or when the
audit baseline exists and the KMS request volume can be estimated.
