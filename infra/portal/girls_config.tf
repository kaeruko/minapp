locals {
  hosted_api_origin = trimspace(var.hosted_api_base_url)
  girls_config = {
    schema_version      = 1
    hosted_api_base_url = local.hosted_api_origin
  }
  girls_config_json = jsonencode(local.girls_config)
}

resource "terraform_data" "girls_hosted_origin_guard" {
  input = local.hosted_api_origin

  lifecycle {
    precondition {
      condition     = contains(local.tenant_api_origins, local.hosted_api_origin)
      error_message = "hosted_api_base_url must also be present in tenant_api_origins so the portal CSP permits Girls API requests."
    }
  }
}

resource "aws_s3_object" "girls_config" {
  bucket = aws_s3_bucket.portal.id
  key    = "girls-config.json"

  content       = local.girls_config_json
  content_type  = "application/json; charset=utf-8"
  cache_control = "no-store, max-age=0"
  etag          = md5(local.girls_config_json)

  depends_on = [
    aws_s3_bucket_ownership_controls.portal,
    terraform_data.girls_hosted_origin_guard,
  ]
}
