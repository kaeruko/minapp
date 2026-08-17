output "tenant_id" {
  description = "Immutable MinApp tenant identity for this deployment."
  value       = var.tenant_id
}

output "api_protocol_version" {
  description = "Protocol version exposed by the tenant API."
  value       = local.api_protocol_version
}

output "api_base_url" {
  description = "Base URL of the tenant HTTP API."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for Phase 1 integration."
  value       = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "Public Cognito app client ID."
  value       = aws_cognito_user_pool_client.app.id
}

output "data_table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.main.name
}

output "upload_bucket_name" {
  description = "Private upload bucket name."
  value       = aws_s3_bucket.uploads.bucket
}

output "published_bucket_name" {
  description = "Private published-content bucket name."
  value       = aws_s3_bucket.published.bucket
}
