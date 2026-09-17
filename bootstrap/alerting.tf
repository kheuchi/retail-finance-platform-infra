# Security alerting.
#
# The trail records what happened. This turns that record into a signal: CloudTrail
# streams into CloudWatch Logs, metric filters match event patterns as they arrive,
# and alarms publish to an email topic.
#
# Plain words: the trail is the security camera; this is the motion detector wired to
# it. Without this, a break-glass administrator session is only discoverable by
# someone deliberately going to look for it afterwards.
#
# Cost: CloudWatch Logs bills per GB ingested and stored, which is small for
# management events in a quiet account and bounded by the retention variable. Alarms
# are within the free allowance at this count, and the first SNS email notifications
# each month are free. Nothing here is hourly.

resource "aws_cloudwatch_log_group" "audit" {
  name              = local.audit_log_group_name
  retention_in_days = var.audit_log_retention_days

  # Accepted, reviewed exception. See docs/security/checkov-exceptions.md.
  #checkov:skip=CKV_AWS_158:A customer-managed KMS key carries a fixed monthly charge against a USD 50 ceiling. The durable copy of this data is the S3 trail bucket, which is encrypted and retained far longer.
}

# CloudTrail cannot write to CloudWatch Logs on its own authority; it assumes this
# role to do so. The trust policy is what makes it usable only by CloudTrail.
data "aws_iam_policy_document" "cloudtrail_logs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # Stops another account from inducing our CloudTrail role to be assumed on its
    # behalf, the confused-deputy case these condition keys exist for.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.audit_trail_arn]
    }
  }
}

resource "aws_iam_role" "cloudtrail_logs" {
  name               = local.audit_cwl_role_name
  description        = "Lets CloudTrail deliver events into CloudWatch Logs for alerting."
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_logs_trust.json
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    sid    = "WriteTrailEventsToLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.audit.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name   = "write-trail-events"
  role   = aws_iam_role.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

resource "aws_sns_topic" "security_alerts" {
  name = local.security_topic_name

  #checkov:skip=CKV_AWS_26:SNS server-side encryption requires a KMS key and adds per-request cost. The messages are alarm state changes naming an event type, not log contents.
}

# One recipient, one person. Reusing the existing notification address avoids adding
# a second secret to CI for the same inbox.
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.budget_alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

data "aws_iam_policy_document" "security_alerts" {
  statement {
    sid    = "AllowCloudWatchAlarmsToPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.security_alerts.json
}

# --- Detections -------------------------------------------------------------

locals {
  security_metric_namespace = "${var.project_name}/Security"

  security_detections = {
    break_glass_write = {
      metric_name = "BreakGlassAdminWrite"
      description = "A write action performed by the break-glass administrator identity."
      # readOnly is false for mutating calls, so this fires on change rather than on
      # the operator merely looking at something.
      pattern = "{ ($.userIdentity.type = \"IAMUser\") && ($.userIdentity.userName = \"${var.break_glass_user_name}\") && ($.readOnly IS FALSE) }"
    }

    root_account_used = {
      metric_name = "RootAccountUsed"
      description = "Any use of the root account, which this project forbids for routine work (decision D-007)."
      # invokedBy NOT EXISTS excludes AWS services acting on the account's behalf,
      # which would otherwise make this alarm fire constantly and be ignored.
      pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "security" {
  for_each = local.security_detections

  name           = "${var.project_name}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.audit.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = local.security_metric_namespace
    value     = "1"
    # Without this the metric reports nothing when no event matches, and the alarm
    # sits in INSUFFICIENT_DATA rather than OK.
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "security" {
  for_each = local.security_detections

  alarm_name          = "${var.project_name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = local.security_metric_namespace
  metric_name         = each.value.metric_name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
  ok_actions    = [aws_sns_topic.security_alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.security]
}
