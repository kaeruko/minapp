# Extend the Hosted/Girls sign-in lifetime while keeping short-lived bearer tokens.
# Terraform override blocks merge into the base app client in main.tf.
resource "aws_cognito_user_pool_client" "app" {
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 3650

  token_validity_units {
    access_token  = "days"
    id_token      = "days"
    refresh_token = "days"
  }
}

# Refresh tokens are exchanged by the existing public API Lambda. The refresh
# token itself is the credential, so this route must not require the JWT
# authorizer whose access token may already be expired.
resource "aws_apigatewayv2_route" "auth_refresh" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /auth/refresh"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}
