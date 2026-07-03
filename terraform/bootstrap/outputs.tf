output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state. Wire this into envs/dev/backend.tf as `bucket`."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking. Wire this into envs/dev/backend.tf as `dynamodb_table`."
  value       = aws_dynamodb_table.locks.name
}

output "region" {
  description = "Region the backend resources live in. Wire this into envs/dev/backend.tf as `region`."
  value       = var.region
}
