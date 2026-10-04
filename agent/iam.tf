# Three roles, one duty each:
#   agent-runtime   what the agent container may do: EU Claude/Nova models, the gateway,
#                   its Databricks secret, its image and logs
#   agent-gateway   what AgentCore Gateway may do: invoke the channel Lambda
#   agent-channels  what the channel Lambda may do: the notifier secret, send email, logs

data "aws_iam_policy_document" "agentcore_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "runtime" {
  name               = "${local.prefix}-runtime"
  description        = "AgentCore runtime of the month-end agents (story 7.1)."
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

data "aws_iam_policy_document" "runtime" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken has no resource type; EU foundation models are addressed by region wildcard because an EU profile may route to any EU region.
  statement {
    sid     = "EuModelsOnly"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:${format(local.arn, "bedrock")}:inference-profile/eu.anthropic.claude-*",
      "arn:${format(local.arn, "bedrock")}:inference-profile/eu.amazon.nova-*",
      "arn:${data.aws_partition.current.partition}:bedrock:eu-*::foundation-model/anthropic.claude-*",
      "arn:${data.aws_partition.current.partition}:bedrock:eu-*::foundation-model/amazon.nova-*",
    ]
  }

  statement {
    sid       = "CallChannelTools"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.channels.gateway_arn]
  }

  statement {
    sid       = "OwnDatabricksSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.databricks_agent.arn]
  }

  statement {
    sid       = "PullImage"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [aws_ecr_repository.agent.arn]
  }

  statement {
    sid       = "RegistryToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:${format(local.arn, "logs")}:log-group:/aws/bedrock-agentcore/runtimes/*"]
  }

  statement {
    sid       = "Metrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["bedrock-agentcore"]
    }
  }

  statement {
    sid       = "WorkloadToken"
    actions   = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"]
    resources = ["arn:${format(local.arn, "bedrock-agentcore")}:workload-identity-directory/default*"]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "agent-runtime"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime.json
}

resource "aws_iam_role" "gateway" {
  name               = "${local.prefix}-gateway"
  description        = "AgentCore Gateway for the agents channel tools."
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

data "aws_iam_policy_document" "gateway" {
  statement {
    sid       = "InvokeChannelTools"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.channels.arn]
  }
}

resource "aws_iam_role_policy" "gateway" {
  name   = "agent-gateway"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway.json
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "channels" {
  name               = "${local.prefix}-channels"
  description        = "Channel tools Lambda: records drafts, checks approvals, sends approved items."
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "channels" {
  statement {
    sid       = "NotifierSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.databricks_notifier.arn]
  }

  statement {
    sid       = "SendAsChannelAddress"
    actions   = ["ses:SendEmail"]
    resources = [aws_sesv2_email_identity.channel.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.channels.arn}:*"]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "channels" {
  name   = "agent-channels"
  role   = aws_iam_role.channels.id
  policy = data.aws_iam_policy_document.channels.json
}
