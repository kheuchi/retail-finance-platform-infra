# Databricks Prerequisites

## TL;DR

The AWS side of the Databricks setup is done as far as it can go without you. Two
storage buckets exist and are locked down.

Everything that remains is blocked on one value: your **Databricks account ID**,
which does not exist until you create a Databricks account. Once you have it, the
rest is a short, testable piece of work.

Do not create the Databricks account until you are ready to use it. The trial is
14 days and the clock starts at sign-up.

## What is built

| Resource | Purpose |
|---|---|
| `…-dbx-root-<account>-eu-central-1` | Workspace root storage. Databricks keeps the workspace's own system data here. Historically called the DBFS root. |
| `…-dbx-uc-<account>-eu-central-1` | Unity Catalog managed storage. Governed tables physically live here. |

Both carry the same protections as the rest of the estate, and all of it is
verified against AWS rather than assumed:

- versioning enabled, so a bad overwrite is recoverable
- all four public-access blocks on
- bucket-owner-enforced ownership, so ACLs cannot reintroduce cross-account access
- SSE-S3 (AES-256) encryption at rest
- a bucket policy denying any request that does not use TLS
- a lifecycle rule reaping superseded versions after 30 days and abandoned uploads
  after 7

The lifecycle rule deliberately never expires current objects. These are data
buckets, not log buckets: the correct retention for a finance table is a data
governance decision, not an infrastructure default.

Cost today: effectively zero. Empty S3 buckets bill only for what they store.

## What is not built, and why

Three things remain, and all three are blocked on the same missing value.

| Missing piece | What it does | Why it is blocked |
|---|---|---|
| Databricks cross-account IAM role | Lets Databricks operate in your AWS account | Trust policy requires `sts:ExternalId` set to your Databricks account ID |
| Unity Catalog storage credential role | Lets Unity Catalog read and write the managed bucket | Same external ID requirement |
| Databricks statements on both bucket policies | Grants Databricks access to the buckets | The policy condition is keyed on your Databricks account ID |

Per the AWS setup documentation, Databricks assumes these roles from its own AWS
account, `414351767826`, and the external ID must be **your** Databricks account ID,
not that number.

This was left unwritten on purpose. IAM written against an identifier that does not
exist yet cannot be applied and cannot be tested, and an untested IAM policy is a
guess wearing a policy document's clothing. Two permission-scoping failures earlier
in this project both surfaced only at runtime.

## What you need to do

1. **Decide when to start.** The trial gives USD 400 of Databricks credit valid for
   14 days. The AWS promotional credit does not cover Databricks charges, so this is
   the budget for the lakehouse work. Start it when there is a clear run at the
   build, not before.
2. **Sign up** for the Databricks free trial, choosing AWS as the cloud and
   `eu-central-1` (Frankfurt) as the region, so it matches everything already built.
3. **Copy the account ID** from the Databricks account console. It is a UUID, not the
   `414351767826` number above.
4. **Hand it over.** It is an identifier, not a secret, but it belongs in the
   Git-ignored `bootstrap/terraform.tfvars` and in the CI secret, not in the
   repository.

## What happens next

With that value present:

- the cross-account role and the Unity Catalog storage credential role get built and
  applied through the pipeline, as everything else has been;
- the Databricks access statements are added to both bucket policies;
- the workspace and metastore are created and connected;
- then, and only then, does any compute start.

## Before the first cluster

The single most likely way to breach the USD 50 ceiling on this project is a cluster
left running. The guardrails agreed in the foundation design:

1. Auto-termination on every cluster, 10 to 20 minutes.
2. Smallest available node size, single node where the workload allows.
3. No always-on SQL warehouse; serverless SQL with a short auto-stop.
4. Job clusters rather than all-purpose clusters for scheduled work.
5. A hard calendar stop. Compute off outside the build window.
6. Check the AWS Budget before and after each session. It alerts at 50%, 80% and
   100% forecast, and those alerts now reach a confirmed inbox.

Note the asymmetry worth remembering: the AWS Budget watches AWS spend. Databricks
DBUs are billed by Databricks, so the AWS Budget will not see them. Watch the
Databricks console's own usage page as well.
