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
