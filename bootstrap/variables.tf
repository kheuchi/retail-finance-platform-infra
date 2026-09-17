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
