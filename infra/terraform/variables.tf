variable "aws_region" {
  description = "AWS region for the environment."
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric/hyphen characters and start with a letter."
  }
}

variable "tenant_id" {
  description = "Immutable MinApp tenant identity. Use a server-issued 32-character lowercase hexadecimal ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.tenant_id))
    error_message = "tenant_id must be exactly 32 lowercase hexadecimal characters."
  }
}
