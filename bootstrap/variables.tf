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

variable "monthly_budget_usd" {
  description = "Maximum intended AWS spend per calendar month in USD."
  type        = number
  default     = 50

  validation {
    condition     = var.monthly_budget_usd > 0 && var.monthly_budget_usd <= 50
    error_message = "The approved personal-spend ceiling is USD 50 per month."
  }
}

variable "budget_alert_email" {
  description = "Email address that receives AWS Budget alerts. Supply via an untracked tfvars file."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.budget_alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = <<-EOT
    budget_alert_email must be a valid email address, or be omitted entirely.
    In CI this variable comes from the TF_VAR_BUDGET_ALERT_EMAIL Actions secret.
    A missing or blank secret arrives as an empty string rather than as null, so
    it fails here instead of silently planning the Budget without notifications.
    EOT
  }
}

variable "break_glass_user_name" {
  description = <<-EOT
  IAM user that constitutes the break-glass administrator path. Any write action by
  this identity raises an alarm, because routine changes are expected to arrive
  through CI rather than from a workstation.
  EOT
  type        = string
  default     = "cheikh-platform-admin"
}

variable "audit_log_retention_days" {
  description = "How long CloudTrail events are kept in CloudWatch Logs. Ingestion and storage are billed, so this is deliberately shorter than the 365-day retention in S3, which stays the durable record."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180], var.audit_log_retention_days)
    error_message = "Use a CloudWatch Logs retention value of 180 days or fewer to bound cost."
  }
}

variable "github_organization" {
  description = "GitHub organization or user that owns the infrastructure repository."
  type        = string
  default     = "kheuchi"
}

variable "github_repository" {
  description = "GitHub repository permitted to request AWS deployment credentials."
  type        = string
  default     = "retail-finance-platform-infra"
}

variable "github_organization_id" {
  description = "Immutable GitHub owner ID used by the repository's hardened OIDC subject template."
  type        = number
  default     = 47268855
}

variable "github_repository_id" {
  description = "Immutable GitHub repository ID used by the hardened OIDC subject template."
  type        = number
  default     = 1371524439
}

variable "github_deploy_environment" {
  description = "Protected GitHub Environment required for infrastructure applies."
  type        = string
  default     = "aws-bootstrap"
}

variable "enable_databricks_network" {
  description = <<-EOT
  Whether to create the customer-managed VPC for the Databricks classic compute
  plane. Defaults to false so that nothing in databricks_network.tf exists, and
  nothing bills, until the Databricks account is ready to consume it.

  The running cost when enabled is the two interface VPC endpoints, roughly USD 15
  per month. The VPC, subnets, route tables, security groups, S3 gateway endpoint
  and flow logs are free. There is no NAT gateway, by design.

  Turning this on is a deliberate, reviewed act: it is changed here, in a pull
  request, so the moment the meter started is in Git history.

  Enabled on 2026-09-24 for the Databricks Enterprise trial, which ends on
  2026-10-06. Set back to false after the trial to stop the endpoint charges.
  EOT
  type        = bool
  default     = true
}

variable "databricks_vpc_cidr" {
  description = <<-EOT
  Address range for the Databricks customer-managed VPC. Databricks requires the
  VPC to sit between /25 and /16, and each workspace subnet between /17 and /26.
  A /16 is used so the two workspace subnets can be /22 without crowding the two
  small endpoint subnets carved from the same space.
  EOT
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.databricks_vpc_cidr)) && tonumber(split("/", var.databricks_vpc_cidr)[1]) >= 16 && tonumber(split("/", var.databricks_vpc_cidr)[1]) <= 25
    error_message = "databricks_vpc_cidr must be a valid CIDR with a prefix length between /16 and /25, which is the range Databricks supports for a customer-managed VPC."
  }
}

variable "databricks_account_id" {
  description = <<-EOT
  Databricks account ID, a UUID from the account console. Databricks' own AWS
  account presents it as a principal tag when it touches the workspace root bucket,
  and the bucket policy only honours requests carrying this exact tag. Kept out of
  Git by convention: supply it through the untracked tfvars file locally, and the
  DATABRICKS_ACCOUNT_ID Actions variable in CI.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.databricks_account_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.databricks_account_id))
    error_message = "databricks_account_id must be the Databricks account UUID from the account console, or be omitted."
  }

  validation {
    condition     = !var.enable_databricks_network || var.databricks_account_id != null
    error_message = "enable_databricks_network needs databricks_account_id: without it the root bucket grant cannot be restricted to this Databricks account."
  }
}

# The VPC endpoint service names Databricks publishes per region for back-end
# PrivateLink. Defaults are the eu-central-1 values from the Databricks table of
# PrivateLink VPC endpoint services, retrieved on 2026-09-24. They are services
# Databricks runs; we only create endpoints pointing at them.
variable "databricks_workspace_vpce_service" {
  description = "Databricks PrivateLink service for the workspace REST API (\"General Access\" in the Databricks table)."
  type        = string
  default     = "com.amazonaws.vpce.eu-central-1.vpce-svc-081f78503812597f7"
}

variable "databricks_relay_vpce_service" {
  description = "Databricks PrivateLink service for the secure cluster connectivity relay."
  type        = string
  default     = "com.amazonaws.vpce.eu-central-1.vpce-svc-08e5dfca9572c85c4"
}
