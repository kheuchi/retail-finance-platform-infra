locals {
  # GitHub's hardened OIDC subject identifies the owner and repository by their
  # immutable numeric IDs, so a rename or a reused name cannot inherit this trust.
  github_oidc_subject     = "${var.github_organization}@${var.github_organization_id}/${var.github_repository}@${var.github_repository_id}"
  github_oidc_provider_id = "token.actions.githubusercontent.com"
  github_plan_role_name   = "${var.project_name}-github-plan"
  github_deploy_role_name = "${var.project_name}-github-deploy"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_provider_id}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS resolved this CA thumbprint when the provider was created. Declaring it
  # prevents perpetual drift while IAM continues to validate GitHub's certificate.
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
}

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    sid     = "GitHubRepositoryPlanAccess"
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
      values   = ["repo:${local.github_oidc_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = local.github_plan_role_name
  description          = "Read-only Terraform planning from the approved GitHub repository."
  assume_role_policy   = data.aws_iam_policy_document.github_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_plan_read_only" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_plan_state_lock" {
  statement {
    sid    = "ReadTerraformStateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/bootstrap/terraform.tfstate"
    ]
  }

  statement {
    sid    = "ManageTerraformStateLockOnly"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/bootstrap/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "github_plan_state_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_state_lock.json
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    sid     = "ProtectedGitHubEnvironmentDeployAccess"
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
      values   = ["repo:${local.github_oidc_subject}:environment:${var.github_deploy_environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = local.github_deploy_role_name
  description          = "Human-gated Terraform deployment from the approved GitHub environment."
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  # Accepted, reviewed exception. See docs/security/checkov-exceptions.md.
  # Only the account password policy still uses "*": IAM account-level settings have
  # no ARN to scope to, so AWS rejects a resource-qualified statement for them. Every
  # other statement in this document names its exact resources.
  #checkov:skip=CKV_AWS_356:Residual "*" is the IAM account password policy, which AWS does not expose as a resource.
  #checkov:skip=CKV_AWS_111:Same statement. iam:UpdateAccountPasswordPolicy cannot be resource-constrained.

  statement {
    sid    = "ManageBootstrapStateBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:DeleteObject",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetObject",
      # The provider reads every bucket sub-configuration on refresh, and these
      # IAM action names do not begin with "GetBucket", so the wildcard misses
      # them. They are read-only and scoped to the state bucket below.
      "s3:GetAccelerateConfiguration",
      "s3:GetAnalyticsConfiguration",
      "s3:GetIntelligentTieringConfiguration",
      "s3:GetInventoryConfiguration",
      "s3:GetMetricsConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:PutBucket*",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  statement {
    sid    = "ManageAuditLogBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucketPolicy",
      "s3:GetAccelerateConfiguration",
      "s3:GetAnalyticsConfiguration",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetIntelligentTieringConfiguration",
      "s3:GetInventoryConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetMetricsConfiguration",
      "s3:GetObject",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
      "s3:PutBucket*",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration"
    ]
    resources = [
      local.audit_bucket_arn,
      "${local.audit_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "ManageManagementEventTrail"
    effect = "Allow"
    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:GetTrail",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:ListTags",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:RemoveTags",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail"
    ]
    resources = [local.audit_trail_arn]
  }

  statement {
    # DescribeTrails and ListTrails are account-wide enumeration calls. AWS defines
    # no resource type for them, so a trail-scoped ARN is rejected outright and "*"
    # is the only expressible form. They are read-only and disclose trail
    # configuration, not log contents.
    sid    = "EnumerateCloudTrailTrails"
    effect = "Allow"
    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:ListTrails"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageAuditLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DeleteMetricFilter",
      "logs:DeleteRetentionPolicy",
      "logs:ListTagsForResource",
      "logs:PutMetricFilter",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource"
    ]
    resources = [
      local.audit_log_group_arn,
      "${local.audit_log_group_arn}:*"
    ]
  }

  statement {
    sid    = "ManageSecurityAlerting"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource"
    ]
    resources = [local.alarm_arn_prefix]
  }

  statement {
    sid    = "ManageSecurityTopic"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetSubscriptionAttributes",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTagsForResource",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:TagResource",
      "sns:Unsubscribe",
      "sns:UntagResource"
    ]
    resources = [
      local.security_topic_arn,
      "${local.security_topic_arn}:*"
    ]
  }

  statement {
    sid    = "ManageCloudTrailLogsRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole"
    ]
    resources = [local.audit_cwl_role_arn]
  }

  statement {
    # CloudTrail is handed this role when the trail is wired to CloudWatch Logs, so
    # the deploy role must be allowed to pass it. Unscoped PassRole is a privilege
    # escalation path, so it is narrowed to this one role and further restricted to
    # the CloudTrail service: the role cannot be passed to anything else.
    sid       = "PassCloudTrailLogsRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.audit_cwl_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    # Enumeration calls with no AWS-defined resource type, so a scoped ARN is
    # rejected and "*" is the only expressible form. All are read-only and return
    # configuration, not data. Keeping them in their own statement makes the
    # unavoidable wildcards easy to audit against the write statements above.
    sid    = "ReadAlertingConfiguration"
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "logs:DescribeLogGroups",
      "logs:DescribeMetricFilters"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageAccountBootstrapControls"
    effect    = "Allow"
    actions   = ["iam:GetAccountPasswordPolicy", "iam:UpdateAccountPasswordPolicy"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageProjectGitHubRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-github-*"
    ]
  }

  statement {
    sid    = "ReadAttachedAWSManagedPolicy"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"]
  }

  statement {
    sid    = "ManageGitHubIdentityProvider"
    effect = "Allow"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviderTags",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_provider_id}"
    ]
  }

  statement {
    sid    = "ManageProjectBudget"
    effect = "Allow"
    actions = [
      "budgets:ModifyBudget",
      "budgets:ViewBudget",
      # Budget tagging is a separate action family from ModifyBudget/ViewBudget.
      # The provider lists tags on every Budget refresh.
      "budgets:ListTagsForResource",
      "budgets:TagResource",
      "budgets:UntagResource"
    ]
    # AWS Budgets supports resource-level permissions, so name the one budget this
    # role may touch rather than granting it every budget in the account. Take the
    # ARN from the resource itself instead of assembling it from parts, so the
    # policy cannot drift from the budget it is meant to describe.
    resources = [aws_budgets_budget.monthly.arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "bootstrap-deployment"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
