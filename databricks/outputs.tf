output "workspace_url" {
  description = "URL of the classic workspace. Null until enable_workspace is applied."
  value       = local.workspace_url
}

output "workspace_id" {
  description = "Numeric Databricks workspace ID."
  value       = try(databricks_mws_workspaces.this[0].workspace_id, null)
}

output "crossaccount_role_arn" {
  description = "Role Databricks assumes to manage cluster instances."
  value       = try(aws_iam_role.crossaccount[0].arn, null)
}

output "unity_catalog_role_arn" {
  description = "Role Unity Catalog assumes to reach the governed bucket."
  value       = try(aws_iam_role.unity_catalog[0].arn, null)
}

output "governed_external_location" {
  description = "Unity Catalog external location over the governed bucket."
  value       = try(databricks_external_location.governed[0].url, null)
}
