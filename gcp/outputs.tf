output "runtime_service_account" {
  description = "Identity the agent runs as on Agent Runtime."
  value       = google_service_account.runtime.email
}

output "runtime_service_account_unique_id" {
  description = "Numeric ID that AWS trusts (sub claim of its Google ID token) for the gateway-only role."
  value       = google_service_account.runtime.unique_id
}

output "deployer_service_account" {
  description = "Service account the data repo impersonates through federation."
  value       = google_service_account.deployer.email
}

output "workload_identity_provider" {
  description = "Provider resource name for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "staging_bucket" {
  description = "Deployment staging bucket."
  value       = "gs://${google_storage_bucket.staging.name}"
}

output "databricks_secret" {
  description = "Secret Manager secret holding the agent's Databricks OAuth credentials."
  value       = google_secret_manager_secret.databricks_agent.id
}
