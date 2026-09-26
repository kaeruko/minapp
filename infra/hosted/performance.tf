variable "hosted_identity_package_path" {
  description = "Optional reviewed ZIP for a scoped deployment based on the currently live code. Normally built from backend/src."
  type        = string
  default     = null
}

variable "hosted_provisioned_concurrency" {
  description = "Pre-initialized Hosted API environments. Keep 0 normally; raise temporarily for demos when the regional concurrency quota supports it."
  type        = number
  default     = 0

  validation {
    condition = (
      var.hosted_provisioned_concurrency >= 0 &&
      var.hosted_provisioned_concurrency <= 10 &&
      floor(var.hosted_provisioned_concurrency) == var.hosted_provisioned_concurrency
    )
    error_message = "hosted_provisioned_concurrency must be an integer from 0 through 10."
  }
}

variable "hosted_identity_memory_size" {
  description = "Memory in MiB for the Hosted identity/platform Lambda."
  type        = number
  default     = 1024

  validation {
    condition = (
      var.hosted_identity_memory_size >= 128 &&
      var.hosted_identity_memory_size <= 10240 &&
      floor(var.hosted_identity_memory_size) == var.hosted_identity_memory_size
    )
    error_message = "hosted_identity_memory_size must be an integer from 128 through 10240 MiB."
  }
}

variable "auth_api_provisioned_concurrency" {
  description = "Pre-initialized legacy auth API environments used by login/refresh. Keep 0 normally and raise temporarily for demos."
  type        = number
  default     = 0

  validation {
    condition = (
      var.auth_api_provisioned_concurrency >= 0 &&
      var.auth_api_provisioned_concurrency <= 5 &&
      floor(var.auth_api_provisioned_concurrency) == var.auth_api_provisioned_concurrency
    )
    error_message = "auth_api_provisioned_concurrency must be an integer from 0 through 5."
  }
}

variable "auth_api_memory_size" {
  description = "Memory in MiB for the legacy API Lambda that serves login and refresh."
  type        = number
  default     = 128

  validation {
    condition = (
      var.auth_api_memory_size >= 128 &&
      var.auth_api_memory_size <= 10240 &&
      floor(var.auth_api_memory_size) == var.auth_api_memory_size
    )
    error_message = "auth_api_memory_size must be an integer from 128 through 10240 MiB."
  }
}

resource "aws_lambda_alias" "hosted_identity_live" {
  name             = "live"
  description      = "Published Hosted API used by API Gateway"
  function_name    = aws_lambda_function.hosted_identity_api.function_name
  function_version = aws_lambda_function.hosted_identity_api.version
}

resource "aws_lambda_provisioned_concurrency_config" "hosted_identity" {
  count = var.hosted_provisioned_concurrency == 0 ? 0 : 1

  function_name                     = aws_lambda_function.hosted_identity_api.function_name
  qualifier                         = aws_lambda_alias.hosted_identity_live.name
  provisioned_concurrent_executions = var.hosted_provisioned_concurrency
}

resource "aws_lambda_permission" "hosted_identity_live_gateway" {
  statement_id  = "AllowExecutionFromHostedApiGatewayLive"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hosted_identity_api.function_name
  qualifier     = aws_lambda_alias.hosted_identity_live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_alias" "auth_api_live" {
  name             = "live-auth"
  description      = "Published auth API used by login and refresh routes"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
}

resource "aws_lambda_provisioned_concurrency_config" "auth_api" {
  count = var.auth_api_provisioned_concurrency == 0 ? 0 : 1

  function_name                     = aws_lambda_function.api.function_name
  qualifier                         = aws_lambda_alias.auth_api_live.name
  provisioned_concurrent_executions = var.auth_api_provisioned_concurrency
}

resource "aws_lambda_permission" "auth_api_live_gateway" {
  statement_id  = "AllowExecutionFromAuthApiGatewayLive"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  qualifier     = aws_lambda_alias.auth_api_live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "auth_api_live" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.auth_api_live.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"

  depends_on = [
    aws_lambda_provisioned_concurrency_config.auth_api,
    aws_lambda_permission.auth_api_live_gateway,
  ]
}
