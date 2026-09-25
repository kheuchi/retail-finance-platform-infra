# Customer-managed VPC for the Databricks classic compute plane.
#
# Why a customer-managed VPC at all. In the default Databricks deployment, the
# clusters run in a VPC that Databricks creates and owns in your account, and you
# have no say over its network controls. A customer-managed VPC means the compute
# runs inside a network this repository defines: our CIDR, our subnets, our
# security groups, our flow logs. That is the difference between "we use a managed
# service" and "we can evidence how the service is contained".
#
# What is deliberate here, and the reason for each choice:
#
#   - No internet gateway and no NAT gateway. There is no route out of this VPC to
#     the public internet at all. Data cannot leave by a public path because no
#     public path exists. This is the "isolated environment" pattern in the
#     Databricks network documentation.
#   - Egress is confined to the VPC CIDR, the endpoint security group, and the S3
#     prefix list. No security group rule in this file allows 0.0.0.0/0.
#   - Reachability to AWS services is provided by VPC endpoints instead: an S3
#     gateway endpoint, which is free, and interface endpoints for STS and Kinesis,
#     which Databricks requires.
#   - Port 3306 is omitted. The Databricks documentation lists it for the legacy
#     Hive metastore; this platform governs data through Unity Catalog, so opening
#     it would be an unused hole.
#
#   - Back-end PrivateLink carries every conversation with the Databricks control
#     plane: one interface endpoint for the workspace REST API, one for the secure
#     cluster connectivity relay. This is what makes the no-egress design work at
#     all, and it requires the Databricks Enterprise tier.
#
# Cost. Everything in this file is gated behind var.enable_databricks_network,
# which defaults to false, so none of it exists until someone deliberately turns it
# on. When enabled, the running cost is the four interface endpoints (STS, Kinesis,
# workspace, relay). Interface endpoints bill per endpoint per availability zone
# per hour, so four endpoints across two zones is eight billed attachments, roughly
# USD 64 a month in eu-central-1. An earlier version of this comment priced them per
# endpoint only, which understated the cost by half. The VPC, subnets, route
# tables, security groups and S3 gateway endpoint are free. There is no NAT.
#
# See docs/architecture.md and cmdb.yml (stacks.bootstrap.databricks_network).

# Gated like everything else in this file, and for a reason worth recording: a
# data source is read during plan whether or not anything references it, so an
# ungated one demands its IAM permission before the apply that grants that
# permission can even be planned. Counting it to zero keeps the permissions-first
# apply plannable.
data "aws_availability_zones" "available" {
  count = local.databricks_network_count

  state = "available"
}

locals {
  databricks_network_count = var.enable_databricks_network ? 1 : 0
  databricks_subnet_count  = var.enable_databricks_network ? 2 : 0

  # Databricks requires each workspace subnet to carry a netmask between /17 and
  # /26, and it consumes two IP addresses per node: one for management traffic and
  # one for the Spark application. A /22 therefore supports roughly 500 nodes,
  # which is far beyond anything this project will run, but sizing down to /26
  # would cap a single cluster at about 30 nodes for no saving: subnets are free.
  databricks_workspace_subnet_cidrs = [
    cidrsubnet(var.databricks_vpc_cidr, 6, 0),
    cidrsubnet(var.databricks_vpc_cidr, 6, 1)
  ]

  # Interface endpoints live in their own small subnets rather than in the
  # workspace subnets. Databricks recommends this, and it keeps the endpoint
  # network interfaces in a separate blast radius from the compute.
  databricks_endpoint_subnet_cidrs = [
    cidrsubnet(var.databricks_vpc_cidr, 8, 8),
    cidrsubnet(var.databricks_vpc_cidr, 8, 9)
  ]

  databricks_vpc_name = "${var.project_name}-dbx"
}

