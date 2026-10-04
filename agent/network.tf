# The agent runtime gets its own security group: HTTPS to the endpoints and to S3, nothing
# else. No internet route exists in this VPC, so the only paths out are these endpoints.
resource "aws_security_group" "runtime" {
  #checkov:skip=CKV2_AWS_5:Attached by AgentCore to the network interfaces it creates for the runtime, which Terraform does not create.
  name        = "${local.prefix}-runtime"
  description = "AgentCore runtime for the month-end agents. HTTPS to VPC endpoints only."
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.prefix}-runtime"
  }
}

resource "aws_vpc_security_group_egress_rule" "runtime_to_endpoints" {
  security_group_id            = aws_security_group.runtime.id
  referenced_security_group_id = data.aws_security_group.endpoint.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS to interface endpoints (Bedrock, AgentCore, ECR, logs, secrets, Databricks workspace)"
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_vpc_security_group_egress_rule" "runtime_to_s3" {
  security_group_id = aws_security_group.runtime.id
  prefix_list_id    = data.aws_prefix_list.s3.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to S3 through the gateway endpoint (image layers)"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_runtime" {
  security_group_id            = data.aws_security_group.endpoint.id
  referenced_security_group_id = aws_security_group.runtime.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the agent runtime"
}

# Seven interface endpoints, 2 AZ each: roughly USD 3.7 a day. Built for the demo window.
locals {
  endpoint_services = toset([
    "bedrock-runtime",
    "bedrock-agentcore",
    "bedrock-agentcore.gateway",
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
  ])
}

resource "aws_vpc_endpoint" "agent" {
  for_each = local.endpoint_services

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.endpoint.ids
  security_group_ids  = [data.aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.prefix}-${replace(each.key, ".", "-")}"
  }
}
