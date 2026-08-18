output "portal_url" {
  description = "Canonical production-style Web portal URL."
  value       = "https://${local.portal_domain}"
}

output "portal_bucket_name" {
  description = "Private S3 bucket containing the Web portal assets."
  value       = aws_s3_bucket.portal.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used when invalidating published assets."
  value       = aws_cloudfront_distribution.portal.id
}

output "cloudfront_domain_name" {
  description = "CloudFront target hostname. External DNS providers should point portal_domain here."
  value       = aws_cloudfront_distribution.portal.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted-zone ID for Route 53 aliases."
  value       = aws_cloudfront_distribution.portal.hosted_zone_id
}

output "portal_certificate_arn" {
  description = "ACM certificate used by CloudFront."
  value       = local.portal_certificate_arn
}

output "portal_config_url" {
  description = "Same-origin bootstrap configuration URL."
  value       = "https://${local.portal_domain}/portal-config.json"
}

output "external_dns_required" {
  description = "True when DNS is not managed by this Terraform stack."
  value       = var.route53_zone_id == null
}
