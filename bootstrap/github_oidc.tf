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
    sid       = "ManageProjectBudget"
    effect    = "Allow"
    actions   = ["budgets:ModifyBudget", "budgets:ViewBudget"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "bootstrap-deployment"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
