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
