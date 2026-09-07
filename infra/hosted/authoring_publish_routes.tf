locals {
  hosted_authoring_publish_routes = toset([
    "POST /hosted/authoring/projects/{content_id}/publish",
  ])
}

resource "aws_apigatewayv2_route" "hosted_authoring_publish" {
  for_each = local.hosted_authoring_publish_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
