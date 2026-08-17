locals {
  phase3_protected_routes = toset([
    "GET /mobile/apps",
    "POST /mobile/apps/{app_id}/versions/{version_id}/launch",
  ])
}

resource "aws_iam_role" "mobile_api" {
  name = "${local.name_prefix}-mobile-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mobile_api_basic_execution" {
  role       = aws_iam_role.mobile_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mobile_api_application" {
  name = "${local.name_prefix}-mobile-api-application"
  role = aws_iam_role.mobile_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinAppMobileData"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:TransactWriteItems",
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Sid    = "MinAppPublishedRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.published.arn}/*"
      },
    ]
  })
}

resource "aws_lambda_function" "mobile_api" {
  function_name = "${local.name_prefix}-mobile-api"
  role          = aws_iam_role.mobile_api.arn
  handler       = "phase4_mobile_handler.lambda_handler"
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
    aws_iam_role_policy_attachment.mobile_api_basic_execution,
    aws_iam_role_policy.mobile_api_application,
  ]
}

resource "aws_cloudwatch_log_group" "mobile_api" {
  name              = "/aws/lambda/${aws_lambda_function.mobile_api.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "mobile_api" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.mobile_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "phase3_protected" {
  for_each = local.phase3_protected_routes

  api_id = aws_apigatewayv2_api.api.id

  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.mobile_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "launch_content" {
  api_id = aws_apigatewayv2_api.api.id

  route_key = "GET /launch/{token}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.mobile_api.id}"
}

resource "aws_lambda_permission" "mobile_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mobile_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
