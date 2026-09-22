# Audit baseline.
#
# CloudTrail records who called which AWS API, when, and from where. Management
# events cover control-plane changes such as creating a bucket or editing a role.
# The first copy of management events is free; only storage and data events bill.
#
# Known limitation, stated rather than hidden: in a single account the log bucket
# sits beside the workloads it describes, so a sufficiently privileged administrator
# can alter both. Separating them is what a Log Archive account buys, and it is not
# reachable while the Free plan rules out AWS Organizations (decision D-009).

resource "aws_s3_bucket" "audit_logs" {
  bucket        = local.audit_bucket_name
  force_destroy = false

  # Accepted, reviewed exceptions. See docs/security/checkov-exceptions.md.
  #checkov:skip=CKV_AWS_18:This is the log destination. Pointing access logging at the log bucket itself creates a feedback loop; a separate logging bucket is deferred with the rest of the audit expansion.
  #checkov:skip=CKV2_AWS_62:No consumer exists for object-created events on the trail bucket.
  #checkov:skip=CKV_AWS_144:Cross-region replication contradicts decision D-013 and doubles cost.
  #checkov:skip=CKV_AWS_145:SSE-KMS carries a fixed monthly charge against a USD 50 ceiling. SSE-S3 is enforced and TLS is required in transit.

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"

    filter {}

    # A year of history is enough to demonstrate the control and to investigate
    # anything in this project, while keeping storage cost near zero.
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "audit_logs" {
  # Exactly the policy CloudTrail documents, including the aws:SourceArn condition
  # that stops another account from writing its logs into this bucket.
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.audit_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.audit_trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.audit_trail_arn]
    }

    # Object ownership is BucketOwnerEnforced, which rejects requests that specify
    # an ACL — except this exact canned ACL, which S3 still accepts and which
    # CloudTrail still sends. Keeping the condition matches the documented policy.
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # VPC flow logs land in the same protected bucket as the trail, under their own
  # prefix. The delivery service writes them, so it needs the same pair of grants
  # CloudTrail has: read the bucket ACL to confirm the target, then put objects.
  # Both are narrowed by source account so no other account's delivery service can
  # write here.
  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.audit_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit_logs.arn}/vpc-flow-logs/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.audit_logs.arn,
      "${aws_s3_bucket.audit_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  policy = data.aws_iam_policy_document.audit_logs.json
}

resource "aws_cloudtrail" "management_events" {
  name           = local.audit_trail_name
  s3_bucket_name = aws_s3_bucket.audit_logs.id

  # Accepted, reviewed exceptions. See docs/security/checkov-exceptions.md.
  #checkov:skip=CKV_AWS_252:An SNS topic on log delivery has no subscriber. Delivery notifications are not the alerting control; CloudWatch metric filters are, and they are the next increment.
  #checkov:skip=CKV_AWS_35:Logs are encrypted with SSE-S3. A customer-managed KMS key adds a fixed monthly charge against a USD 50 ceiling.
  #checkov:skip=CKV2_AWS_10:CloudWatch Logs integration is wanted and deferred deliberately, not rejected. It is what turns the trail into alerting, and it is the recommended next increment.

  # Capture activity in every region, not just Frankfurt. An attacker operating in
  # an unused region is precisely the case a single-region trail would miss.
  is_multi_region_trail = true

  # IAM, STS and other global services report into one region; without this their
  # events are absent entirely.
  include_global_service_events = true

  # Lets us prove afterwards that a log file was not altered or removed. Free.
  enable_log_file_validation = true

  # Stream events to CloudWatch Logs as well as S3. S3 remains the durable record;
  # this copy exists so metric filters can match events as they arrive and raise an
  # alarm. See alerting.tf.
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.audit.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Object-level events on the Terraform state bucket: who read or wrote state,
    # and when. Scoped to that one bucket because data events bill per event and
    # account-wide capture is the usual way this becomes expensive.
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.terraform_state.arn}/"]
    }
  }

  # The bucket policy must exist before CloudTrail will validate the destination.
  depends_on = [aws_s3_bucket_policy.audit_logs]
}
