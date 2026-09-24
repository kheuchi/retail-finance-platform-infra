terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  # Same state bucket as bootstrap/, different key. Supplied at init time, as for
  # bootstrap, so no account identifier is committed.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.134"
    }
    # Used for one thing: waiting out IAM eventual consistency before Databricks
    # tries to assume a role that was created seconds earlier.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
