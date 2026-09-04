# =====================================================================
# ECR — container image registry
# =====================================================================

resource "aws_ecr_repository" "app" {
  name = "${var.name_prefix}-balance-service"

  # Tags cannot be overwritten. Combined with tagging images by commit
  # SHA in the pipeline, a running task can always be traced back to
  # exactly one commit.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Exercise environment: allows terraform destroy to remove the
  # repository without emptying it by hand first.
  force_delete = true

  tags = { Name = "${var.name_prefix}-balance-service" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
