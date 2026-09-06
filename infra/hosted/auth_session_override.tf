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
