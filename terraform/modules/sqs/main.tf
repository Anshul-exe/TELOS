# ---------------------------------------------------------------------------
# SQS module — telos-task-events queue bridging task-service (publisher) and
# notification-service (consumer). A dead-letter queue (DLQ) catches poison
# messages after maxReceiveCount delivery attempts.
# ---------------------------------------------------------------------------

locals {
  base_tags = merge(var.tags, {
    Module = "sqs"
  })

  queue_name = "${var.queue_name_prefix}-task-events"
  dlq_name   = "${var.queue_name_prefix}-task-events-dlq"
}

# ── Dead-letter queue ──────────────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = var.message_retention_seconds

  tags = merge(local.base_tags, { Name = local.dlq_name })
}

# ── Main queue ─────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "this" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.base_tags, { Name = local.queue_name })
}

# ── DLQ redrive-allow policy ──────────────────────────────────────────────
# Lets the main queue send rejected messages to the DLQ.

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}
