resource "aws_apigatewayv2_route" "hosted_group_settings" {
  api_id = aws_apigatewayv2_api.api.id

  route_key          = "PATCH /hosted/groups/{group_id}"
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "hosted_group_icon" {
  for_each = toset([
    "GET /hosted/groups/{group_id}/icon",
    "POST /hosted/groups/{group_id}/icon",
    "DELETE /hosted/groups/{group_id}/icon",
  ])

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.hosted_identity_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
