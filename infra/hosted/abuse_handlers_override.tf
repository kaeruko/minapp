# Terraform override blocks intentionally change only the Lambda entry points.
# The base resources remain defined in main.tf / identity_groups.tf.
resource "aws_lambda_function" "api" {
  handler = "abuse_entry.api_lambda_handler"
}

resource "aws_lambda_function" "hosted_identity_api" {
  handler = "abuse_entry.hosted_lambda_handler"
}
