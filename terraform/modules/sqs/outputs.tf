output "queue_url" {
  description = "URL of the main SQS queue (for task-service / notification-service env vars)."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the main SQS queue (for IAM policies)."
  value       = aws_sqs_queue.this.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue (for IAM policies)."
  value       = aws_sqs_queue.dlq.arn
}
