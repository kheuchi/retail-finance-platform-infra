# Cost and egress guardrails for the workspace.
#
# Four controls, each for a way the trial could go wrong:
#   1. A cluster policy, so compute is small, cheap and stops itself.
#   2. Users create clusters only through that policy.
#   3. Serverless compute, which runs outside our VPC, may reach only our governed
#      bucket and nothing on the internet.
#   4. Budget alerts on Databricks spend, which the AWS budget cannot see in detail.
#
# Honest limit: workspace admins bypass cluster policies. The owner is an admin, so
# for the owner the policy is a default, not a fence. The budget alerts are the
# control that still applies.

locals {
  guardrails_count = var.enable_workspace && var.enable_guardrails ? 1 : 0

  # Picked from the workspace's own node-type list on 2026-09-25: 2 or 4 cores,
  # local NVMe for Spark shuffle, Graviton first because it is cheapest per core.
  allowed_node_types = ["m6gd.large", "m6gd.xlarge", "m5d.large", "m5d.xlarge"]
  allowed_runtimes   = ["17.3.x-scala2.13", "16.4.x-scala2.12"]

  serverless_network_policy_id = "retail-finance-serverless"
}

# ── 1. Cluster policy ────────────────────────────────────────────────
resource "databricks_cluster_policy" "finance_small" {
  count    = local.guardrails_count
  provider = databricks.workspace

  name                  = "finance-small"
  description           = "Small, auto-terminating, spot-backed clusters for the finance platform. Default is single node."
  max_clusters_per_user = 1

  definition = jsonencode({
    "spark_version"       = { type = "allowlist", values = local.allowed_runtimes, defaultValue = local.allowed_runtimes[0] }
    "node_type_id"        = { type = "allowlist", values = local.allowed_node_types, defaultValue = local.allowed_node_types[0] }
    "driver_node_type_id" = { type = "allowlist", values = local.allowed_node_types, defaultValue = local.allowed_node_types[0] }

    # Stops by itself. The single biggest cost control on Databricks.
    "autotermination_minutes" = { type = "range", minValue = 10, maxValue = 30, defaultValue = 15 }

    # At most two workers. Default is single node: one VM, no workers.
    "num_workers"           = { type = "range", minValue = 0, maxValue = 2, defaultValue = 0 }
    "autoscale.max_workers" = { type = "range", maxValue = 2 }
    "spark_conf.spark.databricks.cluster.profile" = {
      type = "unlimited", defaultValue = "singleNode", isOptional = true
    }
    "spark_conf.spark.master"   = { type = "unlimited", defaultValue = "local[*]", isOptional = true }
    "custom_tags.ResourceClass" = { type = "unlimited", defaultValue = "SingleNode", isOptional = true }

    # Spot workers with an on-demand driver: much cheaper, and losing a worker
    # does not kill the cluster.
    "aws_attributes.availability"    = { type = "allowlist", values = ["SPOT_WITH_FALLBACK", "ON_DEMAND"], defaultValue = "SPOT_WITH_FALLBACK" }
    "aws_attributes.first_on_demand" = { type = "fixed", value = 1 }

    # Data access goes through Unity Catalog only. Instance profiles would be a
    # second, ungoverned path to S3.
    "aws_attributes.instance_profile_arn" = { type = "forbidden" }
    "data_security_mode"                  = { type = "allowlist", values = ["SINGLE_USER", "USER_ISOLATION"], defaultValue = "SINGLE_USER" }

    # Photon bills more DBUs per hour; not needed at this data volume.
    "runtime_engine" = { type = "fixed", value = "STANDARD" }
    "cluster_type"   = { type = "allowlist", values = ["all-purpose", "job"] }

    # Cost attribution on every instance, in AWS Cost Explorer.
    "custom_tags.CostCenter" = { type = "fixed", value = "finance-data-platform" }
    "custom_tags.Guardrail"  = { type = "fixed", value = "finance-small" }
  })
}

