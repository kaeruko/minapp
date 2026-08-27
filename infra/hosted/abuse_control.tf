resource "aws_dynamodb_table" "abuse_control" {
  name         = "${aws_dynamodb_table.main.name}-abuse"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at_epoch"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "prod"

  depends_on = [terraform_data.account_guard]
}

resource "aws_iam_role_policy" "abuse_control" {
  name = "${local.name_prefix}-abuse-control"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinAppAbuseRateLimits"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.abuse_control.arn
      },
    ]
  })
}

output "abuse_control_table_name" {
  description = "DynamoDB table containing short-lived hashed abuse-control counters."
  value       = aws_dynamodb_table.abuse_control.name
}
