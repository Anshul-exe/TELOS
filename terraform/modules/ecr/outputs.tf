output "repository_urls" {
  description = "Map of repository name -> repository URL (for docker build/push and manifests)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name -> repository ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_names" {
  description = "List of created repository names."
  value       = [for repo in aws_ecr_repository.this : repo.name]
}
