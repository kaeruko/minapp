variable "aws_region" {
  description = "AWS region for the operator-owned portal S3 bucket and Terraform resources."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "environment" {
  description = "Portal environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric/hyphen characters and start with a letter."
  }
}

variable "operator_account_id" {
  description = "Expected AWS account ID for the operator-owned portal deployment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.operator_account_id))
    error_message = "operator_account_id must be exactly 12 digits."
  }
}

variable "portal_domain" {
  description = "Canonical HTTPS hostname for the shared Web portal."
  type        = string
  default     = "minapp.cloxs.jp"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", trimspace(var.portal_domain)))
    error_message = "portal_domain must be a lowercase DNS hostname without scheme, path, query, fragment, or trailing dot."
  }
}

variable "directory_api_base_url" {
  description = "Public HTTPS origin of the central Directory API, also published in portal-config.json."
  type        = string

  validation {
    condition     = can(regex("^https://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$", trimspace(var.directory_api_base_url)))
    error_message = "directory_api_base_url must be a public HTTPS origin with no path, query, fragment, or trailing slash."
  }
}

variable "tenant_api_origins" {
  description = "Explicit active tenant HTTPS origins allowed by the portal CSP for connect-src and frame-src."
  type        = set(string)

  validation {
    condition = (
      length(var.tenant_api_origins) > 0 &&
      alltrue([
        for origin in var.tenant_api_origins :
        can(regex("^https://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$", trimspace(origin)))
      ])
    )
    error_message = "tenant_api_origins must contain at least one public HTTPS origin and may not contain paths, queries, fragments, or trailing slashes."
  }
}

variable "certificate_arn" {
  description = "Optional prevalidated ACM certificate ARN in us-east-1. Required for external DNS; omit only when route53_zone_id is supplied so Terraform can create and validate the certificate."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.certificate_arn == null ||
      can(regex(
        "^arn:aws:acm:us-east-1:${var.operator_account_id}:certificate/[0-9a-fA-F-]+$",
        trimspace(var.certificate_arn)
      ))
    )
    error_message = "certificate_arn must be an ACM certificate ARN from us-east-1 in operator_account_id."
  }

  validation {
    condition     = var.certificate_arn != null || var.route53_zone_id != null
    error_message = "Provide certificate_arn for external DNS, or route53_zone_id so Terraform can create and validate the portal certificate."
  }
}

variable "route53_zone_id" {
  description = "Optional Route 53 hosted-zone ID. When set, Terraform manages the portal A/AAAA aliases; when certificate_arn is omitted it also manages DNS certificate validation."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.route53_zone_id == null || can(regex("^Z[A-Z0-9]+$", trimspace(var.route53_zone_id)))
    error_message = "route53_zone_id must be a Route 53 hosted-zone ID beginning with Z."
  }
}
