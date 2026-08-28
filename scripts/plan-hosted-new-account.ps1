param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{12}$')]
    [string]$ExpectedAwsAccountId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$HostedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z]{2}-[a-z]+-\d$')]
    [string]$AwsRegion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile,

    [ValidateNotNullOrEmpty()]
    [string]$BackendConfig = 'backend.hcl',

    [switch]$Apply
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
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Context returned empty output."
    }
    return $text.Trim()
}

$null = Get-Command aws -ErrorAction Stop
$null = Get-Command terraform -ErrorAction Stop

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hostedDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'infra/hosted'))
$backendPath = if ([System.IO.Path]::IsPathRooted($BackendConfig)) {
    [System.IO.Path]::GetFullPath($BackendConfig)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $hostedDir $BackendConfig))
}

if (-not (Test-Path -LiteralPath $backendPath -PathType Leaf)) {
    throw "Hosted backend config is missing: $backendPath"
}

$previousProfile = $env:AWS_PROFILE
$previousRegion = $env:AWS_REGION
$planPath = Join-Path ([System.IO.Path]::GetTempPath()) ("minapp-hosted-new-account-{0}.tfplan" -f [Guid]::NewGuid().ToString('N'))

try {
    $env:AWS_PROFILE = $AwsProfile
    $env:AWS_REGION = $AwsRegion

    Write-Host '[1/6] Verify AWS caller identity'
    $identityText = Invoke-ExternalCapture `
        -FilePath 'aws' `
        -Arguments @(
            'sts', 'get-caller-identity',
            '--profile', $AwsProfile,
            '--region', $AwsRegion,
            '--output', 'json',
            '--no-cli-pager'
        ) `
        -Context 'AWS caller identity'

    try {
        $identity = $identityText | ConvertFrom-Json
    }
    catch {
        throw "AWS caller identity returned non-JSON output: $identityText"
    }

    if ([string]$identity.Account -ne $ExpectedAwsAccountId) {
        throw "AWS account mismatch. Expected $ExpectedAwsAccountId but received $($identity.Account)."
    }
    Write-Host "  Account=$($identity.Account)"
    Write-Host "  Arn=$($identity.Arn)"

    Write-Host '[2/6] Reinitialize Terraform against the explicitly selected backend'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @(
            "-chdir=$hostedDir",
            'init',
            '-reconfigure',
            "-backend-config=$backendPath"
        ) `
        -Context 'Hosted Terraform init'

    Write-Host '[3/6] Validate Terraform configuration'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'fmt', '-check') `
        -Context 'Hosted Terraform fmt check'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'validate') `
        -Context 'Hosted Terraform validate'

    Write-Host '[4/6] Create a saved plan with explicit account, tenant and region'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @(
            "-chdir=$hostedDir",
            'plan',
            '-out', $planPath,
            '-var', "expected_account_id=$ExpectedAwsAccountId",
            '-var', "hosted_tenant_id=$HostedTenantId",
            '-var', "aws_region=$AwsRegion"
        ) `
        -Context 'Hosted Terraform plan'

    Write-Host '[5/6] Reject destructive or mutating plans'
    $planJsonText = Invoke-ExternalCapture `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'show', '-json', $planPath) `
        -Context 'Hosted saved plan JSON'

    try {
        $plan = $planJsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        throw 'Hosted saved plan could not be decoded as Terraform JSON.'
    }

    $unexpected = @(
        $plan.resource_changes |
            Where-Object {
                $actions = @($_.change.actions)
                $actions -contains 'delete' -or $actions -contains 'update'
            }
    )
    if ($unexpected.Count -ne 0) {
        $details = @(
            $unexpected |
                ForEach-Object {
                    $actions = @($_.change.actions) -join ','
                    "$($_.address) [$actions]"
                }
        ) -join '; '
        throw "New-account bootstrap plan contains update/delete/replacement actions. Apply stopped. $details"
    }

    $creates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'create' }
    ).Count
    if ($creates -eq 0) {
        throw 'New-account bootstrap plan contains no resource creates. Refusing to treat this as a fresh bootstrap.'
    }
    Write-Host "  Fresh bootstrap accepted: creates=$creates updates=0 deletes=0"

    Write-Host '[6/6] Finish'
    if (-not $Apply) {
        Write-Host '  Plan verified. Nothing was applied because -Apply was not specified.'
        Write-Host "  Re-run the same command with -Apply after reviewing account, backend, tenant and region."
        return
    }

    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'apply', $planPath) `
        -Context 'Hosted Terraform saved-plan apply'

    Write-Host 'Hosted new-account bootstrap apply completed.'
    Write-Host 'Run the Hosted smoke-test suite before changing any client API endpoint.'
}
finally {
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        Remove-Item -LiteralPath $planPath -Force
    }
    $env:AWS_PROFILE = $previousProfile
    $env:AWS_REGION = $previousRegion
}
