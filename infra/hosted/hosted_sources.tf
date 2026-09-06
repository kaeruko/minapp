variable "minapp_apps_source_root" {
  description = "Path to the minapp_apps checkout that owns creative Hosted app sources. Defaults to a sibling checkout for local development."
  type        = string
  default     = null
}

locals {
  minapp_apps_source_root = var.minapp_apps_source_root != null ? abspath(var.minapp_apps_source_root) : abspath("${path.module}/../../../minapp_apps")

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
      version    = 4
      source_dir = "${local.minapp_apps_source_root}/novel_starter"
    }
    novel-editor = {
      version    = 1
      source_dir = "${local.minapp_apps_source_root}/novel_editor"
    }
  }
}

# Core demo apps still come from minapp. Creative Editor/Player sources come
# from the separate minapp_apps checkout so they are not bundled into the Host
# binary and are not duplicated as a second source of truth in this repo.
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
