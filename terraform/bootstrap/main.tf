variable "region" {
  description = "AWS region for the state bucket and lock table. Must match the region the rest of the stack is deployed to."
  type        = string
  default     = "ap-south-1"
}

# Random suffix keeps the S3 bucket name globally unique without hardcoding an
# account-specific string. Generated once and pinned in state; never changes on
# re-apply.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "telos-tfstate-${random_id.suffix.hex}"
  table_name  = "telos-tf-locks"

  tags = {
    Project   = "telos"
    ManagedBy = "terraform"
    Component = "tf-backend-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# S3 bucket: Terraform remote state
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
  tags   = local.tags

  # This bucket holds the state for the entire platform. Guard against a
  # careless `terraform destroy` wiping it out.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning: keep a history of every state write so a corrupted or bad apply
# can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Default encryption at rest (SSE-S3 / AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access — state can contain secrets and must never be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table: Terraform state locking
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  tags         = local.tags

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}
