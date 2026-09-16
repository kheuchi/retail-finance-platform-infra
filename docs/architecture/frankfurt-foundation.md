# Frankfurt Foundation: Network, Audit and Databricks

Status: **proposal**. Nothing in this document is deployed. It exists so the cost and
security trade-offs can be decided before anything chargeable is created.

## TL;DR

The next layer of the platform needs three things: somewhere for compute to run
(network), a record of what happened (audit), and the lakehouse itself (Databricks).

Two of these are nearly free and should be built. One is not, and is where the entire
budget will go.

- **Audit** costs roughly USD 1 per month. Build it first. It is the control most
  visibly missing today.
- **Network** costs nothing if we stay serverless, and about USD 37 per month the
  moment we add a NAT Gateway. Avoid the NAT Gateway.
- **Databricks** is the real cost and the real risk. Idle infrastructure is free;
  running compute is not. It needs hard guardrails before the first cluster starts.

Recommendation: build audit now, defer the network until Databricks forces the
question, and treat Databricks as a time-boxed exercise with an explicit stop.

## Cost framing

The account has a USD 100 promotional credit and a USD 50 per month personal-spend
ceiling. Enabling AWS Organizations or Control Tower forfeits the credit, so neither
is in scope (decision D-009).

What matters more than any single price is the *shape* of a cost:

| Shape | Behaviour | Examples here |
|---|---|---|
| Free | No charge regardless of use | VPC, subnets, security groups, S3 Gateway Endpoint, first CloudTrail management trail |
| Hourly | Bills whether or not you use it | NAT Gateway, Interface VPC Endpoints, EC2, Databricks classic clusters |
| Usage | Bills per event or per GB | S3 storage, Config items, CloudTrail data events, Databricks DBUs |

Hourly costs are the dangerous ones on a small budget. They accrue while you sleep and
they do not care that the demo is finished. Every hourly resource in this design is
called out explicitly below.

**All figures are estimates for `eu-central-1` and must be re-checked against current
AWS and Databricks pricing before anything is enabled.** They are included to show
relative magnitude and to support a decision, not as a quotation.

## 1. Audit baseline

### What it is

- **CloudTrail** records AWS API calls: who did what, from where, when. *Management
  events* cover control-plane actions such as creating a bucket or changing a role.
  *Data events* cover object-level actions such as reading a specific S3 object.
- **AWS Config** records the configuration of each resource over time and can
  evaluate rules against it.

Plain words: CloudTrail is the security camera on the door. Config is the periodic
inventory of what is in the room.

### Proposal

| Item | Shape | Estimated monthly | Recommendation |
|---|---|---|---|
| CloudTrail management trail, multi-region, to S3 | Free for the first copy | ~USD 0 | **Build** |
| S3 storage for trail logs | Usage | Well under USD 1 at this volume | **Build** |
| CloudTrail data events on the state bucket | Usage, per 100k events | Low, but unbounded in principle | Build, with a lifecycle rule |
| AWS Config recorder, all resource types | Usage, per configuration item | Genuinely uncertain; scales with resource churn | **Defer** |
| AWS Config, scoped to IAM and S3 only | Usage | Small | Consider after CloudTrail |
| GuardDuty, Security Hub | — | Unavailable on the current plan | Document as an exception |

The trail bucket needs the same protections as the state bucket: versioning, public
access block, TLS-only policy, lifecycle expiry, plus a bucket policy allowing the
CloudTrail service principal to write.

Note the honest limitation: in a single account, logs sit alongside the workloads they
describe, and a sufficiently privileged administrator can alter both. That is the gap
a Log Archive account closes, and it is exactly what Control Tower would give us. It
cannot be fixed within this constraint, only documented.

### Why first

It is the cheapest control with the highest portfolio value, it closes the most
obvious gap in the current verified state, and it is a prerequisite for evidence in
the Well-Architected review. It also makes break-glass use auditable, which the
runbook currently lists as a known weakness.

## 2. Network

### The central question

Do we need a VPC at all?

A VPC is only required if something runs inside it. Databricks *serverless* compute
runs in the Databricks-owned AWS account, not ours. Databricks *classic* compute runs
in our account and does need a VPC.

So the network decision is downstream of the Databricks decision, which is why this
section is deliberately second.

### Serverless-first (recommended)

Cost: **USD 0**. No VPC to manage, no NAT Gateway, no endpoints, nothing hourly.

