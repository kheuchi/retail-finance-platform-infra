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
