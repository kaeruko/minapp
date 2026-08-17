locals {
  phase4_protected_routes = toset([
    "GET /lifecycle/apps",
    "POST /apps/{app_id}/versions",
    "DELETE /apps/{app_id}",
    "POST /apps/{app_id}/versions/{version_id}/approve",
  ])
}

resource "aws_lambda_function" "lifecycle_api" {
  function_name = "${local.name_prefix}-lifecycle-api"
  role          = aws_iam_role.api.arn
  handler       = "phase4_lifecycle_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      DATA_TABLE_NAME     = aws_dynamodb_table.main.name
      UPLOAD_BUCKET       = aws_s3_bucket.uploads.bucket
      PUBLISHED_BUCKET    = aws_s3_bucket.published.bucket
      USER_POOL_ID        = aws_cognito_user_pool.main.id
      USER_POOL_CLIENT_ID = aws_cognito_user_pool_client.app.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_basic_execution,
    aws_iam_role_policy.api_application,
    aws_iam_role_policy.api_phase2,
  ]
}

resource "aws_cloudwatch_log_group" "lifecycle_api" {
  name              = "/aws/lambda/${aws_lambda_function.lifecycle_api.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "lifecycle_api" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lifecycle_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "phase4_protected" {
  for_each = local.phase4_protected_routes

  api_id = aws_apigatewayv2_api.api.id

  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.lifecycle_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "lifecycle_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lifecycle_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