This is the right default. The default VPC is not used for workloads (operating rule
5), and if nothing of ours runs in a VPC, that rule is satisfied trivially.

### If classic compute becomes necessary

| Component | Shape | Estimated monthly | Note |
|---|---|---|---|
| VPC, subnets, route tables, security groups | Free | USD 0 | |
| S3 Gateway Endpoint | Free | USD 0 | Always add this; it also keeps S3 traffic off the internet |
| Internet Gateway | Free | USD 0 | The charge is on data transfer, not the gateway |
| **NAT Gateway** | **Hourly** | **~USD 37 plus per-GB processing** | **Avoid.** Roughly 75% of the monthly ceiling, burned whether used or not |
| Interface VPC Endpoints (STS, Kinesis, and others) | Hourly, each | ~USD 8 each | Databricks classic requires several; the total rivals the NAT Gateway |

This is the trap in the design. A conventional private-subnet architecture with a NAT
Gateway consumes the entire budget before a single row of data is processed. The
enterprise-correct answer and the affordable answer diverge here, and the honest move
is to build the affordable one and *document* the enterprise one as a reference
design with its cost stated.

## 3. Databricks foundation

### What has to exist

- A **Databricks account** and a **workspace** in `eu-central-1`.
- An **S3 bucket** for workspace root storage.
- A **cross-account IAM role** letting Databricks operate in our account.
- **Unity Catalog**: the governance layer holding catalogs, schemas, tables, lineage
  and access grants. It needs its own S3 location and IAM role.

Idle cost of all of the above: effectively **USD 0**. Buckets and roles cost nothing
meaningful when empty. A workspace with no running compute does not bill.

### Where the money goes

Databricks bills **DBUs** (Databricks Units, a compute-time unit) on top of any
underlying AWS EC2 cost. A cluster left running overnight is the single most likely
way to breach the USD 50 ceiling on this project.

Required guardrails before any compute starts:

1. Auto-termination on every cluster, set aggressively (10 to 20 minutes).
2. Smallest available node size; single node where the workload allows.
3. No always-on SQL warehouse. Serverless SQL with a short auto-stop instead.
4. Job clusters rather than all-purpose clusters for scheduled work, since they
   terminate when the job ends.
5. A hard calendar stop. The build is one week; compute should be off outside it.
6. Check the AWS Budget before and after each working session. It already alerts at
   50%, 80% and 100% forecast.

### Open questions this needs answered

These are genuine decisions that cannot be made from the code:

- Which Databricks pricing tier, and whether the free trial is being used, since the
  trial window interacts with the one-week build.
- Whether serverless compute is available on the chosen tier in `eu-central-1`.
- Whether the AWS credit applies to Databricks charges purchased through AWS
  Marketplace, or whether Databricks bills separately. This materially changes the
  effective budget and should be confirmed before committing.

## Recommended sequence

1. **Audit baseline.** CloudTrail management trail plus a protected log bucket.
   About USD 1 per month, no hourly resources, closes the largest current gap.
2. **Databricks account and workspace, with zero compute.** Unity Catalog, storage
   and IAM only. Proves the integration at no cost.
3. **A single time-boxed compute exercise.** Smallest node, aggressive
   auto-termination, run the end-to-end slice, then stop.
4. **Network only if step 3 forces it.** If classic compute is unavoidable, build the
   VPC with an S3 Gateway Endpoint and no NAT Gateway, and document what a production
   design would add and what it would cost.
5. **Teardown.** Compute off, workspace suspended or deleted, S3 lifecycle applied.
   The audit trail stays; it is cheap, and it is the evidence.

## Estimated steady-state cost

| Scenario | Estimated monthly | Within ceiling |
|---|---|---|
| Audit baseline only | ~USD 1 | Yes, comfortably |
| Audit plus Databricks idle, no compute | ~USD 1 to 2 | Yes |
| Audit plus serverless Databricks, bounded session use | Depends on DBU consumption | Only with the guardrails above |
| Audit plus VPC with NAT Gateway | ~USD 38 before any compute | Technically yes, practically no |
| Anything with an always-on cluster or SQL warehouse | Breaches quickly | **No** |

## Approval gate

Nothing here gets built without an explicit decision, because steps 2 onward can
create chargeable resources. The audit baseline (step 1) is the only part worth
recommending without further cost discussion, and even that should go through a
reviewed Terraform plan like everything else.
