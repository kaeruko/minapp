# Runtime-session expiry is enforced synchronously by application logic via
# expires_at_epoch. DynamoDB TTL is only eventual physical cleanup for the
# metadata row, using the later ttl_epoch value written by the backend.
resource "aws_dynamodb_table" "main" {
  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }
}
