locals {
  hosted_builtin_sources = {
    shiba-game = {
      version    = 1
      source_dir = abspath("${path.module}/../../apps/mobile/assets/builtin/shiba_donguri")
    }
    shiba-goshujin = {
      version    = 1
      source_dir = abspath("${path.module}/../../apps/mobile/assets/builtin/shiba_goshujin")
    }
    novel-starter = {
      version    = 3
      source_dir = abspath("${path.module}/../../apps/mobile/assets/builtin/novel_starter")
    }
  }
}

# The mobile built-ins remain the source of truth. Terraform makes the same
# files available to Hosted BtoC as immutable, versioned fork templates.
data "archive_file" "hosted_builtin_source" {
  for_each = local.hosted_builtin_sources

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/minapp-hosted-builtin-${each.key}-v${each.value.version}.zip"
}

resource "aws_s3_object" "hosted_builtin_source" {
  for_each = local.hosted_builtin_sources

  bucket       = aws_s3_bucket.uploads.id
  key          = "hosted/templates/${each.key}/v${each.value.version}/source.zip"
  source       = data.archive_file.hosted_builtin_source[each.key].output_path
  source_hash  = data.archive_file.hosted_builtin_source[each.key].output_base64sha256
  content_type = "application/zip"

  metadata = {
    sha256 = filesha256(data.archive_file.hosted_builtin_source[each.key].output_path)
  }

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.uploads,
    aws_s3_bucket_public_access_block.uploads,
    terraform_data.account_guard,
  ]
}