# ── 2. Clusters only through the policy ──────────────────────────────
data "databricks_group" "users" {
  count    = local.guardrails_count
  provider = databricks.workspace

  display_name = "users"
}

# No free-form cluster creation for ordinary users. With CAN_USE on the policy
# below they can still create clusters, but only within its limits.
resource "databricks_entitlements" "users" {
  count    = local.guardrails_count
  provider = databricks.workspace

  group_id              = data.databricks_group.users[0].id
  workspace_access      = true
  databricks_sql_access = true
  allow_cluster_create  = false
}

resource "databricks_permissions" "finance_small_policy" {
  count    = local.guardrails_count
  provider = databricks.workspace

  cluster_policy_id = databricks_cluster_policy.finance_small[0].id

  access_control {
    group_name       = data.databricks_group.users[0].display_name
    permission_level = "CAN_USE"
  }
}

# ── 3. Serverless egress: our bucket, nothing else ───────────────────
# Serverless compute runs in Databricks' account, not in our VPC, so the VPC's
# no-egress design does not cover it. This policy does: restricted mode, with the
# governed bucket as the only allowed destination.
#
# Lives under enable_workspace rather than enable_guardrails because its
# assignment cannot be deleted (the provider's Delete is a no-op), so the policy
# must outlive the workspace during teardown. The workspace depends on it, which
# makes Terraform destroy the workspace first.
resource "databricks_account_network_policy" "serverless_restricted" {
  count    = local.workspace_count
  provider = databricks.account

  # Databricks rejects IDs longer than 32 characters ("Invalid NetworkPolicyId").
  # The limit is undocumented; it was found by probing the API with read-only GETs
  # after the first apply failed on a 45-character ID. The precondition below turns
  # it into a plan-time error.
  network_policy_id = local.serverless_network_policy_id

  lifecycle {
    precondition {
      condition     = length(local.serverless_network_policy_id) <= 32
      error_message = "Databricks network policy IDs are limited to 32 characters."
    }
  }

  egress = {
    network_access = {
      restriction_mode = "RESTRICTED_ACCESS"
      allowed_storage_destinations = [
        {
          bucket_name              = local.bootstrap.unity_catalog_bucket_name
          region                   = var.aws_region
          storage_destination_type = "AWS_S3"
        }
      ]
      policy_enforcement = {
        enforcement_mode = "ENFORCED"
      }
    }
  }
}

resource "databricks_workspace_network_option" "this" {
  count    = local.workspace_count
  provider = databricks.account

  workspace_id      = databricks_mws_workspaces.this[0].workspace_id
  network_policy_id = databricks_account_network_policy.serverless_restricted[0].network_policy_id
}

# ── 4. Budget alerts on Databricks spend ─────────────────────────────
# Whole account, not just this workspace: the starter serverless workspace draws
# on the same trial credit. List-price dollars, monthly window, so the counter
# resets on the 1st; the trial straddles 2026-10-01.
resource "databricks_budget" "trial" {
  count    = local.workspace_count
  provider = databricks.account

  display_name = "${var.project_name}-trial-credit"

  dynamic "alert_configurations" {
    for_each = nonsensitive(var.budget_alert_email == null) ? [] : toset(["100", "200", "300", "380"])

    content {
      time_period        = "MONTH"
      trigger_type       = "CUMULATIVE_SPENDING_EXCEEDED"
      quantity_type      = "LIST_PRICE_DOLLARS_USD"
      quantity_threshold = alert_configurations.value

      action_configurations {
        action_type = "EMAIL_NOTIFICATION"
        target      = var.budget_alert_email
      }
    }
  }

  # The API normalises what it stores: thresholds come back as
  # "300.000000000000000000", alerts come back in a different order, and an empty
  # filter block appears. Without this every plan would show a phantom change and
  # hide real drift. The cost: changing thresholds or the email later needs this
  # line removed for one apply. Thresholds were checked against the API after creation.
  lifecycle {
    ignore_changes = [alert_configurations, filter]
  }
}
