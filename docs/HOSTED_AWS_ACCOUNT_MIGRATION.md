# Hosted AWS account migration

Tracks #99.

## Decision for the current migration

At the time of this migration there are no production users to preserve.
The App Store submission was rejected, so there is no accepted production
client whose Hosted data must remain compatible with the old AWS account.

Therefore this migration is a **clean bootstrap**, not a data migration.

Do not copy these resources from the old account into the new account:

- Cognito users
- Hosted metadata DynamoDB rows
- Runtime DynamoDB rows
- draft/source objects
- published objects
- Runtime/content/authoring session records

Review/demo accounts, groups and apps are recreated after the new stack passes
smoke tests.

This decision is intentional. In particular, copying DynamoDB metadata while
creating a new Cognito User Pool is invalid because Cognito subjects change.
Do not implement a partial compatibility fallback.

## Invariants

The account move must not change these application contracts:

- Hosted tenant identity is explicit and immutable.
- Child apps never receive Cognito tokens or AWS credentials.
- Published content and Runtime use short-lived scoped capabilities.
- Group/app/membership checks remain server-side.
- Existing Runtime bridge errors keep their current fail-fast behavior.
- The client endpoint is changed only after the new stack passes smoke tests.

The new editable-app foundation from #98 is implemented only after the new AWS
stack is the active Hosted environment.

## Prepare the new account

Create a Terraform remote-state S3 bucket in the new AWS account outside this
stack. Then create the ignored local file `infra/hosted/backend.hcl` from
`backend.hcl.example` and point it at the **new** remote-state bucket/key.

Do not reuse the old account's Terraform state.

Use a dedicated AWS CLI profile for the new account. Confirm the intended:

- 12-digit AWS account ID
- Hosted tenant ID
- AWS region
- environment (`dev`, `prod`, etc.)
- remote-state bucket/key

No item above is inferred by the bootstrap script.

## Plan first

Run from the repository root:

```powershell
./scripts/plan-hosted-new-account.ps1 `
  -ExpectedAwsAccountId '<NEW_ACCOUNT_ID>' `
  -HostedTenantId '<HOSTED_TENANT_ID>' `
  -AwsRegion '<REGION>' `
  -Environment '<ENVIRONMENT>' `
  -AwsProfile '<NEW_AWS_PROFILE>'
```

The script stops unless all of the following are true:

1. `aws sts get-caller-identity` returns exactly the requested account.
2. the selected backend can be initialized explicitly with `-reconfigure`.
3. Terraform format/validation succeeds.
4. the saved plan contains at least one create.
5. the saved plan contains no update/delete/replacement action.

Without `-Apply`, nothing is applied.

The zero-user migration deliberately requires a create-only plan. If an update
or delete appears, diagnose the state/account/backend mismatch rather than
relaxing the check.

## Apply the exact verified plan

After reviewing the account, backend, tenant, region, environment and expected
resource creates, run the identical command with `-Apply`:

```powershell
./scripts/plan-hosted-new-account.ps1 `
  -ExpectedAwsAccountId '<NEW_ACCOUNT_ID>' `
  -HostedTenantId '<HOSTED_TENANT_ID>' `
  -AwsRegion '<REGION>' `
  -Environment '<ENVIRONMENT>' `
  -AwsProfile '<NEW_AWS_PROFILE>' `
  -Apply
```

The script applies the exact saved plan that it already inspected. It does not
create a second implicit plan.

## Verify the new Hosted stack

Read Terraform outputs only from the new backend:

```powershell
$hostedApiBaseUrl = terraform -chdir=infra/hosted output -raw api_base_url
$hostedTenantId = terraform -chdir=infra/hosted output -raw hosted_tenant_id
```

Run the Hosted smoke tests against the new API. The primary end-to-end smoke can
create its own temporary user:

```powershell
./scripts/smoke-test-hosted.ps1 `
  -HostedApiBaseUrl $hostedApiBaseUrl `
  -ExpectedTenantId $hostedTenantId `
  -TemporaryUser
```

Also run the source/publish and Runtime bridge coverage before cutover. The
Runtime bridge smoke requires the concrete Terraform outputs for table, pool and
bucket names plus the expected new AWS account/profile.

Do not switch a client to the new endpoint if any smoke test fails.

## Recreate review/demo state

After the clean stack passes smoke tests:

1. create the review/demo account through the normal Hosted API/UI;
2. recreate its group;
3. install the required built-ins/apps;
4. verify login, launch, content loading and Runtime state;
5. update App Review credentials/notes only after those checks pass.

Do not seed these records by writing directly to Cognito, DynamoDB or S3.

## Client cutover

Change the Flutter/Web Hosted API base URL only after the new environment is
verified. Then perform a production-device check covering:

- login/register/recovery as applicable
- group listing/creation/join
- app listing
- app launch
- published content delivery
- Runtime bridge state
- deletion/revocation behavior

Keep the old AWS stack intact during this verification window.

## Old account cleanup

Because this migration has zero production users, the old Hosted data is not a
rollback source after the new environment is accepted. It is only retained long
enough to make endpoint rollback possible during cutover verification.

Before deleting anything, explicitly confirm that no Flutter/Web configuration,
review notes, DNS/configuration file, CI setting or operator script still points
to the old Hosted API.

Then remove old Hosted resources deliberately. Do not point the new Terraform
state at the old resources and do not import them into the new state.

## Next architecture step

After cutover, implement #98 on the new account using the separate concepts:

```text
app_id      = executable package (Player / Editor)
content_id  = editable/published work
content_format = compatibility contract between them
```

See `docs/EDITABLE_APP_FOUNDATION.md`.
