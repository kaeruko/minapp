locals {
  hosted_authoring_session_create_routes = toset([
    "POST /hosted/authoring/projects/{content_id}/session",
  ])

  hosted_authoring_capability_routes = toset([
    "GET /hosted/authoring/session/{token}",
    "POST /hosted/authoring/session/{token}/document",
    "GET /hosted/authoring/session/{token}/assets/{proxy+}",
    "POST /hosted/authoring/session/{token}/assets/{proxy+}",
    "DELETE /hosted/authoring/session/{token}/assets/{proxy+}",
  ])
}

resource "aws_apigatewayv2_route" "hosted_authoring_session_create" {
  for_each = local.hosted_authoring_session_create_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "hosted_authoring_capability" {
  for_each = local.hosted_authoring_capability_routes

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
}
