resource "aws_iam_role" "tenant_info" {
  name = "${local.name_prefix}-tenant-info"

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
      TENANT_ID            = var.tenant_id
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
  api_id = aws_apigatewayv2_api.api.id

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
