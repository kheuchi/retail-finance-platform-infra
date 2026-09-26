# The finance catalog in Unity Catalog, stored in our governed bucket.
#
#   finance.raw     landing volume for generated source files
#   finance.bronze  as ingested, append-only
#   finance.silver  typed, deduplicated, validated
#   finance.gold    certified finance tables: what models and the agent read
#   finance.ops     build artifacts (job wheels), kept apart from data
#
# Access goes to account-level groups, never to named users: that is the
# enterprise pattern, and it keeps email addresses out of public plan logs.
# The Terraform service principal creates, and therefore owns, every object.
#
# Workspace-level objects, so they sit behind enable_unity_catalog and are removed
# in teardown step 1 while the workspace still exists. force_destroy is on because
# the data is synthetic and reproducible; on real data it would be off.

locals {
  catalog_count = local.unity_catalog_count
  schemas = {
    raw    = "Landing zone for generated source files. Nothing reads this directly except Bronze ingestion."
    bronze = "Source data as ingested: append-only, schema captured, no cleaning."
    silver = "Typed, deduplicated and validated. Reconciliation checks run here."
    gold   = "Certified finance tables. The only schema analysts, models and the agent read."
    ops    = "Operational artifacts such as job wheels. Not data."
  }
}

# ── Groups (account level) ───────────────────────────────────────────
resource "databricks_group" "data_engineers" {
  count    = local.catalog_count
  provider = databricks.account

  display_name = "finance-data-engineers"
}

resource "databricks_group" "analysts" {
  count    = local.catalog_count
  provider = databricks.account

  display_name = "finance-analysts"
}

resource "databricks_group_member" "owner_is_engineer" {
  count    = local.catalog_count * local.admin_user_count
  provider = databricks.account

  group_id  = databricks_group.data_engineers[0].id
  member_id = data.databricks_user.workspace_admin[0].id
}

# ── Catalog, schemas, landing volume ─────────────────────────────────
resource "databricks_catalog" "finance" {
  count    = local.catalog_count
  provider = databricks.workspace

  name           = "finance"
  comment        = "Retail accounting data: raw, bronze, silver, gold. Synthetic data only."
  storage_root   = "s3://${local.bootstrap.unity_catalog_bucket_name}/catalogs/finance"
  isolation_mode = "ISOLATED" # usable only from this workspace
  force_destroy  = true

  properties = {
    data_classification = "internal"
    contains_real_pii   = "false"
  }

  depends_on = [databricks_external_location.governed]
}

resource "databricks_schema" "finance" {
  for_each = local.catalog_count == 1 ? local.schemas : {}
  provider = databricks.workspace

  catalog_name  = databricks_catalog.finance[0].name
  name          = each.key
  comment       = each.value
  force_destroy = true
}

resource "databricks_volume" "landing" {
  count    = local.catalog_count
  provider = databricks.workspace

  catalog_name = databricks_catalog.finance[0].name
  schema_name  = databricks_schema.finance["raw"].name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Generated source files (CSV), one folder per source."
}

# Job libraries are installed from here rather than from workspace files. The first
# job could not read its wheel from the service principal's workspace folder; a
# volume sits in our S3 bucket, reached through the S3 gateway endpoint, which is a
# path already proven by the Unity Catalog validation. Databricks also recommends
# volumes for libraries on Unity Catalog compute.
resource "databricks_volume" "artifacts" {
  count    = local.catalog_count
  provider = databricks.workspace

  catalog_name = databricks_catalog.finance[0].name
  schema_name  = databricks_schema.finance["ops"].name
  name         = "artifacts"
  volume_type  = "MANAGED"
  comment      = "Job wheels deployed by Databricks Asset Bundles."
}

# ── Grants ───────────────────────────────────────────────────────────
# databricks_grants is authoritative: anything not listed here is revoked.
resource "databricks_grants" "catalog" {
  count    = local.catalog_count
  provider = databricks.workspace

  catalog = databricks_catalog.finance[0].name

  grant {
    principal  = databricks_group.data_engineers[0].display_name
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal  = databricks_group.analysts[0].display_name
    privileges = ["USE_CATALOG"]
  }
}

# Analysts read Gold and nothing else: no raw data, no half-cleaned data.
resource "databricks_grants" "gold" {
  count    = local.catalog_count
  provider = databricks.workspace

  schema = "${databricks_catalog.finance[0].name}.${databricks_schema.finance["gold"].name}"

  grant {
    principal  = databricks_group.analysts[0].display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}
