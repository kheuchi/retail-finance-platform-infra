output "account_id" {
  description = "AWS account receiving the bootstrap resources."
  value       = data.aws_caller_identity.current.account_id
}

output "state_bucket_name" {
  description = "S3 bucket to use for remote Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "monthly_budget_name" {
  description = "AWS Budget protecting the monthly spend ceiling."
  value       = aws_budgets_budget.monthly.name
}

output "github_plan_role_arn" {
  description = "Role assumed by GitHub Actions for Terraform plans."
  value       = aws_iam_role.github_plan.arn
}

output "github_deploy_role_arn" {
  description = "Role assumed by the protected GitHub Environment for applies."
  value       = aws_iam_role.github_deploy.arn
}

# The three values the Databricks account console asks for when you register a
# network configuration for a customer-managed VPC. They are null until
# enable_databricks_network is turned on.

output "databricks_vpc_id" {
  description = "Customer-managed VPC hosting the Databricks classic compute plane."
  value       = try(aws_vpc.databricks[0].id, null)
}

output "databricks_workspace_subnet_ids" {
  description = "Private subnets in which Databricks places cluster nodes. Two availability zones, no route to the internet."
  value       = aws_subnet.databricks_workspace[*].id
}

output "databricks_workspace_security_group_id" {
  description = "Security group applied to Databricks compute plane nodes."
  value       = try(aws_security_group.databricks_workspace[0].id, null)
}
