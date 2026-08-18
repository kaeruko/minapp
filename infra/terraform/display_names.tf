locals {
  display_name_protected_routes = toset([
    "GET /me/display-name",
    "PATCH /me/display-name",
    "GET /groups/{group_id}/display-names",
    "PATCH /users/{user_id}/display-name",
  ])
}

resource "aws_lambda_function" "display_name_api" {
  function_name = "${local.name_prefix}-display-name-api"
  role          = aws_iam_role.api.arn
  handler       = "display_name_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      TENANT_ID            = var.tenant_id
      API_PROTOCOL_VERSION = tostring(local.api_protocol_version)
      DATA_TABLE_NAME      = aws_dynamodb_table.main.name
      UPLOAD_BUCKET        = aws_s3_bucket.uploads.bucket
      PUBLISHED_BUCKET     = aws_s3_bucket.published.bucket
      USER_POOL_ID         = aws_cognito_user_pool.main.id
      USER_POOL_CLIENT_ID  = aws_cognito_user_pool_client.app.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_basic_execution,
    aws_iam_role_policy.api_application,
    aws_iam_role_policy.api_phase2,
    terraform_data.tenant_identity,
  ]
}

resource "aws_cloudwatch_log_group" "display_name_api" {
  name              = "/aws/lambda/${aws_lambda_function.display_name_api.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "display_name_api" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.display_name_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "display_name_protected" {
  for_each = local.display_name_protected_routes

  api_id = aws_apigatewayv2_api.api.id

  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.display_name_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "display_name_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.display_name_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
