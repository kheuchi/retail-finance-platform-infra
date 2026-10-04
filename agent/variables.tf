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
}

variable "databricks_workspace_url" {
  description = "Workspace URL (https://...). Reached privately by the agent, publicly by the channel Lambda."
  type        = string
}

variable "agent_warehouse_id" {
  description = "SQL warehouse the channel tools use (databricks/ output agent_warehouse_id)."
  type        = string
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
