locals {
  project_name = "minapp-directory"
  name_prefix  = "${local.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

data "archive_file" "directory" {
  type        = "zip"
  source_dir  = abspath("${path.module}/../../directory/src")
  output_path = "${path.module}/minapp-directory.zip"
  excludes    = ["__pycache__"]
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

resource "terraform_data" "operator_account_guard" {
  input = var.operator_account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.operator_account_id
      error_message = "AWS account mismatch: the Directory must be deployed only to operator_account_id."
    }
  }
}

resource "aws_dynamodb_table" "directory" {
  name         = "${local.name_prefix}-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  depends_on = [terraform_data.operator_account_guard]
}

resource "aws_iam_role" "directory_api" {
  name = "${local.name_prefix}-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  depends_on = [terraform_data.operator_account_guard]
}

resource "aws_iam_role_policy_attachment" "directory_api_basic_execution" {
  role       = aws_iam_role.directory_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "directory_api_data" {
  name = "${local.name_prefix}-data"
  role = aws_iam_role.directory_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
      ]
      Resource = aws_dynamodb_table.directory.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "directory_api" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = 30
}

resource "aws_lambda_function" "directory_api" {
  function_name    = "${local.name_prefix}-api"
  role             = aws_iam_role.directory_api.arn
  runtime          = "python3.12"
  handler          = "directory_handler.lambda_handler"
  filename         = data.archive_file.directory.output_path
  source_code_hash = data.archive_file.directory.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      DIRECTORY_TABLE_NAME       = aws_dynamodb_table.directory.name
      DESCRIPTOR_TTL_SECONDS     = tostring(var.descriptor_ttl_seconds)
      RATE_LIMIT_REQUESTS        = tostring(var.rate_limit_requests)
      RATE_LIMIT_WINDOW_SECONDS  = tostring(var.rate_limit_window_seconds)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.directory_api,
    aws_iam_role_policy.directory_api_data,
    aws_iam_role_policy_attachment.directory_api_basic_execution,
  ]
}

resource "aws_apigatewayv2_api" "directory" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "directory_api" {
  api_id                 = aws_apigatewayv2_api.directory.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.directory_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "resolve" {
  api_id    = aws_apigatewayv2_api.directory.id
  route_key = "POST /v1/classrooms/resolve"
  target    = "integrations/${aws_apigatewayv2_integration.directory_api.id}"
}

resource "aws_apigatewayv2_route" "tenant" {
  api_id    = aws_apigatewayv2_api.directory.id
  route_key = "GET /v1/tenants/{tenant_id}"
  target    = "integrations/${aws_apigatewayv2_integration.directory_api.id}"
}

resource "aws_lambda_permission" "directory_api" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.directory_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.directory.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "directory_access" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.directory.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.directory_access.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 500
    throttling_rate_limit  = 250
  }
}
