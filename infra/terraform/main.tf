locals {
  project_name         = "minapp"
  name_prefix          = "${local.project_name}-${var.environment}"
  api_protocol_version = 1

  protected_routes = toset([
    "GET /me",
    "GET /groups",
    "POST /groups",
    "GET /groups/{group_id}/members",
    "POST /groups/{group_id}/students",
    "POST /users/{user_id}/reset-password",
    "DELETE /groups/{group_id}/members/{user_id}",
  ])
}

data "aws_caller_identity" "current" {}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = abspath("${path.module}/../../backend/src")
  output_path = "${path.module}/minapp-api.zip"
  excludes    = ["__pycache__"]
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = var.environment
      TenantId    = var.tenant_id
      ManagedBy   = "terraform"
    }
  }
}

resource "terraform_data" "tenant_identity" {
  input            = var.tenant_id
  triggers_replace = [var.tenant_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-users"

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 6
    require_lowercase                = false
    require_numbers                  = false
    require_symbols                  = false
    require_uppercase                = false
    temporary_password_validity_days = 7
  }

  deletion_protection = var.environment == "prod" ? "ACTIVE" : "INACTIVE"
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.name_prefix}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_dynamodb_table" "main" {
  name         = "${local.name_prefix}-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-uploads"

  force_destroy = false
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "published" {
  bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-published"

  force_destroy = false
}

resource "aws_s3_bucket_versioning" "published" {
  bucket = aws_s3_bucket.published.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "published" {
  bucket = aws_s3_bucket.published.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "published" {
  bucket = aws_s3_bucket.published.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "api" {
  name = "${local.name_prefix}-api"

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

resource "aws_iam_role_policy_attachment" "api_basic_execution" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_application" {
  name = "${local.name_prefix}-api-application"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinAppData"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:TransactWriteItems",
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Sid    = "MinAppUserAdministration"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminSetUserPassword",
        ]
        Resource = aws_cognito_user_pool.main.arn
      },
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.api.arn
  handler       = "handler.lambda_handler"
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
    terraform_data.tenant_identity,
  ]
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id = aws_apigatewayv2_api.api.id

  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-cognito"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

resource "aws_apigatewayv2_route" "health" {
  api_id = aws_apigatewayv2_api.api.id

  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "auth_login" {
  api_id = aws_apigatewayv2_api.api.id

  route_key = "POST /auth/login"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "auth_change_password" {
  api_id = aws_apigatewayv2_api.api.id

  route_key = "POST /auth/change-password"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "protected" {
  for_each = local.protected_routes

  api_id = aws_apigatewayv2_api.api.id

  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.api.id

  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 25
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
