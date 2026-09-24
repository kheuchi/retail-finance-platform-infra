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

Baseline at triage (2026-09-16): 89 passed, 7 failed, 0 skipped. After triage:
90 passed, 0 failed, 6 skipped.

After the audit baseline was added the same day, three further findings appeared on
the trail itself. All three are recorded below; one of them, CloudWatch Logs
integration, is deferred rather than rejected and is the next planned increment.

| Check | Resource | Disposition |
|---|---|---|
| CKV_AWS_300 | State bucket lifecycle | Fixed |
| CKV_AWS_356 | Deploy role policy | Partly fixed, remainder accepted |
| CKV_AWS_111 | Deploy role policy | Partly fixed, remainder accepted |
| CKV_AWS_18 | State bucket | Deferred to the audit work item |
| CKV2_AWS_62 | State bucket | Not applicable |
| CKV_AWS_144 | State bucket | Rejected on cost and architecture grounds |
| CKV_AWS_145 | State bucket | Accepted risk, cost-driven |
| CKV_AWS_252 | CloudTrail trail | Not applicable |
| CKV_AWS_35 | CloudTrail trail | Accepted risk, cost-driven |
| CKV2_AWS_10 | CloudTrail trail | Resolved: CloudWatch Logs integration built |
| CKV_AWS_158 | Audit log group | Accepted risk, cost-driven |
| CKV_AWS_338 | Audit log group | Rejected: S3 is the system of record |
| CKV_AWS_26 | Security alerts topic | Accepted risk, cost-driven |
| CKV2_AWS_5 | Databricks workspace security group | Not applicable |
| CKV2_AWS_5 | Databricks endpoint security group | False positive, verified in AWS |
| CKV2_AWS_11 | Databricks VPC | False positive, verified in AWS |
| CKV2_AWS_12 | Databricks VPC | False positive, verified in AWS |
| CKV_AWS_24 / 25 / 260 | Intra-cluster ingress rules | False positive |

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

### CKV_AWS_356 / CKV_AWS_111 — residual `"*"` on the deploy role

Three statements on the deploy role still use `"*"`, each because AWS offers no
narrower form: the account password policy, which has no ARN; `ec2:Describe*`,
which does not support resource-level permissions; and the CloudWatch Logs
log-delivery actions that VPC flow logs to S3 depend on, which have no resource
type. EC2 creation is also `"*"` on resource but constrained by a `RequestTag`
condition. The subsections below record the original password-policy case.

#### Residual `"*"` on the account password policy

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

### CKV_AWS_252 — no SNS topic on the trail

CloudTrail can publish a notification each time a log file is delivered. There is no
subscriber for that, and delivery notifications are not the control people assume
they are: they say a file arrived, not that anything suspicious is in it.

Residual risk: none meaningful. The useful alerting control is a CloudWatch metric
filter on the log contents, recorded below as the next increment.

### CKV_AWS_35 — trail logs not encrypted with a KMS CMK

Logs are encrypted at rest with SSE-S3, and the bucket denies non-TLS requests. The
difference a customer-managed key makes is an independent audit trail of decryption
and a revocation path, at a fixed monthly charge plus per-request cost.

Residual risk: no key-level audit or revocation for log data.

Revisit when: the same trigger as CKV_AWS_145 on the state bucket. These two should
be decided together, since a single key can serve both.

### CKV2_AWS_10 — trail not integrated with CloudWatch Logs

This one is wanted, and deferred rather than rejected.

Sending the trail to CloudWatch Logs is what turns a record into an alarm: metric
filters can match an event pattern and fire in near real time. It is specifically
what would close the gap the break-glass runbook names, where emergency
administrator access currently raises no alert.

It is not free. CloudWatch Logs bills per GB ingested and stored, though management
events in an account this quiet are a small volume. It also needs a log group and an
IAM role for CloudTrail to write through, which means more deploy-role permissions.

Deferred only to keep this change small after two permission-scoping corrections in
one session. It is the recommended next increment of the audit baseline.

**Resolved on 2026-09-17.** The trail now streams to CloudWatch Logs, with metric
filters and alarms on break-glass administrator writes and on root account use.
See `alerting.tf`.

### CKV_AWS_158 / CKV_AWS_338 / CKV_AWS_26 — the alerting layer

Three findings on the CloudWatch log group and the SNS topic, all the same trade-off
in different clothes.

`CKV_AWS_158` wants the log group encrypted with a customer-managed KMS key, and
`CKV_AWS_26` wants the same for the SNS topic. Both add a fixed monthly charge plus
per-request cost against a USD 50 ceiling. The SNS messages are alarm state changes
naming an event type; they do not carry log contents.

`CKV_AWS_338` wants at least a year of retention in CloudWatch Logs. That misreads
what this copy is for. CloudWatch Logs here is the trigger mechanism, not the system
of record: events stream in so metric filters can match them within minutes. The
durable year of history lives in S3, where storage is an order of magnitude cheaper.
Keeping a year in both would pay twice for the same evidence.

Residual risk: no key-level audit or revocation on the alerting path, and the
CloudWatch copy of events older than 90 days is gone. The S3 copy is unaffected.

Revisit when: the KMS decision is taken for the state and trail buckets, since one
key can serve all of them; or if an investigation ever needs metric-filter matching
over data older than 90 days, which S3 and Athena would serve better anyway.

### CKV2_AWS_5 — security group not attached to a resource

The check looks for security groups that exist but are attached to nothing, on the
reasonable assumption that they are leftovers from a deleted resource.

Not applicable here. `aws_security_group.databricks_workspace` is attached at
runtime by Databricks, to the EC2 instances it launches for cluster nodes.
Terraform never creates those instances, so from Terraform's point of view the
group is permanently unattached. That is the expected steady state of a
customer-managed VPC, not a leftover.

The paired `aws_security_group.databricks_endpoint` passes the same check, because
it is attached to the STS and Kinesis interface endpoints, which Terraform does
create. The contrast is a useful sanity check: if the workspace group were ever
meant to be attached by Terraform, the endpoint group shows what that looks like.

Residual risk: none. An unattached security group grants nothing.

Revisit when: Terraform ever creates the compute itself, which would mean we had
stopped using Databricks-managed clusters.

### A scanner that was partly blind, and the false positives it then raised

Until 2026-09-24 every Databricks network resource sat behind a `count` that
evaluated to zero, and Checkov evaluated them as absent. The earlier clean result
of "205 passed, 0 failed" therefore said nothing about the network. When the flag
was turned on, nine findings appeared, and the branch protection correctly blocked
the merge. All nine are false positives, and they fall into two groups.

**Graph checks that do not follow `[0]` indexes.** `CKV2_AWS_11` (flow logs),
`CKV2_AWS_12` (default security group) and `CKV2_AWS_5` on the endpoint security
group are relationship checks. The flow log, the emptied default security group and
the endpoint attachments all exist in the code, but reference their targets through
`count` indexes that Checkov's graph does not resolve. Each is verified directly in
AWS after apply rather than accepted on the reasoning alone.

**Self-referencing rules read as open.** `CKV_AWS_24`, `CKV_AWS_25` and
`CKV_AWS_260` flag SSH, RDP and HTTP open to `0.0.0.0/0` on the two intra-cluster
rules. Those rules take their source from the security group itself, which
Databricks requires so cluster nodes can talk to each other. Nothing outside that
group can use them.

Residual risk: none from the findings themselves. The lesson is the general one:
a scan of code that creates nothing is not a scan of what will be created.

Revisit when: Checkov resolves count-indexed references, or the network is
refactored away from `count`.

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
