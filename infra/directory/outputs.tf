output "directory_api_base_url" {
  description = "Public base URL for the MinApp Directory API."
  value       = aws_apigatewayv2_api.directory.api_endpoint
}

output "directory_table_name" {
  description = "DynamoDB table used by the operator-only Directory admin CLI."
  value       = aws_dynamodb_table.directory.name
}

output "directory_environment" {
  description = "Directory deployment environment."
  value       = var.environment
}
