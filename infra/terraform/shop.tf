resource "aws_iam_role_policy" "mobile_shop_mutations" {
  name = "${local.name_prefix}-mobile-shop-mutations"
  role = aws_iam_role.mobile_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinAppShopMetadataMutations"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.main.arn
      },
    ]
  })
}
