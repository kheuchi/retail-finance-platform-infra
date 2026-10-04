# AI agent platform, Databricks side (story 7.1, ADR-006).
#
#   finance-month-end-agent   the agent's identity: runs the read-only tool functions in
#                             finance.agent over five Gold tables; writes nothing
#   finance-close-notifier    the channel tools' identity (Lambda behind AgentCore Gateway):
#                             records drafts, reads approvals, publishes approved commentary
#   finance-controllers       people who approve drafts; the only writers of approvals
#
# Tables of record (drafts, approvals, published commentary) are created here, owned by
# the platform, so their grants are set in the same apply. The tool functions are code
# and ship with the data bundle, created by the runner in finance.agent.

locals {
  agent_count = local.catalog_count
  # The Gold tables the agent's tools read: store level or above. Never fraud_scores or refunds (cashier level, R-12).
  agent_gold_tables = local.agent_count == 1 ? toset(["daily_revenue", "budget_variance", "margin", "margin_alerts", "recon_exceptions", "revenue_forecast"]) : toset([])
}

resource "databricks_service_principal" "agent" {
  count    = local.agent_count
  provider = databricks.account

  display_name = "finance-month-end-agent"
}

resource "databricks_service_principal" "notifier" {
  count    = local.agent_count
  provider = databricks.account

  display_name = "finance-close-notifier"
}

resource "databricks_mws_permission_assignment" "agent" {
  count    = local.agent_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = databricks_service_principal.agent[0].id
  permissions  = ["USER"]
}

resource "databricks_mws_permission_assignment" "notifier" {
  count    = local.agent_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = databricks_service_principal.notifier[0].id
  permissions  = ["USER"]
}

resource "databricks_entitlements" "agent" {
  count    = local.agent_count
  provider = databricks.workspace

  service_principal_id = databricks_service_principal.agent[0].id
  workspace_access     = true

  depends_on = [databricks_mws_permission_assignment.agent]
}

resource "databricks_entitlements" "notifier" {
  count    = local.agent_count
  provider = databricks.workspace

  service_principal_id = databricks_service_principal.notifier[0].id
  workspace_access     = true

  depends_on = [databricks_mws_permission_assignment.notifier]
}

resource "databricks_group" "controllers" {
  count    = local.agent_count
  provider = databricks.workspace

  display_name = "finance-controllers"
}

# The owner plays the financial controller in this portfolio.
resource "databricks_group_member" "controller_owner" {
  count    = local.admin_user_count == 1 && local.agent_count == 1 ? 1 : 0
  provider = databricks.workspace

  group_id  = databricks_group.controllers[0].id
  member_id = data.databricks_user.workspace_admin[0].id
}

# Small serverless warehouse for the channel tools' SQL (drafts, approvals, figure check)
# and for creating the tables below. Stops after five idle minutes.
resource "databricks_sql_endpoint" "agent" {
  count    = local.agent_count
  provider = databricks.workspace

  name                      = "finance-agent"
  cluster_size              = "2X-Small"
  min_num_clusters          = 1
  max_num_clusters          = 1
  auto_stop_mins            = 5
  enable_serverless_compute = true
  warehouse_type            = "PRO"

  tags {
    custom_tags {
      key   = "CostCenter"
      value = "finance-data-platform"
    }
  }
}

resource "databricks_permissions" "agent_warehouse" {
  count    = local.agent_count
  provider = databricks.workspace

  sql_endpoint_id = databricks_sql_endpoint.agent[0].id

  access_control {
    service_principal_name = databricks_service_principal.notifier[0].application_id
    permission_level       = "CAN_USE"
  }
}

# ── Tables of record ─────────────────────────────────────────────────
resource "databricks_sql_table" "agent_drafts" {
  count    = local.agent_count
  provider = databricks.workspace

  catalog_name = databricks_catalog.finance[0].name
  schema_name  = databricks_schema.finance["agent"].name
  name         = "drafts"
  table_type   = "MANAGED"
  warehouse_id = databricks_sql_endpoint.agent[0].id
  comment      = "Agent drafts: written only by the channel tools after the figure check (story 7.1)."

  column {
    name = "draft_id"
    type = "string"
  }
  column {
    name = "month"
    type = "string"
  }
  column {
    name = "audience"
    type = "string"
  }
  column {
    name = "title"
    type = "string"
  }
  column {
    name = "body"
    type = "string"
  }
  column {
    name = "status"
    type = "string"
  }
  column {
    name = "check_detail"
    type = "string"
  }
  column {
    name = "created_at"
    type = "timestamp"
  }
  column {
    name = "sent_at"
    type = "timestamp"
  }
  column {
    name = "channel"
    type = "string"
  }
}

