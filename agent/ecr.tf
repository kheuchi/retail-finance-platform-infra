resource "aws_ecr_repository" "agent" {
  #checkov:skip=CKV_AWS_136:AES256 (AWS-managed) is sufficient for an image with no secrets; KMS adds cost and key management for no gain here.
  name                 = local.repository
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # teardown: the images are rebuilt from Git

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
