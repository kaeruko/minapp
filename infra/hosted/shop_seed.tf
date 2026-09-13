locals {
  # Girls built-ins are intentionally limited to memo (planned), karaoke,
  # novel and minappchi. Existing sample apps outside that set live in Shop.
  # Stable synthetic identities keep official Shop works on the same canonical
  # app/listing path as user-published works without creating a login-capable
  # Cognito account or attaching the work to a user's group.
  official_shop_owner_user_id = "4fdc521e5f2642e1afe420ec9f5a931e"
  official_shop_group_id      = "218dbe54f5276416a7634ab10ef33bd4"

  official_shop_directory_sources = {
    shiba-game = {
      app_id     = "bc54fcb0fdca499ebcab0c4de81776a3"
      title      = "しば犬どんぐりキャッチ"
      version    = 1
      source_dir = "${local.minapp_apps_source_root}/shiba_donguri"
      files      = ["index.html"]
    }
    shiba-goshujin = {
      app_id     = "478cbf2dbf804d65b433468e632f0a17"
      title      = "ごしゅじんどこわん"
      version    = 1
      source_dir = "${local.minapp_apps_source_root}/shiba_goshujin"
      files      = ["index.html"]
    }
    shopping-town = {
      app_id     = "29f96117bb7148289e07e759226cfd1a"
      title      = "おかいもの いくわよ"
      version    = 1
      source_dir = "${local.minapp_apps_source_root}/shopping_town"
      files      = ["index.html", "rules.js"]
    }
    ol-home = {
      app_id     = "9b3cd1527777483d8177b6792e7783be"
      title      = "OLさん おうちにかえる"
      version    = 1
      source_dir = "${local.minapp_apps_source_root}/ol_home"
      files      = ["effects.js", "index.html"]
    }
  }
}

data "archive_file" "official_shop_directory_source" {
  for_each = local.official_shop_directory_sources

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/minapp-hosted-shop-${each.key}-v${each.value.version}.zip"
}

locals {
  official_shop_apps = merge(
    {
      drawing = {
        app_id       = "ecb3cb6a08e05305668a952cbdae435b"
        title        = "おえかき"
        version      = 1
        source       = "${local.minapp_apps_source_root}/minapp_drawing.zip"
        files        = ["index.html"]
        published_at = "2026-09-13T00:00:00Z"
      }
    },
    {
      for key, app in local.official_shop_directory_sources : key => {
        app_id       = app.app_id
        title        = app.title
        version      = app.version
        source       = data.archive_file.official_shop_directory_source[key].output_path
        files        = app.files
        published_at = "2026-09-13T00:00:00Z"
      }
    }
  )
}

# Official shop works are ordinary immutable published ZIPs. Keeping them under
# hosted/published means launch, download, reporting and Runtime all continue to
# use HostedShopBackend's existing validation instead of a special-case route.
resource "aws_s3_object" "official_shop_app" {
  for_each = local.official_shop_apps

  bucket       = aws_s3_bucket.published.id
  key          = "hosted/published/official-shop/${each.value.app_id}/v${each.value.version}/source.zip"
  source       = each.value.source
  source_hash  = filesha256(each.value.source)
  content_type = "application/zip"

  metadata = {
    sha256 = filesha256(each.value.source)
  }

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.published,
    aws_s3_bucket_public_access_block.published,
    terraform_data.account_guard,
  ]
}

# list_shop_apps resolves every listing owner through USER#{id}/PROFILE. This
# profile is display-only; deliberately no AUTH row or Cognito user is created.
resource "aws_dynamodb_table_item" "official_shop_owner" {
  table_name = aws_dynamodb_table.main.name
  hash_key   = aws_dynamodb_table.main.hash_key
  range_key  = aws_dynamodb_table.main.range_key

  item = jsonencode({
    pk           = { S = "USER#${local.official_shop_owner_user_id}" }
    sk           = { S = "PROFILE" }
    entity       = { S = "user" }
    user_id      = { S = local.official_shop_owner_user_id }
    auth_subject = { S = "official-shop" }
    login_id     = { S = "みんアプ公式" }
    role         = { S = "user" }
    status       = { S = "active" }
  })
}

resource "aws_dynamodb_table_item" "official_shop_app" {
  for_each = local.official_shop_apps

  table_name = aws_dynamodb_table.main.name
  hash_key   = aws_dynamodb_table.main.hash_key
  range_key  = aws_dynamodb_table.main.range_key

  item = jsonencode({
    pk                   = { S = "APP#${each.value.app_id}" }
    sk                   = { S = "META" }
    entity               = { S = "app" }
    app_id               = { S = each.value.app_id }
    group_id             = { S = local.official_shop_group_id }
    title                = { S = each.value.title }
    owner_user_id        = { S = local.official_shop_owner_user_id }
    source_kind          = { S = "official_shop" }
    editable             = { BOOL = false }
    created_at           = { S = each.value.published_at }
    shop_visibility      = { S = "listed" }
    shop_listed_at       = { S = each.value.published_at }
    published_version    = { N = tostring(each.value.version) }
    published_key        = { S = aws_s3_object.official_shop_app[each.key].key }
    published_sha256     = { S = filesha256(each.value.source) }
    published_files_json = { S = jsonencode(each.value.files) }
    published_at         = { S = each.value.published_at }
  })
}

resource "aws_dynamodb_table_item" "official_shop_listing" {
  for_each = local.official_shop_apps

  table_name = aws_dynamodb_table.main.name
  hash_key   = aws_dynamodb_table.main.hash_key
  range_key  = aws_dynamodb_table.main.range_key

  item = jsonencode({
    pk            = { S = "SHOP" }
    sk            = { S = "APP#${each.value.app_id}" }
    entity        = { S = "shop_listing" }
    app_id        = { S = each.value.app_id }
    owner_user_id = { S = local.official_shop_owner_user_id }
    listed_at     = { S = each.value.published_at }
  })

  depends_on = [aws_dynamodb_table_item.official_shop_app]
}

# Girls built-ins are not duplicated into Shop:
# - memo: planned, not implemented yet
# - sing-along: karaoke
# - novel-starter: novel
# - minappchi: minappchi
# novel_editor is an authoring tool that requires minapp.authoring and is not a
# standalone Runtime work, so it is not a Shop listing either.
