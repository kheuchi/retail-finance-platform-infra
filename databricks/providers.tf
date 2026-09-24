provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application        = var.project_name
      Environment        = "shared"
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = "finance-data-platform"
      DataClassification = "internal"
      Stack              = "databricks"
    }
  }
}

# Account-level API: credentials, storage and network registrations, the
# workspace itself, and workspace assignments.
#
# Authentication is OAuth machine-to-machine as the terraform-platform service
# principal. The client ID and secret are never written here: the provider reads
# DATABRICKS_CLIENT_ID and DATABRICKS_CLIENT_SECRET from the environment, which CI
# populates from an Actions variable and an Actions secret, and which a
# workstation populates from ~/.databrickscfg outside the repository.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}

# Workspace-level API: Unity Catalog storage credential and external location.
# The host does not exist until the workspace does, so this provider is only used
# by resources gated behind enable_unity_catalog, which is turned on in a later
# apply once the workspace URL is already in state.
provider "databricks" {
  alias = "workspace"
  host  = local.workspace_url
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
