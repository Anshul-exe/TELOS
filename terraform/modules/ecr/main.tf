# ---------------------------------------------------------------------------
# ECR module — codifies the two repositories from baseArch.md.
# Scanning on push feeds the security-hardening story (Trivy/manual review).
# Lifecycle policy caps storage cost: keep last N tagged, expire untagged.
# ---------------------------------------------------------------------------

locals {
  base_tags = merge(var.tags, {
    Module = "ecr"
  })
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(local.base_tags, { Name = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.keep_last_tagged} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_tagged
        }
        action = { type = "expire" }
      },
    ]
  })
}
