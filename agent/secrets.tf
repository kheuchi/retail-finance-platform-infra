# Databricks OAuth credentials of the agent and of the channel tools. Terraform creates
# the containers only; the values are written out of band (scripts/set_agent_secrets.sh)
# and never enter Terraform state or Git.
resource "aws_secretsmanager_secret" "databricks_agent" {
  #checkov:skip=CKV2_AWS_57:Databricks OAuth secrets are rotated by re-creating the service principal secret, not by a Lambda rotator.
  #checkov:skip=CKV_AWS_149:AWS-managed key is sufficient for a time-boxed portfolio deployment.
  name                    = "${var.project_name}/agent/databricks-agent"
  description             = "OAuth client credentials of finance-month-end-agent (JSON: client_id, client_secret)."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "databricks_notifier" {
  #checkov:skip=CKV2_AWS_57:Same as above.
  #checkov:skip=CKV_AWS_149:Same as above.
  name                    = "${var.project_name}/agent/databricks-notifier"
  description             = "OAuth client credentials of finance-close-notifier (JSON: client_id, client_secret)."
  recovery_window_in_days = 0
}
