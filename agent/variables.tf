variable "aws_region" {
  description = "Region of the whole platform."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix for every resource; matches bootstrap/."
  type        = string
  default     = "retail-finance-platform"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "kheuchi"
}

variable "alert_email" {
  description = "Address the stand-in channel sends approved items to (and from). Set from a GitHub secret; not in Git."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", var.alert_email))
    error_message = "alert_email must be an email address (set the TF_VAR_alert_email secret)."
  }
}

variable "databricks_workspace_url" {
  description = "Workspace URL (https://...). Reached privately by the agent, publicly by the channel Lambda."
  type        = string

  validation {
    condition     = startswith(var.databricks_workspace_url, "https://")
    error_message = "databricks_workspace_url must start with https:// (set the DATABRICKS_WORKSPACE_URL variable)."
  }
}

variable "agent_warehouse_id" {
  description = "SQL warehouse the channel tools use (databricks/ output agent_warehouse_id)."
  type        = string

  validation {
    condition     = length(var.agent_warehouse_id) > 0
    error_message = "agent_warehouse_id is empty: apply databricks/ first and set the AGENT_WAREHOUSE_ID variable."
  }
}

variable "agent_image_tag" {
  description = "Agent image tag in ECR. Null until the first image is pushed; the runtime is created only once it is set."
  type        = string
  default     = null
}

variable "agent_model_id" {
  description = "Bedrock model or EU inference profile the agent uses. Configuration, not code (ADR-006 portability)."
  type        = string
  default     = "eu.anthropic.claude-sonnet-5"
}

variable "gcp_agent_sa_unique_id" {
  description = "Numeric unique ID of the Google service account the agent runs as on Agent Runtime (gcp/ output). Null until gcp/ is applied (ADR-006 deviation, D-032)."
  type        = string
  default     = null
}
