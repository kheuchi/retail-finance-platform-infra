variable "project_id" {
  description = "Personal GCP project hosting the agent runtime (ADR-006 deviation, D-032)."
  type        = string
  default     = "mon-rag-perso-2026"
}

variable "region" {
  description = "Agent Runtime region (Belgium)."
  type        = string
  default     = "europe-west1"
}

variable "data_repository" {
  description = "GitHub repository whose main branch deploys the agent to Agent Runtime."
  type        = string
  default     = "kheuchi/retail-finance-data-products"
}
