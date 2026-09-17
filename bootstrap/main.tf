locals {
  state_bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  audit_bucket_name = "${var.project_name}-cloudtrail-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  audit_trail_name  = "${var.project_name}-management-events"

  # Built from parts rather than from the resources themselves, so the deploy role
  # can be granted these permissions in a separate, earlier apply than the one that
  # creates the resources. A role cannot create what it has no permission for, and
  # Terraform does not guarantee it updates that role before using it.
  audit_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.audit_bucket_name}"
  audit_trail_arn  = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.audit_trail_name}"

  databricks_root_bucket_name = "${var.project_name}-databricks-root-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  unity_catalog_bucket_name   = "${var.project_name}-unity-catalog-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  databricks_bucket_arns = [
    "arn:${data.aws_partition.current.partition}:s3:::${local.databricks_root_bucket_name}",
    "arn:${data.aws_partition.current.partition}:s3:::${local.unity_catalog_bucket_name}"
  ]

  audit_log_group_name = "/aws/cloudtrail/${var.project_name}"
  audit_cwl_role_name  = "${var.project_name}-cloudtrail-logs"
  security_topic_name  = "${var.project_name}-security-alerts"

  audit_log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.audit_log_group_name}"
  audit_cwl_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.audit_cwl_role_name}"
  security_topic_arn  = "arn:${data.aws_partition.current.partition}:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.security_topic_name}"
  alarm_arn_prefix    = "arn:${data.aws_partition.current.partition}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.project_name}-*"
  budget_notifications = var.budget_alert_email == null ? [] : [
    { threshold = 50, type = "ACTUAL" },
    { threshold = 80, type = "ACTUAL" },
    { threshold = 100, type = "FORECASTED" }
  ]
}

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  force_destroy = false

  # Accepted, reviewed exceptions. Rationale and revisit triggers are recorded in
  # docs/security/checkov-exceptions.md; do not add a skip here without adding the
  # matching entry there.
  #checkov:skip=CKV_AWS_18:Server access logging needs a second bucket and an audit baseline; deferred to the CloudTrail/audit work item.
  #checkov:skip=CKV2_AWS_62:Event notifications have no consumer. Terraform state changes are driven by CI, not by bucket events.
  #checkov:skip=CKV_AWS_144:Cross-region replication contradicts decision D-013 (single region) and doubles storage cost for a file that is already versioned and reproducible.
  #checkov:skip=CKV_AWS_145:SSE-KMS with a customer-managed key adds a fixed monthly charge against a USD 50 ceiling. SSE-S3 (AES-256) is enforced and TLS is required in transit.

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # A failed state upload leaves orphaned multipart parts that are billed as
    # storage but are invisible in a normal bucket listing. Reap them.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state.json
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    # Alert on gross service consumption so promotional credits cannot hide burn.
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = local.budget_notifications

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
}

resource "aws_iam_account_password_policy" "baseline" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  require_uppercase_characters   = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}
