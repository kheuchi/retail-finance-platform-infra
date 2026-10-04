# AI agent platform (story 7.1, ADR-006): who may build it and who may ship its image.
#
# The agent's AWS resources live in their own stack, agent/, with their own deploy
# role. That keeps this stack's deploy role unchanged (and under the inline-policy size
# limit) and gives the agent platform a separate blast radius, as databricks/ has.
#
#   <project>-github-agent-deploy  Terraform for agent/: endpoints, ECR, AgentCore,
#                                  Lambda channel tools, SES identity, secrets
#   <project>-github-agent-ci      the data repo's main branch: push the agent image to
#                                  ECR and invoke the agent runtime; nothing else
#
# Phase 1 of a two-phase change: these roles are created here; the agent/ stack that
# uses them is applied afterwards.

locals {
  agent_prefix           = "${var.project_name}-agent"
  agent_ecr_repository   = "${var.project_name}-agent"
  agent_deploy_role_name = "${var.project_name}-github-agent-deploy"
  agent_ci_role_name     = "${var.project_name}-github-agent-ci"
  data_repo_oidc_subject = "repo:${var.github_organization}@${var.github_organization_id}/${var.data_repository}@${var.data_repository_id}:ref:refs/heads/main"
  account_region_arn     = "${data.aws_partition.current.partition}:%s:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

# ── Deploy role for the agent/ stack ──────────────────────────────────
resource "aws_iam_role" "github_agent_deploy" {
  name                 = local.agent_deploy_role_name
  description          = "Human-gated Terraform deployment of the agent platform (agent/ stack)."
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_agent_deploy" {
  #checkov:skip=CKV_AWS_356:ec2:Describe*, ecr:GetAuthorizationToken and resource creation before an ID exists cannot be resource-scoped; creation is constrained by RequestTag.
  #checkov:skip=CKV_AWS_111:Same statements.

  statement {
    sid       = "AgentState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/agent/*"]
  }

  statement {
    sid     = "ReadStateBucketAndBootstrapOutputs"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/bootstrap/terraform.tfstate"
    ]
  }

  statement {
    sid       = "DescribeNetworkAndRegistry"
    effect    = "Allow"
    actions   = ["ec2:Describe*", "ecr:GetAuthorizationToken", "sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # New endpoints and security groups: only when the request tags them as ours.
  statement {
    sid       = "CreateTaggedNetwork"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint", "ec2:CreateSecurityGroup", "ec2:CreateTags", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Application"
      values   = [var.project_name]
    }
  }

  # Existing project resources (VPC, subnets, endpoint SG) and the ones created above.
  statement {
    sid    = "ManageTaggedNetwork"
    effect = "Allow"
    actions = [
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress", "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:CreateTags", "ec2:DeleteTags"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Application"
      values   = [var.project_name]
    }
  }

  statement {
    sid       = "EndpointPrivateDns"
    effect    = "Allow"
    actions   = ["route53:AssociateVPCWithHostedZone", "route53:DisassociateVPCFromHostedZone"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid    = "AgentImageRepository"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories", "ecr:ListTagsForResource",
      "ecr:TagResource", "ecr:UntagResource", "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy", "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
      "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy", "ecr:DeleteRepositoryPolicy", "ecr:DescribeImages",
      "ecr:BatchDeleteImage", "ecr:ListImages"
    ]
    resources = ["arn:${format(local.account_region_arn, "ecr")}:repository/${local.agent_ecr_repository}"]
  }

  statement {
    sid    = "AgentRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.agent_prefix}-*"]
  }

  statement {
    sid       = "PassAgentRolesToTheirServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.agent_prefix}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["bedrock-agentcore.amazonaws.com", "lambda.amazonaws.com"]
    }
  }

  # AgentCore creates its network interfaces in our VPC through a service-linked role.
  statement {
    sid       = "AgentCoreServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*bedrock-agentcore.amazonaws.com/*"]
  }

  statement {
    sid    = "ChannelLambda"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
      "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:ListVersionsByFunction",
      "lambda:GetFunctionCodeSigningConfig", "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
      "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags"
    ]
    resources = ["arn:${format(local.account_region_arn, "lambda")}:function:${local.agent_prefix}-*"]
  }

  statement {
    sid    = "AgentLogGroups"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource", "logs:TagLogGroup"
    ]
    resources = [
      "arn:${format(local.account_region_arn, "logs")}:log-group:/aws/lambda/${local.agent_prefix}-*",
      "arn:${format(local.account_region_arn, "logs")}:log-group:/aws/bedrock-agentcore/*"
    ]
  }

  statement {
    sid       = "DescribeLogGroups"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${format(local.account_region_arn, "logs")}:log-group:*"]
  }

  statement {
    sid       = "ChannelEmailIdentity"
    effect    = "Allow"
    actions   = ["ses:CreateEmailIdentity", "ses:DeleteEmailIdentity", "ses:GetEmailIdentity", "ses:TagResource", "ses:UntagResource", "ses:ListTagsForResource"]
    resources = ["arn:${format(local.account_region_arn, "ses")}:identity/*"]
  }

  # Containers for the Databricks credentials of the agent and of the channel tools.
  # Terraform creates them empty; values are set out of band and never enter state.
  statement {
    sid    = "AgentSecretContainers"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy", "secretsmanager:TagResource", "secretsmanager:UntagResource",
      "secretsmanager:UpdateSecret"
    ]
    resources = ["arn:${format(local.account_region_arn, "secretsmanager")}:secret:${var.project_name}/agent/*"]
  }

  # AgentCore resource IDs are generated by the service, so they cannot be named in
  # advance; this is scoped to the service, this account and this region.
  statement {
    sid    = "AgentCore"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime", "bedrock-agentcore:UpdateAgentRuntime", "bedrock-agentcore:DeleteAgentRuntime",
      "bedrock-agentcore:GetAgentRuntime", "bedrock-agentcore:ListAgentRuntimes", "bedrock-agentcore:ListAgentRuntimeVersions",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint", "bedrock-agentcore:DeleteAgentRuntimeEndpoint",
      "bedrock-agentcore:GetAgentRuntimeEndpoint", "bedrock-agentcore:ListAgentRuntimeEndpoints",
      "bedrock-agentcore:CreateGateway", "bedrock-agentcore:UpdateGateway", "bedrock-agentcore:DeleteGateway",
      "bedrock-agentcore:GetGateway", "bedrock-agentcore:ListGateways",
      "bedrock-agentcore:CreateGatewayTarget", "bedrock-agentcore:UpdateGatewayTarget", "bedrock-agentcore:DeleteGatewayTarget",
      "bedrock-agentcore:GetGatewayTarget", "bedrock-agentcore:ListGatewayTargets", "bedrock-agentcore:SynchronizeGatewayTargets",
      "bedrock-agentcore:CreateWorkloadIdentity", "bedrock-agentcore:GetWorkloadIdentity", "bedrock-agentcore:DeleteWorkloadIdentity",
      "bedrock-agentcore:UpdateWorkloadIdentity",
      "bedrock-agentcore:CreatePolicyEngine", "bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:DeletePolicyEngine",
      "bedrock-agentcore:UpdatePolicyEngine", "bedrock-agentcore:CreatePolicy", "bedrock-agentcore:GetPolicy",
      "bedrock-agentcore:UpdatePolicy", "bedrock-agentcore:DeletePolicy", "bedrock-agentcore:ListPolicies",
      "bedrock-agentcore:ManageResourceScopedPolicy", "bedrock-agentcore:ManageAdminPolicy",
      "bedrock-agentcore:TagResource", "bedrock-agentcore:UntagResource", "bedrock-agentcore:ListTagsForResource"
    ]
    resources = ["arn:${format(local.account_region_arn, "bedrock-agentcore")}:*"]
  }
}

