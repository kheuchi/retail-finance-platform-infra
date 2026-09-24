variable "aws_region" {
  description = "Primary AWS region for the platform."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = var.aws_region == "eu-central-1"
    error_message = "This project's approved primary region is eu-central-1 (Frankfurt)."
  }
}

variable "project_name" {
  description = "Stable lowercase project identifier used in names and tags."
  type        = string
  default     = "retail-finance-platform"
}

variable "owner" {
  description = "Human or team responsible for the deployed resources."
  type        = string
  default     = "cheikh"
}

variable "databricks_account_id" {
  description = "Databricks account ID from the account console. Supplied through the DATABRICKS_ACCOUNT_ID Actions variable in CI and an untracked tfvars file locally."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.databricks_account_id))
    error_message = "databricks_account_id must be the Databricks account UUID."
  }
}

variable "databricks_client_id" {
  description = "Application ID of the terraform-platform service principal, used to grant it admin on the workspace it creates. Not a secret. Supplied through the DATABRICKS_CLIENT_ID Actions variable."
  type        = string
}

variable "workspace_admin_user" {
  description = "Databricks user name (an email address) granted admin on the workspace. Kept out of Git; supplied through the DATABRICKS_WORKSPACE_ADMIN Actions variable. Null skips the assignment."
  type        = string
  default     = null
  # The repository is public and so are its Actions logs. Marking this sensitive
  # keeps the address out of plan output.
  sensitive = true
}

variable "workspace_name" {
  description = "Display name of the classic workspace."
  type        = string
  default     = "retail-finance-platform"
}

variable "enable_workspace" {
  description = <<-EOT
  Creates the cross-account role, the Databricks credential, storage and network
  registrations, and the classic workspace. Requires the bootstrap network to be
  enabled first. Creating a workspace is free; what costs money is compute
  started inside it and the network endpoints bootstrap already runs.

  Enabled on 2026-09-24, after the bootstrap network was applied.
  EOT
  type        = bool
  default     = true
}

variable "enable_unity_catalog" {
  description = <<-EOT
  Creates the Unity Catalog storage credential, its IAM role and the external
  location on the governed bucket. Needs the workspace URL, so it is turned on
  in an apply after the one that creates the workspace.
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_unity_catalog || var.enable_workspace
    error_message = "enable_unity_catalog needs enable_workspace: Unity Catalog objects are created through the workspace."
  }
}
