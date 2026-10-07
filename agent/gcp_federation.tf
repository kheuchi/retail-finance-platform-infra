# ADR-006 deviation (D-032): while AWS holds AgentCore Runtime and Bedrock, the agent runs on
# Google's Agent Runtime. It reaches the channel tools on AgentCore Gateway by trading a Google
# ID token (issued to its service account, audience below) for short AWS credentials. No key is
# stored anywhere; the role can only invoke the gateway.

locals {
  gcp_gateway_audience = "retail-finance-agent-gateway"
  gcp_federation_count = var.gcp_agent_sa_unique_id == null ? 0 : 1
}

data "aws_iam_policy_document" "gcp_agent_trust" {
  count = local.gcp_federation_count

  statement {
    sid     = "GoogleAgentRuntimeServiceAccount"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["accounts.google.com"]
    }
    # sub: the agent's service account (numeric ID); oaud: the audience it asked the token for.
    condition {
      test     = "StringEquals"
      variable = "accounts.google.com:sub"
      values   = [var.gcp_agent_sa_unique_id]
    }
    condition {
      test     = "StringEquals"
      variable = "accounts.google.com:oaud"
      values   = [local.gcp_gateway_audience]
    }
  }
}

resource "aws_iam_role" "gcp_agent" {
  count                = local.gcp_federation_count
  name                 = "${local.prefix}-gcp"
  description          = "Month-end agents on Google Agent Runtime: may only invoke the channel-tools gateway."
  assume_role_policy   = data.aws_iam_policy_document.gcp_agent_trust[0].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gcp_agent" {
  statement {
    sid       = "CallChannelToolsOnly"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.channels.gateway_arn]
  }
}

resource "aws_iam_role_policy" "gcp_agent" {
  count  = local.gcp_federation_count
  name   = "gateway-only"
  role   = aws_iam_role.gcp_agent[0].id
  policy = data.aws_iam_policy_document.gcp_agent.json
}
