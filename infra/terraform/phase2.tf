locals {
  phase2_protected_routes = toset([
    "GET /apps",
    "POST /groups/{group_id}/apps",
    "GET /groups/{group_id}/review-queue",
    "POST /apps/{app_id}/versions/{version_id}/submit",
    "POST /apps/{app_id}/versions/{version_id}/preview",
  ])
}

resource "aws_iam_role_policy" "api_phase2" {
  name = "${local.name_prefix}-api-phase2"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinAppPhase2DataUpdates"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.main.arn
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
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.published.arn}/*"
      },
    ]
  })
}

resource "aws_apigatewayv2_route" "phase2_protected" {
  for_each = local.phase2_protected_routes

  api_id = aws_apigatewayv2_api.api.id

  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Preview content intentionally has no JWT authorizer. Access is instead guarded by
# a high-entropy, 15-minute opaque token stored server-side. The response carries a
# restrictive CSP and the Web portal embeds it in a sandboxed iframe.
resource "aws_apigatewayv2_route" "preview_content" {
  api_id = aws_apigatewayv2_api.api.id

  route_key = "GET /content/{token}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}
