variable "aws_region" {
  description = "Primary AWS region for the platform."
  type        = string
  default     = "eu-west-3"

  validation {
    condition     = var.aws_region == "eu-west-3"
    error_message = "This project's approved primary region is eu-west-3 (Paris)."
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
    error_message = "budget_alert_email must be a valid email address."
  }
}
