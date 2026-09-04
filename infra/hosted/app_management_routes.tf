locals {
  hosted_app_management_routes = toset([
    "GET /hosted/my/apps",
    "GET /hosted/my/apps/{app_id}",
    "POST /hosted/my/apps/{app_id}/visibility",
  ])
}

resource "aws_apigatewayv2_route" "hosted_app_management" {
  for_each = local.hosted_app_management_routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
