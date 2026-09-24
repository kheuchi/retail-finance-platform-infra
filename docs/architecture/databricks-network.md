# Databricks Network Architecture

## TL;DR

Databricks can run its clusters in a VPC it creates and controls in your account,
or in one you define yourself. This project defines its own, because a network you
did not write is a network you cannot evidence.

The design has **no internet gateway and no NAT gateway**. There is no route out of
this VPC to the public internet. Everything Databricks needs from AWS arrives
through VPC endpoints instead. That is stricter than the default, and more expensive: see the cost section.

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
| STS access | interface endpoint, 2 AZs | ~USD 16/month |
| Kinesis access | interface endpoint, 2 AZs | ~USD 16/month |
| Databricks workspace API | back-end PrivateLink endpoint, 2 AZs | ~USD 16/month |
| Databricks SCC relay | back-end PrivateLink endpoint, 2 AZs | ~USD 16/month |
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

We take the second, for two reasons:

1. **It is the stronger control.** No public egress path exists, so exfiltration
   through one is not a risk to be monitored; it is a capability that was never
   created.
2. **It matches an existing project decision.** Control `NET-2` already says no NAT
   gateway, because it bills hourly whether or not anything uses it.

It is **not** cheaper: see the cost section below. An earlier draft claimed it was,
and that claim was wrong.

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

## Back-end PrivateLink

Two further interface endpoints point at services Databricks runs in its own AWS
account (`414351767826`): one for the workspace REST API, one for the secure
cluster connectivity relay. With private DNS enabled, the hostnames
`frankfurt.privatelink.cloud.databricks.com` and
`tunnel.privatelink.eu-central-1.cloud.databricks.com` resolve to private addresses
inside the VPC, so cluster nodes reach the control plane without any route to the
internet. Both services were confirmed reachable from this account on 2026-09-24,
owned by the Databricks AWS account, available in all three Frankfurt zones, and
auto-accepting connections.

Back-end PrivateLink **requires the Databricks Enterprise tier**. The account was
upgraded from Premium on 2026-09-24 for this reason; the trial credit carried over.

Front-end PrivateLink, for users reaching the web interface privately, is not built.
Users reach the UI over the internet, authenticated by Databricks. That is a
deliberate scope line: it would need a client VPN or Direct Connect to be useful.

## Cost, corrected twice

An earlier version of this page put the network at USD 15, then USD 29 per month.
Both were wrong. Interface endpoints bill **per endpoint, per availability zone,
per hour**, and the first estimate also omitted the two PrivateLink endpoints. The
correct figure is four interface endpoints across two zones, eight billed
attachments at about USD 0.011 an hour each: **roughly USD 64 per month**.

For comparison, a NAT gateway design is about USD 38 per month. The fully-private
design is **not** the cheaper one. It was chosen because it is the only design in
which "no public egress path exists" is literally true, which is the property a
finance function holding price-sensitive figures would ask for.

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
no workspace attached means paying roughly USD 64 a month for nothing.
