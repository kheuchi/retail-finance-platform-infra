provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    application = "retail-finance-platform"
    component   = "agent"
    managed_by  = "terraform"
  }
}

data "google_project" "this" {}
