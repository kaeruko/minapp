# Refresh tokens are exchanged by the existing public API Lambda. The refresh
# token itself is the credential, so this route must not require the JWT
# authorizer whose access token may already be expired.
resource "aws_apigatewayv2_route" "auth_refresh" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /auth/refresh"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}
