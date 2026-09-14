provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application        = var.project_name
      Environment        = "shared"
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = "finance-data-platform"
      DataClassification = "internal"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
