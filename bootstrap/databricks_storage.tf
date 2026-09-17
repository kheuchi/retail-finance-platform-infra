# Databricks storage prerequisites.
#
# Two buckets the lakehouse needs before a workspace can exist:
#
#   - workspace root storage, which Databricks uses for the workspace's own system
#     data. Historically called the DBFS root.
#   - Unity Catalog managed storage, where governed tables actually live. Unity
#     Catalog is the governance layer holding catalogs, schemas, tables, lineage and
#     access grants.
#
# Both are empty and cost nothing until data lands in them. They are built now
# because they sit on the critical path: the workspace cannot be created without
# root storage, and the metastore cannot be created without its own location.
#
# What is deliberately NOT here: the Databricks cross-account IAM role, the Unity
# Catalog storage credential role, and the bucket policies granting Databricks
# access. Every one of those requires the Databricks account ID as an external ID
# or policy condition, and that identifier does not exist until the account is
# created. Writing them now would mean writing IAM that cannot be applied or tested.
# See docs/architecture/databricks-prerequisites.md for what remains and why.

resource "aws_s3_bucket" "databricks_root" {
  bucket        = local.databricks_root_bucket_name
  force_destroy = false

  # Accepted, reviewed exceptions. See docs/security/checkov-exceptions.md.
  #checkov:skip=CKV_AWS_18:Access logging is deferred with the rest of the audit expansion; CloudTrail data events are the better control and are already in place for the state bucket.
  #checkov:skip=CKV2_AWS_62:No consumer exists for object-created events.
  #checkov:skip=CKV_AWS_144:Cross-region replication contradicts decision D-013 and doubles storage cost.
  #checkov:skip=CKV_AWS_145:SSE-KMS carries a fixed monthly charge against a USD 50 ceiling. SSE-S3 is enforced and TLS is required in transit.

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "unity_catalog" {
  bucket        = local.unity_catalog_bucket_name
  force_destroy = false

  #checkov:skip=CKV_AWS_18:As above. Deferred with the audit expansion.
  #checkov:skip=CKV2_AWS_62:No consumer exists for object-created events.
  #checkov:skip=CKV_AWS_144:Cross-region replication contradicts decision D-013 and doubles storage cost.
  #checkov:skip=CKV_AWS_145:SSE-KMS carries a fixed monthly charge against a USD 50 ceiling. SSE-S3 is enforced and TLS is required in transit.

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  databricks_buckets = {
    databricks_root = aws_s3_bucket.databricks_root.id
    unity_catalog   = aws_s3_bucket.unity_catalog.id
  }
}

resource "aws_s3_bucket_ownership_controls" "databricks" {
  for_each = local.databricks_buckets
  bucket   = each.value

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "databricks" {
  for_each = local.databricks_buckets
  bucket   = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "databricks" {
  for_each = local.databricks_buckets
  bucket   = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "databricks" {
  for_each = local.databricks_buckets
  bucket   = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "databricks" {
  for_each = local.databricks_buckets
  bucket   = each.value

  rule {
    id     = "reap-noncurrent-and-failed-uploads"
    status = "Enabled"

    filter {}

    # Deliberately no expiration on current objects: this is data storage, not logs.
    # Only superseded versions and abandoned uploads are reaped, both of which are
    # pure cost with no recovery value once a newer version exists.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "databricks_tls_only" {
  for_each = local.databricks_buckets

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${each.value}",
      "arn:${data.aws_partition.current.partition}:s3:::${each.value}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Only the TLS-only guard for now. The statements granting Databricks itself access
# are added when the account ID exists, since they are conditioned on it.
resource "aws_s3_bucket_policy" "databricks" {
  for_each = local.databricks_buckets

  bucket = each.value
  policy = data.aws_iam_policy_document.databricks_tls_only[each.key].json
}
