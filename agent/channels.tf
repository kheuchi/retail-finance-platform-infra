# Stand-in channel: email through Amazon SES. Teams and ServiceNow would be more targets on
# the same gateway (ADR-006). In the SES sandbox the address must confirm a verification
# email once before anything can be sent.
resource "aws_sesv2_email_identity" "channel" {
  email_identity = var.alert_email
}

data "archive_file" "channels" {
  type        = "zip"
  source_file = "${path.module}/lambda/channels.py"
  output_path = "${path.module}/.build/channels.zip"
}

resource "aws_cloudwatch_log_group" "channels" {
  #checkov:skip=CKV_AWS_158:AWS-managed encryption is sufficient for tool-call logs that hold no secrets.
  name              = "/aws/lambda/${local.prefix}-channels"
  retention_in_days = 365
}

locals {
  # The agent's read-only tools (Unity Catalog functions shipped by the data bundle). The
  # figure check recomputes them, so it sees exactly what the agent saw.
  agent_functions = [for f in ["close_overview", "store_variances", "store_margin_alerts", "reconciliation_exceptions", "revenue_outlook", "cashier_case_count"] : "finance.agent.${f}"]
}

resource "aws_lambda_function" "channels" {
  #checkov:skip=CKV_AWS_117:Outside the VPC on purpose: it reaches SES and the Databricks API; the agent itself has no internet.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by the gateway; a failed call returns to the agent, no queue to dead-letter.
  #checkov:skip=CKV_AWS_173:Environment holds identifiers only; credentials are read from Secrets Manager at run time.
  #checkov:skip=CKV_AWS_272:Code signing is out of scope for this portfolio deployment.
  function_name    = "${local.prefix}-channels"
  description      = "MCP channel tools for the month-end agents: submit_draft, list_drafts, send_approved."
  role             = aws_iam_role.channels.arn
  runtime          = "python3.12"
  handler          = "channels.handler"
  filename         = data.archive_file.channels.output_path
  source_code_hash = data.archive_file.channels.output_base64sha256
  timeout          = 120
  memory_size      = 256
  architectures    = ["arm64"]

  reserved_concurrent_executions = 5

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DATABRICKS_HOST     = var.databricks_workspace_url
      WAREHOUSE_ID        = var.agent_warehouse_id
      NOTIFIER_SECRET_ARN = aws_secretsmanager_secret.databricks_notifier.arn
      CHANNEL_EMAIL       = var.alert_email
      AGENT_FUNCTIONS     = join(",", local.agent_functions)
    }
  }

  depends_on = [aws_cloudwatch_log_group.channels]
}

resource "aws_bedrockagentcore_gateway" "channels" {
  name            = "${local.prefix}-channels"
  description     = "MCP tools for the month-end agents. IAM-authenticated: only the agent runtime role may call it."
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
}

resource "aws_bedrockagentcore_gateway_target" "channels" {
  name               = "channels"
  gateway_identifier = aws_bedrockagentcore_gateway.channels.gateway_id
  description        = "Draft recording with figure check, draft status, sending of approved drafts."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.channels.arn

        tool_schema {
          inline_payload {
            name        = "submit_draft"
            description = "Record a draft for review. Every number in the body is checked against the agent tool functions for that month; a draft with an unknown number is stored as rejected_by_check."
            input_schema {
              type = "object"
              property {
                name        = "month"
                type        = "string"
                description = "Close month, YYYY-MM."
                required    = true
              }
              property {
                name        = "audience"
                type        = "string"
                description = "Who the draft is for: cfo, store_controlling or gl_team."
                required    = true
              }
              property {
                name     = "title"
                type     = "string"
                required = true
              }
              property {
                name        = "body"
                type        = "string"
                description = "Draft text with every figure as returned by the tools."
                required    = true
              }
            }
          }
          inline_payload {
            name        = "list_drafts"
            description = "List drafts of a month with their status and the latest controller decision."
            input_schema {
              type = "object"
              property {
                name     = "month"
                type     = "string"
                required = true
              }
            }
          }
          inline_payload {
            name        = "send_approved"
            description = "Send one approved draft to its channel and publish it for Power BI. Refused unless a controller approved it; sends once."
            input_schema {
              type = "object"
              property {
                name     = "draft_id"
                type     = "string"
                required = true
              }
            }
          }
        }
      }
    }
  }
}
