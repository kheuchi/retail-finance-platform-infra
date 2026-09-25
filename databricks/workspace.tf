# Registrations in the Databricks account, then the workspace that ties them
# together. None of these objects costs anything on its own. A workspace bills
# only for compute started inside it.

resource "databricks_mws_credentials" "this" {
  count    = local.workspace_count
  provider = databricks.account

  credentials_name = "${var.project_name}-crossaccount"
  role_arn         = aws_iam_role.crossaccount[0].arn

  depends_on = [time_sleep.crossaccount_propagation]
}

resource "databricks_mws_storage_configurations" "this" {
  count    = local.workspace_count
  provider = databricks.account

  # account_id is still needed on this resource, on databricks_mws_networks,
  # databricks_mws_workspaces and databricks_mws_vpc_endpoint in provider 1.134,
  # even though the provider block already carries it. For the VPC endpoint the
  # schema does not mark it required, so validate passes and the apply fails with
  # "Unable to load OAuth Config". Found on the first apply.
  account_id                 = var.databricks_account_id
  storage_configuration_name = "${var.project_name}-root"
  bucket_name                = local.bootstrap.databricks_root_bucket_name
}

# The two back-end PrivateLink endpoints exist in AWS already, created by
# bootstrap. Registering them tells Databricks to accept connections from them.
resource "databricks_mws_vpc_endpoint" "workspace" {
  count    = local.workspace_count
  provider = databricks.account

  account_id          = var.databricks_account_id
  vpc_endpoint_name   = "${var.project_name}-workspace-api"
  aws_vpc_endpoint_id = local.network.workspace_vpc_endpoint_id
  region              = var.aws_region
}

resource "databricks_mws_vpc_endpoint" "relay" {
  count    = local.workspace_count
  provider = databricks.account

  account_id          = var.databricks_account_id
  vpc_endpoint_name   = "${var.project_name}-scc-relay"
  aws_vpc_endpoint_id = local.network.relay_vpc_endpoint_id
  region              = var.aws_region
}

# Back-end PrivateLink is what this workspace uses: cluster nodes reach the
# control plane only through the endpoints above. Front-end access, people using
# the web interface, stays on the public network, authenticated by Databricks.
# Making that private too would need a client VPN or Direct Connect into the VPC,
# which this project does not have. The line is recorded in the network doc.
resource "databricks_mws_private_access_settings" "this" {
  count    = local.workspace_count
  provider = databricks.account

  private_access_settings_name = "${var.project_name}-private-access"
  region                       = var.aws_region
  public_access_enabled        = true
  private_access_level         = "ACCOUNT"
}

resource "databricks_mws_networks" "this" {
  count    = local.workspace_count
  provider = databricks.account

  account_id         = var.databricks_account_id
  network_name       = "${var.project_name}-customer-managed-vpc"
  vpc_id             = local.network.vpc_id
  subnet_ids         = local.network.workspace_subnet_ids
  security_group_ids = [local.network.workspace_security_group_id]

  vpc_endpoints {
    rest_api        = [databricks_mws_vpc_endpoint.workspace[0].vpc_endpoint_id]
    dataplane_relay = [databricks_mws_vpc_endpoint.relay[0].vpc_endpoint_id]
  }

  lifecycle {
    precondition {
      condition     = local.network_is_available
      error_message = "The bootstrap network is not enabled. Set enable_databricks_network = true in bootstrap/ and apply that first."
    }
  }
}

resource "databricks_mws_workspaces" "this" {
  count    = local.workspace_count
  provider = databricks.account

  account_id     = var.databricks_account_id
  workspace_name = var.workspace_name
  aws_region     = var.aws_region
  pricing_tier   = "ENTERPRISE"

  credentials_id             = databricks_mws_credentials.this[0].credentials_id
  storage_configuration_id   = databricks_mws_storage_configurations.this[0].storage_configuration_id
  network_id                 = databricks_mws_networks.this[0].network_id
  private_access_settings_id = databricks_mws_private_access_settings.this[0].private_access_settings_id

  # Applied by Databricks to every cluster instance, so EC2 spend is attributable
  # in AWS Cost Explorer. Databricks documents that custom tags, once set, can be
  # changed but never removed, so the set is deliberately small and stable.
  custom_tags = {
    Application = var.project_name
    CostCenter  = "finance-data-platform"
    Owner       = var.owner
  }

  # Not a creation-order need: it makes Terraform destroy the workspace before the
  # serverless network policy, whose assignment cannot be deleted on its own.
  depends_on = [databricks_account_network_policy.serverless_restricted]
}

# Account admins are not automatically workspace admins. The service principal
# needs admin on the workspace to create Unity Catalog objects through it, and the
# human owner needs it to log in.
data "databricks_service_principal" "terraform" {
  count    = local.workspace_count
  provider = databricks.account

  application_id = var.databricks_client_id
}

resource "databricks_mws_permission_assignment" "terraform_admin" {
  count    = local.workspace_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = data.databricks_service_principal.terraform[0].id
  permissions  = ["ADMIN"]
}

data "databricks_user" "workspace_admin" {
  count    = local.admin_user_count
  provider = databricks.account

  user_name = var.workspace_admin_user
}

resource "databricks_mws_permission_assignment" "workspace_admin" {
  count    = local.admin_user_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = data.databricks_user.workspace_admin[0].id
  permissions  = ["ADMIN"]
}
