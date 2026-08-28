locals {
  hosted_public_routes = toset([
    "GET /hosted/health",
    "GET /hosted/legal",
    "GET /hosted/builtins",
    "POST /hosted/register",
    "POST /hosted/recover",
    "GET /hosted/runtime/{token}/state/{key}",
    "POST /hosted/runtime/{token}/state/{key}",
    "DELETE /hosted/runtime/{token}/state/{key}",
    "GET /hosted/content/{token}/{proxy+}",
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
    "GET /hosted/groups/{group_id}/apps/{app_id}/source",
    "POST /hosted/groups/{group_id}/apps/{app_id}/source",
    "POST /hosted/groups/{group_id}/apps/{app_id}/publish",
    "POST /hosted/groups/{group_id}/apps/{app_id}/published-session",
    "POST /hosted/groups/{group_id}/apps/{app_id}/launch-session",
    "DELETE /hosted/groups/{group_id}/apps/{app_id}",
    "POST /hosted/groups/{group_id}/apps/{app_id}/runtime-session",
  ])
}

resource "aws_iam_role" "hosted_identity_api" {
  name = "${local.name_prefix}-identity-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "hosted_identity_api_basic_execution" {
  role       = aws_iam_role.hosted_identity_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "hosted_identity_api_application" {
  name = "${local.name_prefix}-identity-api-application"
  role = aws_iam_role.hosted_identity_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HostedMetadata"
        Effect = "Allow"
        # DynamoDB authorizes every operation inside TransactWriteItems as its
        # corresponding item action in addition to TransactWriteItems itself.
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:TransactWriteItems",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Sid    = "HostedRuntimeData"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:TransactWriteItems",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.runtime.arn
      },
      {
        Sid    = "HostedUserAdministration"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminSetUserPassword",
        ]
        Resource = aws_cognito_user_pool.main.arn
      },
      {
        Sid      = "HostedBuiltinSourceTemplates"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = [for source in aws_s3_object.hosted_builtin_source : "${aws_s3_bucket.uploads.arn}/${source.key}"]
      },
      {
        Sid    = "HostedDraftSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/hosted/drafts/*"
      },
      {
        Sid    = "HostedPublishedSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = "${aws_s3_bucket.published.arn}/hosted/published/*"
      },
    ]
  })
}

resource "aws_lambda_function" "hosted_identity_api" {
  function_name = "${local.name_prefix}-identity-api"
  role          = aws_iam_role.hosted_identity_api.arn
  handler       = "hosted_entry.lambda_handler"
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
      UPLOAD_BUCKET       = aws_s3_bucket.uploads.bucket
      PUBLISHED_BUCKET    = aws_s3_bucket.published.bucket
      PORTAL_ORIGIN       = local.portal_origin
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.hosted_identity_api_basic_execution,
    aws_iam_role_policy.hosted_identity_api_application,
    aws_iam_role_policy.hosted_identity_api_abuse_control,
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
