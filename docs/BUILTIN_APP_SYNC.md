# Built-in app synchronization

`minapp_apps` is the source of truth for individual app source. Existing Flutter
built-ins are copied into `apps/mobile/assets/builtin` before the Android app is
released. Some apps are also published by the Hosted Terraform stack for Shop
or group use.

Use `scripts/sync-builtin-app.ps1` to keep these paths in sync without encoding
an app-specific file list in the script. The script reads the runtime file list
from `apps/mobile/pubspec.yaml`.

## Prerequisites

By default, the repositories are expected to be sibling checkouts:

```text
work/
  minapp/
  minapp_apps/
```

Required commands are `git`, `node`, and `flutter`. Hosted planning also
requires `terraform`, AWS credentials, and the local Hosted backend files.

The source checkout must be on a named branch and clean. This prevents an
uncommitted working tree from being published accidentally. A clean `main`
checkout is updated with `git pull --ff-only` before files are discovered.
Built-in files containing a native `MinAppBuiltinState` Host overlay are
preserved when the portable source does not contain that bridge.

## Default: synchronize everything and deploy AWS

Running the script without arguments is the complete release path:

```powershell
cd C:\Users\mail\work\minapp
.\scripts\sync-builtin-app.ps1
```

This synchronizes every built-in registered in `pubspec.yaml`, runs all source
and Flutter built-in tests, creates a guarded Hosted Terraform plan, rejects
destroy or replacement actions, and applies the accepted plan to AWS.

Because the no-argument command changes AWS, first verify the active identity:

```powershell
aws sts get-caller-identity
```

To preview the same all-app Hosted plan without changing AWS, use:

```powershell
.\scripts\sync-builtin-app.ps1 -PlanHosted
```

## Selective and sync-only operation

Pass the source directory name used below `minapp_apps` and
`assets/builtin`:

```powershell
cd C:\Users\mail\work\minapp
.\scripts\sync-builtin-app.ps1 -AppName sing_along
```

Multiple apps can be synchronized in one run:

```powershell
.\scripts\sync-builtin-app.ps1 -AppName sing_along,minappchi
```

Synchronize all registered built-ins without AWS deployment:

```powershell
.\scripts\sync-builtin-app.ps1 -All
```

The script performs these operations:

1. verifies the `minapp_apps` checkout and records its branch and commit;
2. discovers registered runtime files from `pubspec.yaml`;
3. runs `test_*.js` files found in the selected source directories;
4. copies text and binary assets into the Flutter built-in directory;
5. runs `flutter test test/builtin_apps_test.dart` and `git diff --check`;
6. applies Hosted Terraform for the no-argument command, or follows the
   explicitly selected plan/apply/sync-only mode.

Text assets retain their line-ending style and are normalized to one final
newline. Existing target changes are never overwritten unless they already
match the source or `-ForceOverwrite` is explicitly supplied.

## Hosted AWS publication

Preview the complete Hosted Terraform plan without changing AWS:

```powershell
.\scripts\sync-builtin-app.ps1 -PlanHosted
```

Targeted Hosted plan/apply remains available when only one app is being
prepared:

```powershell
.\scripts\sync-builtin-app.ps1 -AppName sing_along -PlanHosted
.\scripts\sync-builtin-app.ps1 -AppName sing_along -ApplyHosted
```

The no-argument command and `-ApplyHosted` change AWS. Both delegate to
`scripts/deploy-hosted.ps1`, which creates a saved plan and rejects destroy or
replacement actions before applying it.
Whether a selected app produces an AWS change is determined by the Hosted
Terraform configuration. For example, an official Shop app may update its S3
published source and DynamoDB metadata, while a mobile-only app has no Hosted
change.

## Deliberate overrides

`-AllowDirtySource` permits synchronization from an uncommitted
`minapp_apps` working tree. `-ForceOverwrite` permits replacement of a target
asset that already has different local changes. Both options should be used
only after inspecting the relevant repository status and diff.

A non-sibling source checkout can be selected explicitly:

```powershell
.\scripts\sync-builtin-app.ps1 -AppName sing_along -SourceRoot D:\src\minapp_apps
```

## Boundaries

The script does not create a new built-in registration, commit or push Git
changes, build a release APK/AAB, or publish an Android release. A new app must
first be registered in `builtin_apps.dart` and `pubspec.yaml`, with its artwork
and tests added deliberately. Release and store submission remain separate,
reviewed operations.
