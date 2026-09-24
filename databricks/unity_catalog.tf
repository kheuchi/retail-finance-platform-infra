# Unity Catalog access to the governed bucket.
#
# The workspace is attached automatically to the account's existing regional
# metastore, metastore_aws_eu_central_1: Databricks allows one metastore per
# region per account, and new workspaces in a region with a metastore are
# enabled for Unity Catalog on creation. So nothing here creates a metastore.
# What this adds is a storage credential and an external location on the
# unity-catalog bucket built by bootstrap, so governed tables live in storage
# this project owns, protected by its bucket policy and audited by its trail.
#
# The order is the one Databricks documents, and it is not the obvious one:
#
#   1. The storage credential is created first, naming a role that does not
#      exist yet. Databricks issues an external ID for it.
#   2. The IAM role is then created with a trust policy requiring that external
#      ID, which is the confused-deputy defence for Unity Catalog.
#   3. After IAM propagates, the external location is created. Databricks
#      validates it by assuming the role and touching the bucket, so a successful
#      apply is itself evidence the chain works.

resource "databricks_storage_credential" "governed" {
  count    = local.unity_catalog_count
  provider = databricks.workspace

  name    = "${var.project_name}-governed-storage"
  comment = "Managed by Terraform. Grants Unity Catalog access to the governed bucket through a role in the project AWS account."

  # Only workspaces explicitly bound to it may use this credential. With one
  # workspace today that is the same as open, but it is the right default once a
  # second workspace exists.
  isolation_mode = "ISOLATION_MODE_ISOLATED"

  aws_iam_role {
    # Built from parts: referencing the role resource would be circular, because
    # the role needs this credential's external ID.
    role_arn = local.unity_catalog_role_arn
  }
}

# The provider's data source includes the self-assume statement Databricks now
# requires on Unity Catalog roles, alongside the external ID condition.
data "databricks_aws_unity_catalog_assume_role_policy" "governed" {
  count    = local.unity_catalog_count
  provider = databricks.workspace

  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = local.unity_catalog_role_name
  external_id    = databricks_storage_credential.governed[0].aws_iam_role[0].external_id
}

# Read and write on this one bucket only. The bucket is encrypted with SSE-S3,
# so no KMS grant is needed; if it moves to a customer-managed key, kms_name must
# be added here or every read will fail.
data "databricks_aws_unity_catalog_policy" "governed" {
  count    = local.unity_catalog_count
  provider = databricks.workspace

  aws_account_id = data.aws_caller_identity.current.account_id
  bucket_name    = local.bootstrap.unity_catalog_bucket_name
  role_name      = local.unity_catalog_role_name
}

resource "aws_iam_role" "unity_catalog" {
  count = local.unity_catalog_count

  name                 = local.unity_catalog_role_name
  description          = "Assumed by Unity Catalog to read and write the governed bucket."
  assume_role_policy   = data.databricks_aws_unity_catalog_assume_role_policy.governed[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "unity_catalog" {
  count = local.unity_catalog_count

  name   = "unity-catalog-governed-bucket"
  role   = aws_iam_role.unity_catalog[0].id
  policy = data.databricks_aws_unity_catalog_policy.governed[0].json
}

resource "time_sleep" "unity_catalog_propagation" {
  count = local.unity_catalog_count

  create_duration = "30s"

  depends_on = [aws_iam_role_policy.unity_catalog]
}

resource "databricks_external_location" "governed" {
  count    = local.unity_catalog_count
  provider = databricks.workspace

  name            = "${var.project_name}-governed"
  url             = "s3://${local.bootstrap.unity_catalog_bucket_name}/"
  credential_name = databricks_storage_credential.governed[0].name
  comment         = "Managed by Terraform. Root of governed finance data."
  isolation_mode  = "ISOLATION_MODE_ISOLATED"

  depends_on = [time_sleep.unity_catalog_propagation]
}
