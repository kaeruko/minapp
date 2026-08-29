locals {
  project_name         = "minapp-portal"
  name_prefix          = "${local.project_name}-${var.environment}"
  portal_domain        = trimspace(var.portal_domain)
  legacy_portal_domain = trimspace(var.legacy_portal_domain)
  directory_api_origin = trimspace(var.directory_api_base_url)
  tenant_api_origins   = sort([for origin in var.tenant_api_origins : trimspace(origin)])
  s3_origin_id         = "portal-s3"

  portal_config = {
    schema_version         = 1
    directory_api_base_url = local.directory_api_origin
  }
  portal_config_json = jsonencode(local.portal_config)

  csp_connect_sources = join(" ", concat(["'self'", local.directory_api_origin], local.tenant_api_origins))
  csp_frame_sources   = join(" ", local.tenant_api_origins)
  content_security_policy = join("; ", [
    "default-src 'none'",
    "base-uri 'none'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "connect-src ${local.csp_connect_sources}",
    "frame-src ${local.csp_frame_sources}",
  ])
}

data "aws_caller_identity" "current" {}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

resource "terraform_data" "operator_account_guard" {
  input = var.operator_account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.operator_account_id
      error_message = "AWS account mismatch: the Web portal must be deployed only to operator_account_id."
    }
  }
}

resource "aws_s3_bucket" "portal" {
  bucket        = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = false

  depends_on = [terraform_data.operator_account_guard]
}

resource "aws_s3_bucket_ownership_controls" "portal" {
  bucket = aws_s3_bucket.portal.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "portal" {
  bucket = aws_s3_bucket.portal.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "portal" {
  bucket = aws_s3_bucket.portal.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "portal" {
  bucket = aws_s3_bucket.portal.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "portal" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for the private MinApp Web portal bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_response_headers_policy" "portal_security" {
  name = "${local.name_prefix}-security"

  security_headers_config {
    content_security_policy {
      content_security_policy = local.content_security_policy
      override                = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }
}

resource "aws_acm_certificate" "portal" {
  count    = var.certificate_arn == null ? 1 : 0
  provider = aws.us_east_1

  # Keep the existing portal.cloxs.jp certificate in state during the
  # cross-account minapp.cloxs.jp alias migration. Removing it is a separate,
  # explicitly reviewed cleanup after legacy clients no longer need it.
  domain_name       = local.legacy_portal_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [terraform_data.operator_account_guard]
}

resource "aws_acm_certificate" "portal_canonical" {
  count    = var.certificate_arn == null ? 1 : 0
  provider = aws.us_east_1

  domain_name               = local.portal_domain
  subject_alternative_names = [local.legacy_portal_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [terraform_data.operator_account_guard]
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.certificate_arn == null ? {
    for option in aws_acm_certificate.portal[0].domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "portal" {
  count    = var.certificate_arn == null ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.portal[0].arn
  validation_record_fqdns = [aws_route53_record.certificate_validation[local.legacy_portal_domain].fqdn]
}

resource "aws_route53_record" "canonical_certificate_validation" {
  for_each = var.certificate_arn == null ? {
    for option in aws_acm_certificate.portal_canonical[0].domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    } if option.domain_name == local.portal_domain
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "portal_canonical" {
  count    = var.certificate_arn == null ? 1 : 0
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.portal_canonical[0].arn
  validation_record_fqdns = concat(
    [aws_route53_record.certificate_validation[local.legacy_portal_domain].fqdn],
    [for record in aws_route53_record.canonical_certificate_validation : record.fqdn],
  )
}

locals {
  portal_certificate_arn = var.certificate_arn != null ? trimspace(var.certificate_arn) : aws_acm_certificate_validation.portal_canonical[0].certificate_arn
}

resource "aws_cloudfront_distribution" "portal" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "MinApp operator Web portal"
  default_root_object = "index.html"
  aliases = var.activate_canonical_domain ? sort(distinct([
    local.portal_domain,
    local.legacy_portal_domain,
  ])) : [local.legacy_portal_domain]
  http_version = "http2and3"

  origin {
    domain_name              = aws_s3_bucket.portal.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.portal.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.portal_security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.portal_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [terraform_data.operator_account_guard]
}

data "aws_iam_policy_document" "portal_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.portal.arn,
      "${aws_s3_bucket.portal.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.portal.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.portal.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "portal" {
  bucket = aws_s3_bucket.portal.id
  policy = data.aws_iam_policy_document.portal_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.portal]
}

resource "aws_s3_object" "portal_config" {
  bucket = aws_s3_bucket.portal.id
  key    = "portal-config.json"

  content       = local.portal_config_json
  content_type  = "application/json; charset=utf-8"
  cache_control = "no-store, max-age=0"
  etag          = md5(local.portal_config_json)

  depends_on = [aws_s3_bucket_ownership_controls.portal]
}

resource "aws_route53_record" "portal_ipv4" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id = var.route53_zone_id
  name    = local.legacy_portal_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.portal.domain_name
    zone_id                = aws_cloudfront_distribution.portal.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "portal_ipv6" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id = var.route53_zone_id
  name    = local.legacy_portal_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.portal.domain_name
    zone_id                = aws_cloudfront_distribution.portal.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudFront requires this ownership proof before an alternate domain name can
# be moved from a different AWS account. It is intentionally created during the
# preparation phase, before the canonical A/AAAA records are activated.
resource "aws_route53_record" "portal_canonical_ownership" {
  count = var.route53_zone_id == null || local.portal_domain == local.legacy_portal_domain ? 0 : 1

  zone_id = var.route53_zone_id
  name    = "_${local.portal_domain}"
  type    = "TXT"
  ttl     = 300
  records = [aws_cloudfront_distribution.portal.domain_name]
}

resource "aws_route53_record" "portal_canonical_ipv4" {
  count = var.route53_zone_id == null || !var.activate_canonical_domain ? 0 : 1

  zone_id = var.route53_zone_id
  name    = local.portal_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.portal.domain_name
    zone_id                = aws_cloudfront_distribution.portal.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "portal_canonical_ipv6" {
  count = var.route53_zone_id == null || !var.activate_canonical_domain ? 0 : 1

  zone_id = var.route53_zone_id
  name    = local.portal_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.portal.domain_name
    zone_id                = aws_cloudfront_distribution.portal.hosted_zone_id
    evaluate_target_health = false
  }
}
