locals {
  hosted_public_routes = toset([
    "GET /hosted/health",
    "GET /hosted/builtins",
    "POST /hosted/register",
    "POST /hosted/recover",
    "GET /hosted/runtime/{token}/state/{key}",
    "POST /hosted/runtime/{token}/state/{key}",
    "DELETE /hosted/runtime/{token}/state/{key}",
  ])

  hosted_protected_routes = toset([
    "GET /hosted/me",
    "POST /hosted/recovery-code",
    "DELETE /hosted/account",
    "GET /hosted/groups",
    "POST /hosted/groups",
    "POST /hosted/groups/join",
    "GET /hosted/groups/{group_id}/members",
    "POST /hosted/groups/{group_id}/invite",
    "DELETE /hosted/groups/{group_id}/invite",
    "POST /hosted/groups/{group_id}/owner",
    "DELETE /hosted/groups/{group_id}",
    "DELETE /hosted/groups/{group_id}/membership",
    "DELETE /hosted/groups/{group_id}/members/{user_id}",
    "GET /hosted/groups/{group_id}/apps",
    "POST /hosted/groups/{group_id}/apps/install",
    "POST /hosted/groups/{group_id}/apps/{app_id}/fork",
    "DELETE /hosted/groups/{group_id}/apps/{app_id}",
    "POST /hosted/groups/{group_id}/apps/{app_id}/runtime-session",
  ])
}

resource "aws_lambda_function" "hosted_identity_api" {
  function_name = "${local.name_prefix}-identity-api"
  role          = aws_iam_role.api.arn
  handler       = "hosted_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      TENANT_ID           = var.hosted_tenant_id
      DATA_TABLE_NAME     = aws_dynamodb_table.main.name
      RUNTIME_TABLE_NAME  = aws_dynamodb_table.runtime.name
      USER_POOL_ID        = aws_cognito_user_pool.main.id
      USER_POOL_CLIENT_ID = aws_cognito_user_pool_client.app.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_basic_execution,
    aws_iam_role_policy.api_application,
    terraform_data.account_guard,
    terraform_data.tenant_identity,
  ]
}

resource "aws_cloudwatch_log_group" "hosted_identity_api" {
  name              = "/aws/lambda/${aws_lambda_function.hosted_identity_api.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "hosted_identity_api" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.hosted_identity_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "hosted_public" {
  for_each = local.hosted_public_routes

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
}

resource "aws_apigatewayv2_route" "hosted_protected" {
  for_each = local.hosted_protected_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "hosted_identity_api_gateway" {
  statement_id  = "AllowExecutionFromHostedApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hosted_identity_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
