# The agent platform (story 7.1, ADR-006) consumes the foundation: the Databricks VPC,
# its endpoint subnets and endpoint security group come from bootstrap/ (read through its
# state and by tag), never redefined here.
data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
    key    = "bootstrap/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  prefix     = "${var.project_name}-agent"
  bootstrap  = data.terraform_remote_state.bootstrap.outputs
  vpc_id     = local.bootstrap.databricks_vpc_id
  arn        = "${data.aws_partition.current.partition}:%s:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  repository = "${var.project_name}-agent"
}

data "aws_security_group" "endpoint" {
  vpc_id = local.vpc_id
  filter {
    name   = "group-name"
    values = ["*-endpoint"]
  }
}

data "aws_subnets" "endpoint" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*-endpoint-*"]
  }
}
