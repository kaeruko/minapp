[CmdletBinding()]
param(
    [switch]$SkipPull
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Context failed with exit code $exitCode."
    }
}

function Invoke-ExternalCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if ($exitCode -ne 0) {
        throw "$Context failed with exit code $exitCode`: $text"
    }
    return $text.Trim()
}

function Invoke-ExternalCaptureSeparated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "$Context could not start '$FilePath'."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    if ($exitCode -ne 0) {
        $diagnostic = if ([string]::IsNullOrWhiteSpace($stderr)) { '<empty stderr>' } else { $stderr.Trim() }
        throw "$Context failed with exit code $exitCode`: $diagnostic"
    }
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        $diagnostic = if ([string]::IsNullOrWhiteSpace($stderr)) { '<empty stderr>' } else { $stderr.Trim() }
        throw "$Context returned empty stdout. stderr: $diagnostic"
    }

    return [pscustomobject]@{
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

$null = Get-Command terraform -ErrorAction Stop
$null = Get-Command git -ErrorAction Stop

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hostedDir = Join-Path $repoRoot 'infra\hosted'
$backendConfig = Join-Path $hostedDir 'backend.hcl'
$minappAppsRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '..\minapp_apps'))
$novelEditorDir = Join-Path $minappAppsRoot 'novel_editor'
$novelEditorIndex = Join-Path $novelEditorDir 'index.html'
$novelEditorScript = Join-Path $novelEditorDir 'editor.js'
$targetAddress = 'aws_s3_object.hosted_builtin_source["novel-editor"]'
$planPath = Join-Path ([System.IO.Path]::GetTempPath()) ("minapp-novel-editor-{0}.tfplan" -f [Guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $hostedDir -PathType Container)) {
    throw "Hosted Terraform directory not found: $hostedDir"
}
if (-not (Test-Path -LiteralPath $backendConfig -PathType Leaf)) {
    throw "Hosted backend config is missing: $backendConfig"
}
if (-not (Test-Path -LiteralPath $novelEditorDir -PathType Container)) {
    throw "Sibling minapp_apps checkout is missing: $novelEditorDir"
}
if (-not (Test-Path -LiteralPath $novelEditorIndex -PathType Leaf)) {
    throw "Novel Editor index.html is missing: $novelEditorIndex"
}
if (-not (Test-Path -LiteralPath $novelEditorScript -PathType Leaf)) {
    throw "Novel Editor editor.js is missing: $novelEditorScript"
}

try {
    Write-Host '[1/6] Check local minapp_apps source'
    $branch = Invoke-ExternalCapture `
        -FilePath 'git' `
        -Arguments @('-C', $minappAppsRoot, 'branch', '--show-current') `
        -Context 'minapp_apps branch lookup'
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'minapp_apps is in detached HEAD state. Switch to an explicit branch before syncing.'
    }

    $status = Invoke-ExternalCapture `
        -FilePath 'git' `
        -Arguments @('-C', $minappAppsRoot, 'status', '--porcelain') `
        -Context 'minapp_apps status lookup'
    $dirty = -not [string]::IsNullOrWhiteSpace($status)
    Write-Host "  branch=$branch"

    if ($dirty -and -not $SkipPull) {
        throw @"
minapp_apps has local changes, so deployment stopped before Terraform.

Repository: $minappAppsRoot
Branch:     $branch

Run:
  git -C "$minappAppsRoot" status --short

Then either commit/stash the changes and re-run this script, or explicitly use -SkipPull only when you intentionally want to deploy the current dirty working tree.
"@
    }

    if ($branch -eq 'main' -and -not $SkipPull) {
        Write-Host '  clean main checkout: pulling latest minapp_apps with --ff-only'
        Invoke-External `
            -FilePath 'git' `
            -Arguments @('-C', $minappAppsRoot, 'pull', '--ff-only') `
            -Context 'minapp_apps fast-forward pull'
    }
    elseif ($SkipPull) {
        Write-Host '  SkipPull specified: intentionally syncing the current checkout without pulling'
    }
    else {
        Write-Host "  non-main branch '$branch': syncing that branch without pulling"
    }

    $sourceCommit = Invoke-ExternalCapture `
        -FilePath 'git' `
        -Arguments @('-C', $minappAppsRoot, 'rev-parse', '--short', 'HEAD') `
        -Context 'minapp_apps commit lookup'
    Write-Host "  source commit=$sourceCommit"

    Write-Host '[2/6] Initialize Hosted Terraform backend'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'init', '-backend-config=backend.hcl', '-input=false') `
        -Context 'Hosted Terraform init'

    Write-Host '[3/6] Validate Hosted Terraform configuration'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'validate') `
        -Context 'Hosted Terraform validate'

    Write-Host '[4/6] Plan Novel Editor source update only'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @(
            "-chdir=$hostedDir",
            'plan',
            '-input=false',
            "-target=$targetAddress",
            '-out', $planPath
        ) `
        -Context 'Novel Editor Terraform plan'

    $planCapture = Invoke-ExternalCaptureSeparated `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'show', '-json', $planPath) `
        -Context 'Novel Editor saved plan JSON'
    if (-not [string]::IsNullOrWhiteSpace($planCapture.Stderr)) {
        Write-Warning "terraform show emitted stderr while producing valid stdout: $($planCapture.Stderr)"
    }
    try {
        $plan = $planCapture.Stdout | ConvertFrom-Json -Depth 100
    }
    catch {
        $stderrDiagnostic = if ([string]::IsNullOrWhiteSpace($planCapture.Stderr)) { '<empty stderr>' } else { $planCapture.Stderr }
        throw "Novel Editor saved plan JSON could not be decoded: $($_.Exception.Message) stderr: $stderrDiagnostic"
    }

    Write-Host '[5/6] Reject changes outside the Novel Editor S3 object'
    $targetUpdateFound = $false
    $unexpected = @()
    foreach ($change in @($plan.resource_changes)) {
        $actions = @($change.change.actions)
        if ($actions.Count -eq 0 -or ($actions.Count -eq 1 -and $actions[0] -eq 'no-op')) {
            continue
        }
        if ($actions.Count -eq 1 -and $actions[0] -eq 'read') {
            continue
        }

        $address = [string]$change.address
        if ($address -eq $targetAddress -and $actions.Count -eq 1 -and $actions[0] -eq 'update') {
            $targetUpdateFound = $true
            continue
        }

        $unexpected += [pscustomobject]@{
            Address = $address
            Actions = ($actions -join ',')
        }
    }

    if ($unexpected.Count -ne 0) {
        $details = ($unexpected | ForEach-Object { "$($_.Address) [$($_.Actions)]" }) -join '; '
        throw "Novel Editor sync plan contains changes outside the single allowed S3 object update. Apply stopped. $details"
    }

    if (-not $targetUpdateFound) {
        Write-Host '  Novel Editor source is already in sync; nothing to apply.'
        Write-Host ''
        Write-Host 'Novel Editor dev sync complete.'
        return
    }

    Write-Host "  allowed update: $targetAddress"
    Write-Host '[6/6] Apply the exact saved plan'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'apply', '-input=false', $planPath) `
        -Context 'Novel Editor saved-plan apply'

    Write-Host ''
    Write-Host 'Novel Editor dev sync complete.'
    Write-Host 'Close any already-open editor WebView and open the Novel Editor again in Girls.'
}
finally {
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        Remove-Item -LiteralPath $planPath -Force
    }
}
