# みんアプ tenant handover checklist

顧客AWSへ構築したtenantを引き渡すときのテンプレートです。秘密情報をこの文書へ貼り付けません。

## Identity / ownership

- [ ] Customer / school name: `<...>`
- [ ] AWS account ID: `<12 digits>`
- [ ] immutable tenant ID: `<32 lowercase hex>`
- [ ] resource region: `<...>`
- [ ] Directory display name: `<...>`
- [ ] Directory config revision: `<positive integer>`
- [ ] customer owns AWS billing and tenant resources
- [ ] no root credential was received by MinApp operator
- [ ] no long-lived customer access key is stored by MinApp operator

## Terraform state

- [ ] state bucket: `<...>`
- [ ] state key: `tenants/<tenant_id>/terraform.tfstate`
- [ ] bucket is in the customer account
- [ ] versioning enabled
- [ ] encryption enabled
- [ ] public access blocked
- [ ] state key is not shared with another tenant
- [ ] last reviewed plan SHA-256 recorded in the private onboarding record

Do not attach Terraform state or binary plan files to general-purpose tickets.

## Tenant endpoint

- [ ] API base URL: `<https://...>`
- [ ] `/tenant-info` reports expected tenant ID
- [ ] `/tenant-info` reports expected protocol version
- [ ] Directory `POST /v1/classrooms/resolve` resolves expected tenant
- [ ] Directory `GET /v1/tenants/{tenant_id}` resolves expected tenant

## Accounts / classroom

- [ ] first teacher bootstrap completed
- [ ] teacher completed first-login password change
- [ ] at least one group exists
- [ ] test student completed first-login password change
- [ ] classroom code delivered through approved handoff channel
- [ ] raw classroom code is not copied into general GitHub/Slack/email history unless that destination is explicitly approved
- [ ] official join link delivered if an official join domain is configured

## E2E

- [ ] approved smoke-test app exists
- [ ] Directory -> tenant-info -> Login -> Catalog -> Launch passed
- [ ] smoke-test date: `<...>`
- [ ] tested commit/app version: `<...>`
- [ ] evidence contains no password or token

## Support boundaries

- [ ] customer knows normal logout keeps the selected classroom
- [ ] customer knows `教室を変更` clears selected tenant/auth/WebView state
- [ ] customer knows Directory outage behavior and descriptor TTL
- [ ] customer knows Directory `deactivate` alone is not a hard security shutdown
- [ ] persistent cross-account support role: `none` unless separately designed and approved
- [ ] escalation/contact owner recorded outside this public template

## Final sign-off

- [ ] customer resource ownership confirmed
- [ ] state ownership confirmed
- [ ] classroom handoff completed
- [ ] operator temporary AWS session can be discarded
- [ ] no temporary credential remains in local notes or shell scripts
