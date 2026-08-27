output "hosted_tenant_id" {
  description = "Immutable tenant ID for the shared hosted MinApp environment."
  value       = var.hosted_tenant_id
}

output "api_base_url" {
  description = "Base URL of the hosted MinApp HTTP API."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "api_protocol_version" {
  description = "MinApp tenant API protocol version."
  value       = local.api_protocol_version
}

output "user_pool_id" {
  description = "Cognito User Pool ID used by hosted MinApp accounts."
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito app client ID used by hosted MinApp clients."
  value       = aws_cognito_user_pool_client.app.id
}

output "main_table_name" {
  description = "DynamoDB table containing MinApp users, groups, memberships, and app metadata."
  value       = aws_dynamodb_table.main.name
}

output "runtime_table_name" {
  description = "DynamoDB table reserved for scoped built-in/user-app runtime data."
  value       = aws_dynamodb_table.runtime.name
}

output "upload_bucket_name" {
  description = "Private bucket for uploaded app packages."
  value       = aws_s3_bucket.uploads.bucket
}

output "published_bucket_name" {
  description = "Private bucket for immutable published app files."
  value       = aws_s3_bucket.published.bucket
}
