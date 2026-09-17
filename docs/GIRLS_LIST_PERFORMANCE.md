# Girls list performance (2026-09-17)

The app hub now uses four requests for an already-installed group instead of
eight or more: groups, installed apps, maker contracts, and managed apps.
Managed-app retrieval overlaps maker discovery. All four use the same HTTP
client, allowing connection reuse. The editor/player check shares one app-list
read. Sample project discovery/hydration runs only when opening the Novel maker;
the explicit install flow still prepares its sample.

The authenticated shell owns a five-minute, in-memory display snapshot. It is
scoped to the access token and selected group, never written to disk, and always
refreshed after opening the tab. Actions stay disabled until refresh completes.
Refresh failures clear the snapshot and show a retry action instead of leaving
permanent loading indicators. A generation counter rejects stale responses
after group/session changes. Debug builds log list-load duration without IDs,
credentials, or response bodies.

## AWS configuration and current rollout

- Account: `314267685786`; region: `us-west-2`; API: `7ptvf2blw7`.
- Hosted identity API: 1024 MB, published version `1`, alias `live`.
- API Gateway invokes `live`, with alias-qualified permission.
- The desired provisioned concurrency is two. `hosted_performance_entry`
  initializes the three list backends while provisioned environments are
  allocated, preserving the original authorization and abuse-control handler.
- **Provisioned concurrency is not active yet.** The regional account limit is
  10. Service Quotas request `c4c12b7f8a914c93a10521fdb562a1f7TuAcYbXu`, support
  case `178961648900947`, is pending AWS review. AWS rejected a request for 200
  because its request API requires a value above its default of 1000; the
  accepted request is therefore for 1001. This quota is a ceiling, not purchased
  capacity. Only two provisioned environments are intended.

The initial deployment used `hosted_provisioned_concurrency=0`. The estimated
two-environment standing charge at 1 GB is $21.60 per 30 days in Oregon, excluding
requests, execution, other services and tax, once enabled.

## Scoped deployment artifacts

Other undeployed backend and template work was present in the checkout. The
deployed ZIP was built from the existing live ZIP plus only
`hosted_performance_entry.py`. No existing live Python module was changed.

- ZIP: `build/hosted-list-performance.zip`
- SHA-256: `f38149cde6519d07a0c94540945fc45e027ed3041d08bd408f7bd4980b76bec7`
- Saved applied plan: `build/hosted-list-performance-scoped.tfplan`
- Preserved original ZIP: `build/hosted-before-performance.zip`

`hosted_identity_package_path` allows this reviewed artifact to be selected
without publishing other repository changes. Normal builds omit the override
and package `backend/src`. IAM template resource expressions retain the same
ARNs but no longer pull template object uploads into a targeted API deployment.

## After the quota is approved

Check the current deployed function, alias, account quota, repository changes,
and package hash first. Re-plan rather than applying the old bootstrap plan:

```powershell
terraform -chdir=infra/hosted plan `
  '-var=hosted_provisioned_concurrency=2' `
  '-var=hosted_identity_package_path=C:/Users/mail/work/minapp/build/hosted-list-performance.zip' `
  '-target=aws_apigatewayv2_integration.hosted_identity_api' `
  '-out=C:/Users/mail/work/minapp/build/hosted-list-warm.tfplan'
```

Review for only the intended concurrency addition and zero destroys. Do not
reuse the package override if another deployment has replaced version 1; build
and review from the current deployment instead. Apply the reviewed saved plan,
then verify `RequestedProvisionedConcurrentExecutions=2`,
`AvailableProvisionedConcurrentExecutions=2`, `Status=READY`, and that API Gateway
still invokes the alias. Re-run the Hosted smoke test. A targeted plan is used
here specifically to avoid deploying unrelated pending template changes.

## Verification

- Flutter analysis passed; 20 focused mobile tests passed, including parallel
  reads, request count, cached first display, session separation, refresh error
  recovery, and stale-response suppression.
- Backend: all 345 tests passed under Ubuntu/Python via WSL. The existing
  year-9999 timestamp handling causes 27 failures with this workspace's Windows
  virtualenv; Linux matches the Lambda operating environment.
- Android debug APK built and installed on `emulator-5554`.
- With the deployed 1 GB API and no provisioned concurrency, one emulator
  debug-build measurement completed list retrieval in 2771 ms (no previous
  snapshot). The maker and existing apps displayed without an error. This is
  one post-change data-load sample, not a release-build benchmark or an
  end-to-end before/after comparison. Immediate cached display is covered by
  the widget test; no second manual timing was taken.
- The deployed public API passed the existing temporary-account Hosted smoke
  flow: health/legal, login, groups/apps, Runtime read/write/delete, fork,
  cleanup. The smoke account and its test resources were removed.
- No AWS data tables, user accounts, IAM policy grants, or template content were
  changed by the deployment. The two new resources are an alias and its invoke
  permission; the two updates are the identity function and its integration.
