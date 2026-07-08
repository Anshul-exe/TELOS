variable "repository_names" {
  description = "ECR repositories to create. Defaults match baseArch.md."
  type        = list(string)
  default = [
    "telos-frontend",
    "telos-backend", # [FLAG] unused (replaced by 3 microservices), pending removal
    "telos-task-service",
    "telos-auth-service",
    "telos-notification-service",
  ]
}

variable "scan_on_push" {
  description = "Enable image scanning on push (security hardening)."
  type        = bool
  default     = true
}

variable "keep_last_tagged" {
  description = "Number of most-recent tagged images to retain."
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Expire untagged images this many days after push."
  type        = number
  default     = 3
}

variable "image_tag_mutability" {
  description = "Tag mutability for the repositories (MUTABLE or IMMUTABLE)."
  type        = string
  default     = "MUTABLE"
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
