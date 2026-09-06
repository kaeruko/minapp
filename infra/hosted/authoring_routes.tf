locals {
  hosted_authoring_routes = toset([
    "POST /hosted/authoring/projects",
    "GET /hosted/authoring/projects/{content_id}",
    "POST /hosted/authoring/projects/{content_id}/document",
    "GET /hosted/authoring/projects/{content_id}/assets/{proxy+}",
    "POST /hosted/authoring/projects/{content_id}/assets/{proxy+}",
    "DELETE /hosted/authoring/projects/{content_id}/assets/{proxy+}",
  ])
}

resource "aws_apigatewayv2_route" "hosted_authoring" {
  for_each = local.hosted_authoring_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