resource "aws_vpc" "databricks" {
  count = local.databricks_network_count

  # Accepted, reviewed exceptions. See docs/security/checkov-exceptions.md.
  # Both are graph checks that fail to follow count-indexed references. The flow
  # log and the emptied default security group exist and were verified in AWS.
  #checkov:skip=CKV2_AWS_11:Flow logs are enabled by aws_flow_log.databricks, which Checkov's graph does not link through the [0] index.
  #checkov:skip=CKV2_AWS_12:The default security group is emptied by aws_default_security_group.databricks, which Checkov's graph does not link through the [0] index.

  cidr_block = var.databricks_vpc_cidr

  # Both are mandatory for interface endpoints to resolve to their private
  # addresses. Without them the endpoints exist but nothing finds them.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.databricks_vpc_name
  }
}

# Workspace subnets: where Databricks places cluster nodes. Private by
# construction, because the route table they attach to has no route to anywhere
# outside the VPC.
resource "aws_subnet" "databricks_workspace" {
  count = local.databricks_subnet_count

  vpc_id            = aws_vpc.databricks[0].id
  cidr_block        = local.databricks_workspace_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available[0].names[count.index]

  # No public addressing. A node here cannot be reached from, or reach, the
  # internet.
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.databricks_vpc_name}-workspace-${data.aws_availability_zones.available[0].names[count.index]}"
    Tier = "workspace"
  }
}

resource "aws_subnet" "databricks_endpoint" {
  count = local.databricks_subnet_count

  vpc_id                  = aws_vpc.databricks[0].id
  cidr_block              = local.databricks_endpoint_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available[0].names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.databricks_vpc_name}-endpoint-${data.aws_availability_zones.available[0].names[count.index]}"
    Tier = "endpoint"
  }
}

# One route table for the whole VPC, carrying only the implicit local route.
# There is deliberately no aws_internet_gateway and no aws_nat_gateway in this
# file, so there is nothing for a 0.0.0.0/0 route to point at even by accident.
resource "aws_route_table" "databricks" {
  count = local.databricks_network_count

  vpc_id = aws_vpc.databricks[0].id

  tags = {
    Name = "${local.databricks_vpc_name}-private"
  }
}

resource "aws_route_table_association" "databricks_workspace" {
  count = local.databricks_subnet_count

  subnet_id      = aws_subnet.databricks_workspace[count.index].id
  route_table_id = aws_route_table.databricks[0].id
}

resource "aws_route_table_association" "databricks_endpoint" {
  count = local.databricks_subnet_count

  subnet_id      = aws_subnet.databricks_endpoint[count.index].id
  route_table_id = aws_route_table.databricks[0].id
}

# The default security group of a VPC allows all traffic between its members.
# Terraform cannot delete it, but it can strip every rule from it, which is what
# this does. Anything that lands on the default group by mistake is then isolated
# rather than silently permitted.
resource "aws_default_security_group" "databricks" {
  count = local.databricks_network_count

  vpc_id = aws_vpc.databricks[0].id

  tags = {
    Name = "${local.databricks_vpc_name}-default-deny-all"
  }
}

