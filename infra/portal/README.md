# Operator Web portal infrastructure

This Terraform stack creates the static production Web portal boundary described by Phase 6E.

It owns:

- a private, versioned S3 bucket for `apps/web`
- CloudFront with S3 Origin Access Control (OAC)
- a strict CloudFront security response-headers policy
- `/portal-config.json` containing only the Directory API base URL
- optional Route 53 aliases for the portal hostname
- optional ACM certificate creation and DNS validation when the authoritative zone is already in Route 53

It does **not** proxy tenant API requests. Browser login, ZIP upload, review and application operations go directly to the selected tenant API.

## Required inputs

```hcl
operator_account_id      = "123456789012"
environment              = "prod"
portal_domain            = "minapp.cloxs.jp"
directory_api_base_url   = "https://example.execute-api.us-west-2.amazonaws.com"
tenant_api_origins       = [
  "https://tenant-a.execute-api.us-west-2.amazonaws.com",
  "https://tenant-b.execute-api.us-west-2.amazonaws.com",
]
```

`tenant_api_origins` is the explicit CSP egress allow-list. Adding or rotating a tenant API endpoint requires updating this set before that endpoint can be used by the production browser portal.

## TLS and DNS modes

### Existing Route 53 zone

Set `route53_zone_id` and omit `certificate_arn`.

Terraform then:

1. requests the portal ACM certificate in `us-east-1`
2. creates its DNS validation record
3. waits for ACM validation
4. creates CloudFront
5. creates A and AAAA Route 53 aliases for `portal_domain`

### External authoritative DNS

Do not move the parent zone to Route 53 just for MinApp.

First create and validate an ACM certificate for `portal_domain` in `us-east-1`, then pass its ARN as `certificate_arn` and leave `route53_zone_id = null`.

After apply, point the external DNS record for `portal_domain` at the `cloudfront_domain_name` Terraform output. The stack intentionally does not guess or mutate an external DNS provider.

## Portal asset publishing

Terraform manages `portal-config.json` so the Directory endpoint cannot silently diverge from infrastructure configuration.

Publish the rest of `apps/web` to the `portal_bucket_name` output. When using `aws s3 sync --delete`, exclude `portal-config.json` because that object is Terraform-owned.

Example after reviewing and applying the Terraform plan:

```powershell
$bucket = terraform -chdir=infra/portal output -raw portal_bucket_name
$distribution = terraform -chdir=infra/portal output -raw cloudfront_distribution_id
aws s3 sync apps/web "s3://$bucket" --delete --exclude "portal-config.json"
aws cloudfront create-invalidation --distribution-id $distribution --paths "/*"
```

The default CloudFront behavior deliberately uses the managed `CachingDisabled` policy for the MVP. This keeps `index.html`, JavaScript/CSS and `portal-config.json` immediately updateable; fingerprinted assets can receive long-lived caching later.

## Security properties

- S3 public access is blocked.
- S3 object ownership is bucket-owner enforced.
- CloudFront signs S3 requests with OAC/SigV4.
- The bucket policy grants `s3:GetObject` only to the specific CloudFront distribution and denies insecure S3 transport.
- HTTP viewers are redirected to HTTPS.
- CloudFront uses an ACM certificate from `us-east-1` and TLS 1.2 or newer policy.
- CSP allows scripts/styles only from the portal itself and network/frame access only to the configured Directory/tenant origins.
- HSTS, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and framing protection are applied at CloudFront.
- No wildcard CORS or credentialed browser-cookie behavior is introduced by this stack.

## State

Use a separate operator-owned S3 backend key from Directory and tenant stacks, for example:

```hcl
bucket       = "<operator-state-bucket>"
key          = "portal/prod/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true
```

As with the other MinApp infrastructure boundaries, review `terraform plan` before apply and do not apply a plan containing unexpected deletes.
