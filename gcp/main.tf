# Google side of the month-end agents (story 7.1, ADR-006 deviation D-032).
#
#   finance-month-end-agent   the identity the agent runs as on Agent Runtime: may call Gemini
#                             (Vertex AI), read its one Databricks secret, write logs. Its ID
#                             token is what AWS trusts to assume the gateway-only role.
#   finance-agent-deployer    used by the data repo's main branch through Workload Identity
#                             Federation (no key): deploys the agent, acts as the runtime SA
#
# Applied by the owner from the workstation (bootstrap-style, like bootstrap/ on AWS); the
# data repo deploys workloads through the federation created here.

locals {
  services = toset([
    "aiplatform.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  reasoning_engine_service_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}

resource "google_project_service" "this" {
  for_each           = local.services
  service            = each.key
  disable_on_destroy = false # the project is shared; never switch off APIs others may use
}

# ── Runtime identity ─────────────────────────────────────────────────
resource "google_service_account" "runtime" {
  account_id   = "finance-month-end-agent"
  display_name = "Month-end close agents (Agent Runtime)"
  description  = "Runs the agents: Gemini via Vertex AI, its Databricks secret, logs. Assumes the AWS gateway-only role by federation."
}

resource "google_project_iam_member" "runtime" {
  for_each = toset(["roles/aiplatform.user", "roles/logging.logWriter", "roles/cloudtrace.agent"])
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.runtime.email}"
}

# Agent Runtime's service agent starts the container as the runtime identity.
resource "google_service_account_iam_member" "service_agent_uses_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.reasoning_engine_service_agent
  depends_on         = [google_project_service.this]
}

# ── The agent's Databricks credentials (value set out of band, never in state) ──
resource "google_secret_manager_secret" "databricks_agent" {
  secret_id = "finance-agent-databricks"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_iam_member" "runtime_reads_secret" {
  secret_id = google_secret_manager_secret.databricks_agent.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "service_agent_reads_secret" {
  secret_id = google_secret_manager_secret.databricks_agent.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.reasoning_engine_service_agent
}

# ── Staging bucket for deployments (agent package, requirements) ──────
resource "google_storage_bucket" "staging" {
  name                        = "${var.project_id}-finance-agent-staging"
  location                    = "EU"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # teardown: packages are rebuilt from Git

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# ── GitHub (data repo, main branch) deploys through federation, no key ──
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == \"${var.data_repository}\" && assertion.ref == \"refs/heads/main\""
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deployer" {
  account_id   = "finance-agent-deployer"
  display_name = "Deploys the month-end agents to Agent Runtime"
  description  = "Used by the data repo main branch through Workload Identity Federation."
}

resource "google_service_account_iam_member" "github_is_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.data_repository}"
}

resource "google_project_iam_member" "deployer" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_storage_bucket_iam_member" "deployer_staging" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_service_account_iam_member" "deployer_acts_as_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