resource "aws_iam_role_policy" "github_agent_deploy" {
  name   = "agent-deployment"
  role   = aws_iam_role.github_agent_deploy.id
  policy = data.aws_iam_policy_document.github_agent_deploy.json
}

# ── CI role for the data repo: push the image, invoke the runtime ─────
data "aws_iam_policy_document" "github_agent_ci_trust" {
  statement {
    sid     = "DataRepositoryMainBranch"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_provider_id}:sub"
      values   = [local.data_repo_oidc_subject]
    }
  }
}

resource "aws_iam_role" "github_agent_ci" {
  name                 = local.agent_ci_role_name
  description          = "Data repo main branch: push the agent image and invoke the agent runtime."
  assume_role_policy   = data.aws_iam_policy_document.github_agent_ci_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_agent_ci" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken has no resource type.

  statement {
    sid       = "RegistryLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushAgentImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages"
    ]
    resources = ["arn:${format(local.account_region_arn, "ecr")}:repository/${local.agent_ecr_repository}"]
  }

  statement {
    sid       = "InvokeAgentRuntime"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = ["arn:${format(local.account_region_arn, "bedrock-agentcore")}:runtime/*"]
  }
}

resource "aws_iam_role_policy" "github_agent_ci" {
  name   = "agent-ci"
  role   = aws_iam_role.github_agent_ci.id
  policy = data.aws_iam_policy_document.github_agent_ci.json
}

# The plan role (read only) must refresh the agent/ stack too.
data "aws_iam_policy_document" "github_plan_agent" {
  #checkov:skip=CKV_AWS_356:Read-only describe calls across services whose resource IDs are generated.
  statement {
    sid       = "ReadAgentState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/agent/terraform.tfstate"]
  }

  statement {
    sid       = "LockAgentState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/agent/terraform.tfstate.tflock"]
  }

  statement {
    sid    = "ReadAgentPlatform"
    effect = "Allow"
    # Named Get actions only: a wildcard would include AgentCore Identity's token
    # retrieval calls, which hand out credentials.
    actions = [
      "bedrock-agentcore:GetAgentRuntime", "bedrock-agentcore:GetAgentRuntimeEndpoint",
      "bedrock-agentcore:GetGateway", "bedrock-agentcore:GetGatewayTarget",
      "bedrock-agentcore:GetWorkloadIdentity", "bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:GetPolicy",
      "bedrock-agentcore:List*",
      "ses:GetEmailIdentity", "ses:ListTagsForResource",
      "secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_plan_agent" {
  name   = "agent-read"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_agent.json
}
