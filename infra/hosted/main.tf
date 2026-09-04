locals {
  project_name         = "minapp"
  name_prefix          = "${local.project_name}-hosted-${var.environment}"
  api_protocol_version = 1
  portal_origin        = "https://minapp.cloxs.jp"
  cors_allowed_origins = concat([local.portal_origin], var.local_development_cors_origins)

  protected_routes = toset([
    "GET /me",
    "GET /groups",
    "POST /groups",
    "GET /groups/{group_id}/members",
    "POST /groups/{group_id}/students",
    "POST /users/{user_id}/reset-password",
    "DELETE /groups/{group_id}/members/{user_id}",
    "GET /apps",
    "POST /groups/{group_id}/apps",
    "GET /groups/{group_id}/review-queue",
    "POST /apps/{app_id}/versions/{version_id}/submit",
    "POST /apps/{app_id}/versions/{version_id}/preview",
    "POST /apps/{app_id}/versions/{version_id}/approve",
  ])
}

data "aws_caller_identity" "current" {}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = abspath("${path.module}/../../backend/src")
  output_path = "${path.module}/minapp-hosted-api.zip"
  excludes    = ["__pycache__"]
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = var.environment
      TenantId    = var.hosted_tenant_id
      HostingMode = "shared"
      ManagedBy   = "terraform"
    }
  }
}

resource "terraform_data" "account_guard" {
  input = data.aws_caller_identity.current.account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "AWS account mismatch: hosted MinApp may only be deployed to expected_account_id."
    }
  }
}

resource "terraform_data" "tenant_identity" {
  input            = var.hosted_tenant_id
  triggers_replace = [var.hosted_tenant_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-users"

  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "みんアプ Girls メールアドレス確認コード"
    email_message        = "みんアプ Girls の確認コードは {####} です。アプリの設定画面に入力してください。"
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

  depends_on = [terraform_data.account_guard]
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

  deletion_protection_enabled = var.environment == "prod"

  depends_on = [terraform_data.account_guard]
}

# Runtime data is intentionally separated from MinApp account/group/app metadata.
# Built-in and user-created apps will only reach this table through the future
# scoped Runtime/Data API; app JavaScript never receives AWS credentials.
resource "aws_dynamodb_table" "runtime" {
  name         = "${local.name_prefix}-runtime"
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

  deletion_protection_enabled = var.environment == "prod"

  depends_on = [terraform_data.account_guard]
}

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-uploads"
  force_destroy = false

  depends_on = [terraform_data.account_guard]
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
  bucket        = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-published"
  force_destroy = false

  depends_on = [terraform_data.account_guard]
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
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
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
        Sid    = "MinAppMetadata"
        Effect = "Allow"
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
        Sid    = "MinAppRuntimeData"
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
      {
        Sid    = "MinAppDraftObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Sid    = "MinAppPublishedObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.published.arn}/*"
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
      TENANT_ID            = var.hosted_tenant_id
      API_PROTOCOL_VERSION = tostring(local.api_protocol_version)
      DATA_TABLE_NAME      = aws_dynamodb_table.main.name
      RUNTIME_TABLE_NAME   = aws_dynamodb_table.runtime.name
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

  cors_configuration {
    allow_origins = local.cors_allowed_origins
    allow_methods = ["DELETE", "GET", "OPTIONS", "PATCH", "POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 600
  }
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
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "auth_login" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /auth/login"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "auth_change_password" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /auth/change-password"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "protected" {
  for_each = local.protected_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "preview_content" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /content/{token}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
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

resource "aws_iam_role" "tenant_info" {
  name = "${local.name_prefix}-tenant-info"

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

resource "aws_iam_role_policy_attachment" "tenant_info_basic_execution" {
  role       = aws_iam_role.tenant_info.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "tenant_info" {
  function_name = "${local.name_prefix}-tenant-info"
  role          = aws_iam_role.tenant_info.arn
  handler       = "tenant_info_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  memory_size = 128
  timeout     = 5

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      TENANT_ID            = var.hosted_tenant_id
      API_PROTOCOL_VERSION = tostring(local.api_protocol_version)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.tenant_info_basic_execution,
    terraform_data.tenant_identity,
  ]
}

resource "aws_cloudwatch_log_group" "tenant_info" {
  name              = "/aws/lambda/${aws_lambda_function.tenant_info.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "tenant_info" {
  api_id = aws_apigatewayv2_api.api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.tenant_info.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "tenant_info" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /tenant-info"
  target    = "integrations/${aws_apigatewayv2_integration.tenant_info.id}"
}

resource "aws_lambda_permission" "tenant_info_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tenant_info.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
