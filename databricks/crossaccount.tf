# The cross-account role. Databricks assumes it from its own AWS account to launch
# and terminate the EC2 instances that make up clusters in our VPC.
#
# Two things keep it narrow:
#
#   - The trust policy requires sts:ExternalId to equal our Databricks account ID.
#     Databricks' AWS account serves every customer; without this condition any
#     other Databricks customer could register this role ARN in their own account
#     and have Databricks act on our AWS account for them. That is the confused
#     deputy problem, and the external ID is AWS's documented defence against it.
#   - The permissions policy is the "restricted" variant Databricks publishes for
#     customer-managed VPCs: EC2 actions are conditioned on this VPC and this
#     security group, so the role cannot launch instances anywhere else in the
#     account. Both policies come from the provider's data sources, which track
#     Databricks' documented policies, rather than being retyped here.
data "databricks_aws_assume_role_policy" "crossaccount" {
  count    = local.workspace_count
  provider = databricks.account

  external_id = var.databricks_account_id
}

data "databricks_aws_crossaccount_policy" "restricted" {
  count    = local.workspace_count
  provider = databricks.account

  policy_type       = "restricted"
  aws_account_id    = data.aws_caller_identity.current.account_id
  region            = var.aws_region
  vpc_id            = local.network.vpc_id
  security_group_id = local.network.workspace_security_group_id

  # This is the first thing in the stack that needs the network, so it is where a
  # missing network should be reported, in words rather than as a provider error.
  lifecycle {
    precondition {
      condition     = local.network_is_available
      error_message = "The bootstrap network is not enabled. Set enable_databricks_network = true in bootstrap/ and apply that first."
    }
  }
}

resource "aws_iam_role" "crossaccount" {
  count = local.workspace_count

  name                 = local.crossaccount_role_name
  description          = "Assumed by Databricks to manage cluster instances in the customer-managed VPC."
  assume_role_policy   = data.databricks_aws_assume_role_policy.crossaccount[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "crossaccount" {
  count = local.workspace_count

  name   = "databricks-crossaccount-restricted"
  role   = aws_iam_role.crossaccount[0].id
  policy = data.databricks_aws_crossaccount_policy.restricted[0].json
}

# IAM is eventually consistent. Databricks validates the credential by assuming
# the role immediately, and a role created seconds earlier can fail that check.
# Thirty seconds is conservative for a one-off creation.
resource "time_sleep" "crossaccount_propagation" {
  count = local.workspace_count

  create_duration = "30s"

  depends_on = [aws_iam_role_policy.crossaccount]
}
