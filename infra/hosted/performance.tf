variable "hosted_identity_package_path" {
  description = "Optional reviewed ZIP for a scoped deployment based on the currently live code. Normally built from backend/src."
  type        = string
  default     = null
}

variable "hosted_provisioned_concurrency" {
  description = "Pre-initialized Hosted API environments. Defaults to 0; set to 2 only when explicitly opting into warm environments and the regional concurrency quota supports it."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 2], var.hosted_provisioned_concurrency)
    error_message = "Use zero by default, or two when explicitly enabling warm Hosted API environments."
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
