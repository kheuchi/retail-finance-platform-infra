# Pipeline identities: one duty each (story 4.5).
#
#   terraform-platform       account admin; runs this Terraform (unchanged)
#   finance-data-deployer    deploys the data bundle from GitHub Actions: creates and
#                            updates jobs, uploads wheels; nothing else
#   finance-pipeline-runner  the identity jobs run as: reads and writes the finance
#                            schemas; cannot administer anything
#
# Before this split, terraform-platform deployed and ran the data jobs too, so a bug
# or a compromise in data code ran with account-admin power (risk R-10).
#
# Both are ordinary workspace users. They get cluster-policy use through the users
# group (guardrails.tf) and no free-form cluster creation. The deployer may launch
# jobs as the runner (Service Principal User role) and as nothing else.

resource "databricks_service_principal" "deployer" {
  count    = local.catalog_count
  provider = databricks.account

  display_name = "finance-data-deployer"
}

resource "databricks_service_principal" "runner" {
  count    = local.catalog_count
  provider = databricks.account

  display_name = "finance-pipeline-runner"
}

resource "databricks_mws_permission_assignment" "deployer" {
  count    = local.catalog_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = databricks_service_principal.deployer[0].id
  permissions  = ["USER"]
}

resource "databricks_mws_permission_assignment" "runner" {
  count    = local.catalog_count
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this[0].workspace_id
  principal_id = databricks_service_principal.runner[0].id
  permissions  = ["USER"]
}

# The users group has no entitlements in this workspace (locked), so workspace access
# is granted per principal. No cluster creation outside the policies.
resource "databricks_entitlements" "deployer" {
  count    = local.catalog_count
  provider = databricks.workspace

  service_principal_id = databricks_service_principal.deployer[0].id
  workspace_access     = true

  depends_on = [databricks_mws_permission_assignment.deployer]
}

resource "databricks_entitlements" "runner" {
  count    = local.catalog_count
  provider = databricks.workspace

  service_principal_id = databricks_service_principal.runner[0].id
  workspace_access     = true

  depends_on = [databricks_mws_permission_assignment.runner]
}

# Only the deployer may set run_as to the runner. The rule set is authoritative for
# this service principal: account admins keep their implicit rights.
resource "databricks_access_control_rule_set" "runner_users" {
  count    = local.catalog_count
  provider = databricks.account

  name = "accounts/${var.databricks_account_id}/servicePrincipals/${databricks_service_principal.runner[0].application_id}/ruleSets/default"

  grant_rules {
    principals = ["servicePrincipals/${databricks_service_principal.deployer[0].application_id}"]
    role       = "roles/servicePrincipal.user"
  }
}

locals {
  # What the runner needs in every finance schema: read, write, create tables, and use
  # the volumes (landing files, Auto Loader checkpoints, job wheels).
  runner_schema_privileges = ["USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
  pipeline_schemas         = local.catalog_count == 1 ? toset(["raw", "bronze", "silver", "ops", "ml"]) : toset([])
}

# Gold has its own grants resource (catalog.tf), shared with the analysts.
resource "databricks_grants" "pipeline_schemas" {
  for_each = local.pipeline_schemas
  provider = databricks.workspace

  schema = "${databricks_catalog.finance[0].name}.${databricks_schema.finance[each.key].name}"

  grant {
    principal  = databricks_service_principal.runner[0].application_id
    privileges = each.key == "ml" ? concat(local.runner_schema_privileges, ["CREATE_MODEL", "EXECUTE"]) : local.runner_schema_privileges
  }

  # The deployer only uploads job wheels to ops.artifacts.
  dynamic "grant" {
    for_each = each.key == "ops" ? [1] : []
    content {
      principal  = databricks_service_principal.deployer[0].application_id
      privileges = ["USE_SCHEMA", "READ_VOLUME", "WRITE_VOLUME"]
    }
  }
}
