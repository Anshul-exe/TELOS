variable "queue_name_prefix" {
  description = "Prefix for the SQS queue names (e.g. 'telos')."
  type        = string
  default     = "telos"
}

variable "visibility_timeout_seconds" {
  description = "Time (seconds) a message is invisible after being received."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Time (seconds) SQS retains a message before discarding. Default 4 days."
  type        = number
  default     = 345600
}

variable "max_receive_count" {
  description = "Number of receive attempts before a message is sent to the DLQ."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
