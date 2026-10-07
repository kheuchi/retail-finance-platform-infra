terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  # State lives with the rest of the platform, in the AWS state bucket, under agent/: the
  # agent deploy role may already read and write that prefix.
  backend "s3" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.20, < 8.0"
    }
  }
}
