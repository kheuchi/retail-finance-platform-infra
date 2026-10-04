# Created once the first image is in ECR (var.agent_image_tag). The runtime runs inside the
# Databricks VPC's private subnets: no internet, only the endpoints in network.tf.
# Teardown note: AgentCore's network interfaces can outlive the runtime for a while
# (terraform-provider-aws #45099); delete the runtime first, then the security group.
resource "aws_bedrockagentcore_agent_runtime" "month_end" {
  count = var.agent_image_tag == null ? 0 : 1

  agent_runtime_name = replace("${local.prefix}_month_end", "-", "_")
  description        = "Month-end close agents: Deep Agents supervisor + sub-agents (story 7.1)."
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:${var.agent_image_tag}"
    }
  }

  network_configuration {
    network_mode = "VPC"
    network_mode_config {
      subnets         = local.bootstrap.databricks_workspace_subnet_ids
      security_groups = [aws_security_group.runtime.id]
    }
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  environment_variables = {
    DATABRICKS_HOST       = var.databricks_workspace_url
    DATABRICKS_SECRET_ARN = aws_secretsmanager_secret.databricks_agent.arn
    AGENT_TOOLS_MCP_URL   = "${var.databricks_workspace_url}/api/2.0/mcp/functions/finance/agent"
    GATEWAY_URL           = aws_bedrockagentcore_gateway.channels.gateway_url
    MODEL_ID              = var.agent_model_id
  }
}
