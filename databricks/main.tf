# This stack consumes the foundation rather than redefining it. The VPC, subnets,
# security groups, PrivateLink endpoints and buckets belong to bootstrap/, and
# are read here from its state outputs. Two stacks, two state files, one
# direction of dependency: bootstrap never reads this stack.
data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
    key    = "bootstrap/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  # Terraform does not store outputs whose value is null, so while the bootstrap
  # network is disabled these attributes are absent rather than null, and a direct
  # reference fails with "Unsupported attribute" before the readable precondition
  # on databricks_mws_networks can run. Reading them through try() lets that
  # precondition explain the real problem.
  network = {
    vpc_id                      = try(local.bootstrap.databricks_vpc_id, null)
    workspace_subnet_ids        = try(local.bootstrap.databricks_workspace_subnet_ids, [])
    workspace_security_group_id = try(local.bootstrap.databricks_workspace_security_group_id, null)
    workspace_vpc_endpoint_id   = try(local.bootstrap.databricks_workspace_vpc_endpoint_id, null)
    relay_vpc_endpoint_id       = try(local.bootstrap.databricks_relay_vpc_endpoint_id, null)
  }

  workspace_count     = var.enable_workspace ? 1 : 0
  unity_catalog_count = var.enable_workspace && var.enable_unity_catalog ? 1 : 0
  # Whether an admin was supplied is not sensitive, only who it is. count cannot
  # take a sensitive value, so only the null check is unwrapped.
  admin_user_count     = var.enable_workspace && nonsensitive(var.workspace_admin_user != null) ? 1 : 0
  network_is_available = local.network.vpc_id != null && local.network.relay_vpc_endpoint_id != null

  # Role names are built from parts rather than taken from the resources, because
  # the Unity Catalog credential must name its role before the role exists: the
  # role's trust policy needs an external ID that Databricks only issues when the
  # credential is created. The deploy role may manage roles with this prefix only.
  crossaccount_role_name  = "${var.project_name}-dbx-crossaccount"
  unity_catalog_role_name = "${var.project_name}-dbx-unity-catalog"
  unity_catalog_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.unity_catalog_role_name}"

  workspace_url = try(databricks_mws_workspaces.this[0].workspace_url, null)
}
