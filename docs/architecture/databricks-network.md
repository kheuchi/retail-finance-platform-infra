# Databricks Network Architecture

## TL;DR

Databricks can run its clusters in a VPC it creates and controls in your account,
or in one you define yourself. This project defines its own, because a network you
did not write is a network you cannot evidence.

The design has **no internet gateway and no NAT gateway**. There is no route out of
this VPC to the public internet. Everything Databricks needs from AWS arrives
through VPC endpoints instead. That is both cheaper and stricter than the default.

None of it exists yet. Every resource is gated behind `enable_databricks_network`,
which defaults to `false`, so the code is reviewed and merged without anything
being created or billed.

## Why this matters for a finance department

The scenario is the accounting function of a large retailer, not a bank. The
controls that matter most are the ones that protect **financial reporting**: can
you prove the revenue figure, can you show who changed the transformation that
produced the margin report, and can you demonstrate the record was not altered.

A network reads onto that in two specific ways:

- **Containment.** The general ledger extracts, the budget files and the margin
  calculations sit in S3. If the compute that reads them has no path to the public
  internet, the question "could this data have been copied out" has a structural
  answer rather than a policy answer.
- **Evidence.** VPC flow logs record which address talked to which, on which port,
  and whether it was allowed. Combined with CloudTrail, that is the network half of
  an audit trail an external reviewer can test.

Neither is exotic. Both are the sort of control an internal audit function asks
about when a finance process moves to the cloud.

## What is built

| Component | Choice | Cost |
|---|---|---|
| VPC | `10.20.0.0/16`, DNS hostnames and resolution on | free |
| Workspace subnets | two `/22`, one per availability zone, no public IPs | free |
| Endpoint subnets | two `/24`, isolating endpoint network interfaces | free |
| Route table | one, carrying only the local route | free |
| Internet gateway | **none** | — |
| NAT gateway | **none** | — |
| S3 access | gateway endpoint | **free** |
| STS access | interface endpoint | ~USD 7.30/month |
| Kinesis access | interface endpoint | ~USD 7.30/month |
| Flow logs | all traffic, to the CloudTrail bucket | pennies at this volume |

Subnet sizing follows the Databricks requirement that each workspace subnet carry a
netmask between `/17` and `/26`. Databricks consumes two IP addresses per node, one
for management traffic and one for the Spark application, so a `/22` supports
roughly 500 nodes. That is far more than this project needs, but subnets cost
nothing and a `/26` would cap a single cluster at about 30 nodes for no saving.

## Why no NAT gateway

The Databricks documentation offers two shapes for a customer-managed VPC. The
standard one routes outbound traffic through an internet gateway and a NAT gateway.
The fully-private one removes both and relies on VPC endpoints.

We take the second, for three reasons in this order:

1. **It is the stronger control.** No public egress path exists, so exfiltration
   through one is not a risk to be monitored; it is a capability that was never
   created.
2. **It matches an existing project decision.** Control `NET-2` already says no NAT
   gateway, because it bills hourly whether or not anything uses it.
3. **It is cheaper.** A NAT gateway is roughly USD 32 a month before data
   processing charges. Two interface endpoints are roughly USD 15.

This was learned the expensive way. An Azure Databricks workspace created on
2026-09-21 deployed a NAT gateway automatically, because the Azure trial tier
forces a hybrid workspace and does not offer serverless. It began billing at
roughly USD 33 a month from the moment the deployment finished, with no cluster
ever started. The workspace was deleted the same day. The lesson is recorded here
because it generalises: **the Databricks trial credit covers Databricks licence
charges, never the cloud infrastructure the workspace creates in your account.**

## Security group design

Two groups, and no rule in either permits `0.0.0.0/0`.

**Workspace group**, applied by Databricks to cluster nodes:

| Direction | Port | Destination | Why |
|---|---|---|---|
| in / out | all TCP and UDP | itself | Cluster nodes talk to each other. Scoped by group membership, not by CIDR |
| out | 443 | endpoint group | STS, Kinesis, later the Databricks PrivateLink endpoints |
| out | 443 | S3 prefix list | S3 via the gateway endpoint |
| out | 6666 | VPC CIDR | Secure cluster connectivity relay |
| out | 8443–8451 | VPC CIDR | Control plane API and Unity Catalog lineage |

**Endpoint group**, applied to the interface endpoints: inbound 443 from the
workspace group, nothing else.

Two deliberate omissions:

- **Port 3306 is not opened.** The Databricks documentation lists it for the legacy
  Hive metastore. This platform governs data through Unity Catalog, so the port
  would be an unused hole.
- **The VPC default security group is stripped of all rules.** A default security
  group permits free traffic between its members, and Terraform cannot delete it.
  Emptying it means anything that lands there by accident is isolated rather than
  quietly permitted.

## What is not built yet

**Back-end PrivateLink.** Two further interface endpoints are needed, pointing at
the Databricks workspace API and the secure cluster connectivity relay. Their VPC
endpoint service names depend on the Databricks account and region, and they must
be registered in the Databricks account console before a workspace can use them.

This matters for sequencing: **until those exist, the VPC is private-ready but not
connected.** A workspace launched against it could not reach the control plane,
because there is no NAT and no PrivateLink, which is to say no path at all. They
add roughly USD 15 a month, taking the network to about USD 29.

They are deliberately not written yet, for the same reason the Databricks IAM roles
are not: an endpoint service name that does not exist cannot be applied and cannot
be tested, and untested infrastructure is a guess in a policy document's clothing.

**Customer-managed KMS keys** for the workspace root and for EBS volumes on cluster
nodes. Recorded as `DAT-9` in the control matrix, deferred on cost.

## Turning it on

```hcl
# bootstrap/terraform.tfvars
enable_databricks_network = true
```

Then let the pipeline plan it before applying, as with every other change. The plan
should show the VPC, four subnets, one route table, three security groups, three
VPC endpoints and one flow log.

The two interface endpoints begin billing the moment they are created, so turn this
on when the Databricks account is ready to consume it, not before.

## Registering with Databricks

Three values come out of the Terraform and go into the Databricks account console
when creating a network configuration:

```
databricks_vpc_id
databricks_workspace_subnet_ids
databricks_workspace_security_group_id
```

They are `null` until the flag is turned on.

## Teardown

Set the flag back to `false` and apply. The interface endpoints are the only
recurring charge and they disappear with it. The VPC, subnets and security groups
cost nothing, so there is no urgency to remove them, but leaving the flag on with
no workspace attached means paying roughly USD 15 a month for nothing.