resource "databricks_sql_table" "agent_approvals" {
  count    = local.agent_count
  provider = databricks.workspace

  catalog_name = databricks_catalog.finance[0].name
  schema_name  = databricks_schema.finance["agent"].name
  name         = "approvals"
  table_type   = "MANAGED"
  warehouse_id = databricks_sql_endpoint.agent[0].id
  comment      = "Controller decisions on drafts. Only finance-controllers can write here."

  column {
    name = "draft_id"
    type = "string"
  }
  column {
    name = "decision"
    type = "string"
  }
  column {
    name = "approver"
    type = "string"
  }
  column {
    name = "decided_at"
    type = "timestamp"
  }
  column {
    name = "note"
    type = "string"
  }
}

resource "databricks_sql_table" "close_commentary" {
  count    = local.agent_count
  provider = databricks.workspace

  catalog_name = databricks_catalog.finance[0].name
  schema_name  = databricks_schema.finance["gold"].name
  name         = "close_commentary"
  table_type   = "MANAGED"
  warehouse_id = databricks_sql_endpoint.agent[0].id
  comment      = "Approved month-end commentary, published by the channel tools; read by Power BI and analysts."

  column {
    name = "month"
    type = "string"
  }
  column {
    name = "title"
    type = "string"
  }
  column {
    name = "body"
    type = "string"
  }
  column {
    name = "draft_id"
    type = "string"
  }
  column {
    name = "approved_by"
    type = "string"
  }
  column {
    name = "published_at"
    type = "timestamp"
  }
}

# ── Grants ───────────────────────────────────────────────────────────
resource "databricks_grants" "agent_schema" {
  count    = local.agent_count
  provider = databricks.workspace

  schema = "${databricks_catalog.finance[0].name}.${databricks_schema.finance["agent"].name}"

  # The runner creates the tool functions from the data bundle.
  grant {
    principal  = databricks_service_principal.runner[0].application_id
    privileges = ["USE_SCHEMA", "CREATE_FUNCTION", "EXECUTE"]
  }

  grant {
    principal  = databricks_service_principal.agent[0].application_id
    privileges = ["USE_SCHEMA", "EXECUTE"]
  }

  grant {
    principal  = databricks_service_principal.notifier[0].application_id
    privileges = ["USE_SCHEMA", "EXECUTE"]
  }

  grant {
    principal  = databricks_group.controllers[0].display_name
    privileges = ["USE_SCHEMA"]
  }
}

resource "databricks_grants" "agent_gold_tables" {
  for_each = local.agent_gold_tables
  provider = databricks.workspace

  table = "${databricks_catalog.finance[0].name}.gold.${each.key}"

  grant {
    principal  = databricks_service_principal.agent[0].application_id
    privileges = ["SELECT"]
  }

  grant {
    principal  = databricks_service_principal.notifier[0].application_id
    privileges = ["SELECT"]
  }
}

resource "databricks_grants" "agent_drafts" {
  count    = local.agent_count
  provider = databricks.workspace

  table = databricks_sql_table.agent_drafts[0].id

  grant {
    principal  = databricks_service_principal.notifier[0].application_id
    privileges = ["SELECT", "MODIFY"]
  }

  grant {
    principal  = databricks_group.controllers[0].display_name
    privileges = ["SELECT"]
  }
}

resource "databricks_grants" "agent_approvals" {
  count    = local.agent_count
  provider = databricks.workspace

  table = databricks_sql_table.agent_approvals[0].id

  grant {
    principal  = databricks_group.controllers[0].display_name
    privileges = ["SELECT", "MODIFY"]
  }

  grant {
    principal  = databricks_service_principal.notifier[0].application_id
    privileges = ["SELECT"]
  }
}

resource "databricks_grants" "close_commentary" {
  count    = local.agent_count
  provider = databricks.workspace

  table = databricks_sql_table.close_commentary[0].id

  grant {
    principal  = databricks_service_principal.notifier[0].application_id
    privileges = ["SELECT", "MODIFY"]
  }
}
