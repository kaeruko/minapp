variable "aws_region" {
  description = "AWS region for the hosted MinApp environment."
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

variable "hosted_tenant_id" {
  description = "Immutable MinApp tenant identity for the shared hosted environment. Use a 32-character lowercase hexadecimal ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.hosted_tenant_id))
    error_message = "hosted_tenant_id must be exactly 32 lowercase hexadecimal characters."
  }
}

variable "expected_account_id" {
  description = "AWS account ID that is allowed to own the hosted MinApp environment. Terraform fails before resource creation when credentials point elsewhere."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}

variable "allow_self_signup" {
  description = "Allow Cognito self-sign-up. Keep false until the MinApp hosted registration API and abuse controls are implemented."
  type        = bool
  default     = false
}

variable "local_development_cors_origins" {
  description = "Optional localhost origins for direct-browser development. Must remain empty in prod."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(distinct(var.local_development_cors_origins)) == length(var.local_development_cors_origins) &&
      alltrue([
        for origin in var.local_development_cors_origins :
        can(regex("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]{1,5})?$", origin))
      ]) &&
      (var.environment != "prod" || length(var.local_development_cors_origins) == 0)
    )
    error_message = "local_development_cors_origins must contain unique localhost origins and must be empty in prod."
  }
}
