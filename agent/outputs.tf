output "ecr_repository_url" {
  description = "Where the data repo pushes the agent image."
  value       = aws_ecr_repository.agent.repository_url
}

output "gateway_url" {
  description = "MCP endpoint of the channel tools (IAM-authenticated)."
  value       = aws_bedrockagentcore_gateway.channels.gateway_url
}

output "agent_runtime_arn" {
  description = "AgentCore runtime ARN, once created."
  value       = try(aws_bedrockagentcore_agent_runtime.month_end[0].agent_runtime_arn, null)
}

output "databricks_agent_secret_arn" {
  description = "Secret container for finance-month-end-agent credentials."
  value       = aws_secretsmanager_secret.databricks_agent.arn
}

output "databricks_notifier_secret_arn" {
  description = "Secret container for finance-close-notifier credentials."
  value       = aws_secretsmanager_secret.databricks_notifier.arn
}

output "gcp_agent_role_arn" {
  description = "Role the agent on Google Agent Runtime assumes to call the gateway (D-032)."
  value       = try(aws_iam_role.gcp_agent[0].arn, null)
}

output "gcp_gateway_audience" {
  description = "Audience the agent requests for its Google ID token."
  value       = local.gcp_gateway_audience
}