resource "aws_security_group" "databricks_workspace" {
  count = local.databricks_network_count

  # Accepted, reviewed exception. See docs/security/checkov-exceptions.md.
  #checkov:skip=CKV2_AWS_5:Attached at runtime by Databricks to cluster nodes, which Terraform does not create. An unattached group here is the expected steady state, not a leftover.

  name        = "${local.databricks_vpc_name}-workspace"
  description = "Databricks classic compute plane nodes. No internet egress."
  vpc_id      = aws_vpc.databricks[0].id

  tags = {
    Name = "${local.databricks_vpc_name}-workspace"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "databricks_endpoint" {
  count = local.databricks_network_count

  #checkov:skip=CKV2_AWS_5:Attached to all four interface endpoints; Checkov's graph does not follow the [0]-indexed reference. See docs/security/checkov-exceptions.md.

  name        = "${local.databricks_vpc_name}-endpoint"
  description = "Interface VPC endpoints serving the Databricks compute plane."
  vpc_id      = aws_vpc.databricks[0].id

  tags = {
    Name = "${local.databricks_vpc_name}-endpoint"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Cluster nodes talk to each other on every port. Databricks requires this and
# scopes it by security group membership rather than by CIDR, which is the
# tighter form: only instances carrying this group can participate.
resource "aws_vpc_security_group_ingress_rule" "databricks_workspace_self_tcp" {
  count = local.databricks_network_count

  # The source is this security group itself, not an address range. Checkov reads
  # an all-ports rule with no CIDR as open to 0.0.0.0/0. It is not.
  #checkov:skip=CKV_AWS_24:Source is the security group itself, not 0.0.0.0/0.
  #checkov:skip=CKV_AWS_25:Source is the security group itself, not 0.0.0.0/0.
  #checkov:skip=CKV_AWS_260:Source is the security group itself, not 0.0.0.0/0.

  security_group_id            = aws_security_group.databricks_workspace[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Intra-cluster TCP between compute plane nodes"
}

resource "aws_vpc_security_group_ingress_rule" "databricks_workspace_self_udp" {
  count = local.databricks_network_count

  # The source is this security group itself, not an address range. Checkov reads
  # an all-ports rule with no CIDR as open to 0.0.0.0/0. It is not.
  #checkov:skip=CKV_AWS_24:Source is the security group itself, not 0.0.0.0/0.
  #checkov:skip=CKV_AWS_25:Source is the security group itself, not 0.0.0.0/0.
  #checkov:skip=CKV_AWS_260:Source is the security group itself, not 0.0.0.0/0.

  security_group_id            = aws_security_group.databricks_workspace[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "udp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Intra-cluster UDP between compute plane nodes"
}

resource "aws_vpc_security_group_egress_rule" "databricks_workspace_self_tcp" {
  count = local.databricks_network_count

  security_group_id            = aws_security_group.databricks_workspace[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Intra-cluster TCP between compute plane nodes"
}

resource "aws_vpc_security_group_egress_rule" "databricks_workspace_self_udp" {
  count = local.databricks_network_count

  security_group_id            = aws_security_group.databricks_workspace[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "udp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Intra-cluster UDP between compute plane nodes"
}

# Reaching STS and Kinesis, and later the Databricks PrivateLink endpoints, all of
# which terminate on network interfaces inside the endpoint subnets.
resource "aws_vpc_security_group_egress_rule" "databricks_workspace_to_endpoints" {
  count = local.databricks_network_count

  security_group_id            = aws_security_group.databricks_workspace[0].id
  referenced_security_group_id = aws_security_group.databricks_endpoint[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS to interface VPC endpoints"
}

# S3 through the gateway endpoint. Gateway endpoints are reached by route rather
# than by address, so the destination is AWS's managed prefix list for S3 in this
# region, not a CIDR we invent.
resource "aws_vpc_security_group_egress_rule" "databricks_workspace_to_s3" {
  count = local.databricks_network_count

  security_group_id = aws_security_group.databricks_workspace[0].id
  prefix_list_id    = data.aws_prefix_list.s3[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to S3 via the gateway endpoint"
}

# Secure cluster connectivity. Databricks opens this relay outbound from the node;
# the control plane never initiates a connection inwards. With back-end PrivateLink
# the relay resolves to a private address inside this VPC, which is why the
# destination is the VPC CIDR and not the internet.
resource "aws_vpc_security_group_egress_rule" "databricks_workspace_scc_relay" {
  count = local.databricks_network_count

  security_group_id = aws_security_group.databricks_workspace[0].id
  cidr_ipv4         = var.databricks_vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 6666
  to_port           = 6666
  description       = "Secure cluster connectivity relay via back-end PrivateLink"
}

# Control plane APIs and Unity Catalog lineage streaming. 8443 and 8445 are
# internal compute-to-control-plane calls, 8444 carries Unity Catalog lineage, and
# 8446-8451 are reserved by Databricks for future use.
resource "aws_vpc_security_group_egress_rule" "databricks_workspace_control_plane" {
  count = local.databricks_network_count

  security_group_id = aws_security_group.databricks_workspace[0].id
  cidr_ipv4         = var.databricks_vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 8443
  to_port           = 8451
  description       = "Control plane API and Unity Catalog lineage via back-end PrivateLink"
}

# The relay endpoint listens on 6666 for secure cluster connectivity. Databricks'
# PrivateLink guide requires the endpoint security group to admit 443 and 6666 from
# the compute plane; 2443 is only needed with the compliance security profile,
# which this workspace does not enable.
resource "aws_vpc_security_group_ingress_rule" "databricks_endpoint_scc_relay" {
  count = local.databricks_network_count

  security_group_id            = aws_security_group.databricks_endpoint[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "tcp"
  from_port                    = 6666
  to_port                      = 6666
  description                  = "Secure cluster connectivity relay from the compute plane"
}

resource "aws_vpc_security_group_ingress_rule" "databricks_endpoint_https" {
  count = local.databricks_network_count

  security_group_id            = aws_security_group.databricks_endpoint[0].id
  referenced_security_group_id = aws_security_group.databricks_workspace[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the compute plane"
}

data "aws_prefix_list" "s3" {
  count = local.databricks_network_count

  name = "com.amazonaws.${var.aws_region}.s3"
}

# A gateway endpoint is a route table entry, not a network interface. It costs
# nothing, carries no hourly charge, and keeps S3 traffic on the AWS network
# rather than sending it through a NAT gateway at a per-gigabyte price.
resource "aws_vpc_endpoint" "s3" {
  count = local.databricks_network_count

  vpc_id            = aws_vpc.databricks[0].id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.databricks[0].id]

  tags = {
    Name = "${local.databricks_vpc_name}-s3"
  }
}

# Interface endpoints are billed per hour per availability zone, which is the
# running cost of this file. Two endpoints across two zones is roughly USD 15 a
# month at current eu-central-1 pricing.
resource "aws_vpc_endpoint" "sts" {
  count = local.databricks_network_count

  vpc_id              = aws_vpc.databricks[0].id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.databricks_endpoint[*].id
  security_group_ids  = [aws_security_group.databricks_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.databricks_vpc_name}-sts"
  }
}

resource "aws_vpc_endpoint" "kinesis_streams" {
  count = local.databricks_network_count

  vpc_id              = aws_vpc.databricks[0].id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.databricks_endpoint[*].id
  security_group_ids  = [aws_security_group.databricks_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.databricks_vpc_name}-kinesis-streams"
  }
}

# Back-end PrivateLink. These two endpoints point at services Databricks runs in
# its own AWS account. Private DNS makes the workspace and relay hostnames resolve
# to these endpoints' private addresses from inside the VPC, so cluster nodes reach
# the control plane without any route to the internet. They must also be
# registered with the Databricks account before a workspace can use them; that
# happens in the databricks/ stack.
resource "aws_vpc_endpoint" "databricks_workspace" {
  count = local.databricks_network_count

  vpc_id              = aws_vpc.databricks[0].id
  service_name        = var.databricks_workspace_vpce_service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.databricks_endpoint[*].id
  security_group_ids  = [aws_security_group.databricks_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.databricks_vpc_name}-databricks-workspace"
  }
}

resource "aws_vpc_endpoint" "databricks_relay" {
  count = local.databricks_network_count

  vpc_id              = aws_vpc.databricks[0].id
  service_name        = var.databricks_relay_vpce_service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.databricks_endpoint[*].id
  security_group_ids  = [aws_security_group.databricks_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.databricks_vpc_name}-databricks-relay"
  }
}

# Flow logs record which addresses talked to which, on what port, and whether the
# traffic was accepted or rejected. For a platform that produces financial figures,
# this is the network half of the audit story: it is the evidence that answers
# "could anything have reached out of this network" with a record rather than an
# assurance. They land in the same protected bucket as CloudTrail.
resource "aws_flow_log" "databricks" {
  count = local.databricks_network_count

  vpc_id                   = aws_vpc.databricks[0].id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = "${aws_s3_bucket.audit_logs.arn}/vpc-flow-logs/"
  max_aggregation_interval = 600

  tags = {
    Name = "${local.databricks_vpc_name}-flow-logs"
  }
}
