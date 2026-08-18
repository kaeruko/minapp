variable "aws_region" {
  description = "AWS region for the operator-owned Directory service."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "environment" {
  description = "Directory environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric/hyphen characters and start with a letter."
  }
}

variable "operator_account_id" {
  description = "Expected AWS account ID for the operator-owned Directory deployment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.operator_account_id))
    error_message = "operator_account_id must be exactly 12 digits."
  }
}

variable "descriptor_ttl_seconds" {
  description = "How long clients may cache a tenant descriptor before refreshing it."
  type        = number
  default     = 86400

  validation {
    condition = (
      var.descriptor_ttl_seconds >= 60 &&
      var.descriptor_ttl_seconds <= 604800 &&
      floor(var.descriptor_ttl_seconds) == var.descriptor_ttl_seconds
    )
    error_message = "descriptor_ttl_seconds must be an integer between 60 and 604800 seconds."
  }
}

variable "rate_limit_requests" {
  description = "Per-source-IP Directory request limit within one rate-limit window."
  type        = number
  default     = 60

  validation {
    condition = (
      var.rate_limit_requests >= 1 &&
      var.rate_limit_requests <= 10000 &&
      floor(var.rate_limit_requests) == var.rate_limit_requests
    )
    error_message = "rate_limit_requests must be an integer between 1 and 10000."
  }
}

variable "rate_limit_window_seconds" {
  description = "Fixed window size used by the typed application-level rate limiter."
  type        = number
  default     = 60

  validation {
    condition = (
      var.rate_limit_window_seconds >= 1 &&
      var.rate_limit_window_seconds <= 3600 &&
      floor(var.rate_limit_window_seconds) == var.rate_limit_window_seconds
    )
    error_message = "rate_limit_window_seconds must be an integer between 1 and 3600 seconds."
  }
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
    error_message = "local_development_cors_origins must contain unique http://localhost, http://127.0.0.1, or http://[::1] origins and must be empty in prod."
  }
}
