param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{12}$')]
    [string]$ExpectedAwsAccountId,

    [ValidatePattern('^[a-z]{2}-[a-z]+-\d$')]
    [string]$AwsRegion = 'us-west-2',

    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile = 'minapp-admin',

    [ValidateNotNull()]
    [string[]]$AllowedReplacementAddresses = @()
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

function Get-TerraformOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return Invoke-ExternalCapture `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'output', '-raw', $Name) `
        -Context "Terraform output $Name"
}

$null = Get-Command aws -ErrorAction Stop
$null = Get-Command terraform -ErrorAction Stop
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hostedDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'infra/hosted'))
$backendConfig = Join-Path $hostedDir 'backend.hcl'
$smokeScript = Join-Path $PSScriptRoot 'smoke-test-hosted-runtime-bridge.ps1'

if (-not (Test-Path -LiteralPath $backendConfig -PathType Leaf)) {
    throw "Hosted backend config is missing: $backendConfig"
}
if (-not (Test-Path -LiteralPath $smokeScript -PathType Leaf)) {
    throw "Hosted Runtime bridge smoke script is missing: $smokeScript"
}

$allowedReplacementSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($address in $AllowedReplacementAddresses) {
    if ([string]::IsNullOrWhiteSpace($address)) {
        throw 'AllowedReplacementAddresses must not contain an empty address.'
    }
    if (-not $allowedReplacementSet.Add($address)) {
        throw "AllowedReplacementAddresses contains a duplicate address: $address"
    }
}

$previousProfile = $env:AWS_PROFILE
$previousRegion = $env:AWS_REGION
$planPath = Join-Path ([System.IO.Path]::GetTempPath()) ("minapp-hosted-issue87-{0}.tfplan" -f [Guid]::NewGuid().ToString('N'))

try {
    $env:AWS_PROFILE = $AwsProfile
    $env:AWS_REGION = $AwsRegion

    Write-Host '[1/8] Verify AWS caller identity'
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

    Write-Host '[2/8] Initialize Hosted dev Terraform backend'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'init', '-backend-config=backend.hcl') `
        -Context 'Hosted Terraform init'

    Write-Host '[3/8] Validate Hosted Terraform configuration'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'fmt', '-check') `
        -Context 'Hosted Terraform fmt check'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'validate') `
        -Context 'Hosted Terraform validate'

    Write-Host '[4/8] Create saved Hosted dev plan'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @(
            "-chdir=$hostedDir",
            'plan',
            '-out', $planPath,
            '-var', "expected_account_id=$ExpectedAwsAccountId"
        ) `
        -Context 'Hosted Terraform plan'

    Write-Host '[5/8] Reject unapproved destroy/replacement actions before apply'
    $planCapture = Invoke-ExternalCaptureSeparated `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'show', '-json', $planPath) `
        -Context 'Hosted saved plan JSON'
    if (-not [string]::IsNullOrWhiteSpace($planCapture.Stderr)) {
        Write-Warning "terraform show emitted stderr while producing valid stdout: $($planCapture.Stderr)"
    }
    try {
        $plan = $planCapture.Stdout | ConvertFrom-Json -Depth 100
    }
    catch {
        $stderrDiagnostic = if ([string]::IsNullOrWhiteSpace($planCapture.Stderr)) { '<empty stderr>' } else { $planCapture.Stderr }
        throw "Hosted saved plan could not be decoded as Terraform JSON: $($_.Exception.Message) stderr: $stderrDiagnostic"
    }

    $approvedReplacementSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $blockedDestructive = @()
    foreach ($change in @($plan.resource_changes)) {
        $actions = @($change.change.actions)
        if ($actions -notcontains 'delete') {
            continue
        }

        $address = [string]$change.address
        $isReplacement = $actions -contains 'create'
        if ($isReplacement -and $allowedReplacementSet.Contains($address)) {
            [void]$approvedReplacementSet.Add($address)
            continue
        }

        $blockedDestructive += [pscustomobject]@{
            Address = $address
            Actions = ($actions -join ',')
        }
    }

    if ($blockedDestructive.Count -ne 0) {
        $details = ($blockedDestructive | ForEach-Object { "$($_.Address) [$($_.Actions)]" }) -join '; '
        throw "Hosted plan contains unapproved destroy/replacement actions. Apply stopped. $details"
    }

    $unusedReplacementApprovals = @(
        $allowedReplacementSet |
            Where-Object { -not $approvedReplacementSet.Contains($_) }
    )
    if ($unusedReplacementApprovals.Count -ne 0) {
        throw "Allowed replacement address was not present as an exact create+delete replacement. Apply stopped. $($unusedReplacementApprovals -join '; ')"
    }

    $creates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'create' }
    ).Count
    $updates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'update' }
    ).Count
    $replacements = $approvedReplacementSet.Count
    Write-Host "  saved plan accepted: creates=$creates updates=$updates approved_replacements=$replacements unapproved_destroys=0"
    foreach ($address in $approvedReplacementSet) {
        Write-Host "  approved replacement: $address"
    }

    Write-Host '[6/8] Apply the exact saved plan'
    Invoke-External `
        -FilePath 'terraform' `
        -Arguments @("-chdir=$hostedDir", 'apply', $planPath) `
        -Context 'Hosted Terraform saved-plan apply'

    Write-Host '[7/8] Read applied Hosted dev outputs'
    $apiBaseUrl = Get-TerraformOutput -Name 'api_base_url'
    $tenantId = Get-TerraformOutput -Name 'hosted_tenant_id'
    $dataTableName = Get-TerraformOutput -Name 'main_table_name'
    $runtimeTableName = Get-TerraformOutput -Name 'runtime_table_name'
    $userPoolId = Get-TerraformOutput -Name 'user_pool_id'
    $uploadBucketName = Get-TerraformOutput -Name 'upload_bucket_name'
    $publishedBucketName = Get-TerraformOutput -Name 'published_bucket_name'

    Write-Host "  API=$apiBaseUrl"
    Write-Host "  Tenant=$tenantId"

    Write-Host '[8/8] Run real AWS Runtime bridge smoke and physical cleanup verification'
    & $smokeScript `
        -HostedApiBaseUrl $apiBaseUrl `
        -ExpectedTenantId $tenantId `
        -ExpectedAwsAccountId $ExpectedAwsAccountId `
        -AwsRegion $AwsRegion `
        -AwsProfile $AwsProfile `
        -DataTableName $dataTableName `
        -RuntimeTableName $runtimeTableName `
        -UserPoolId $userPoolId `
        -UploadBucketName $uploadBucketName `
        -PublishedBucketName $publishedBucketName
    if ($LASTEXITCODE -ne 0) {
        throw "Hosted Runtime bridge smoke failed with exit code $LASTEXITCODE."
    }

    Write-Host ''
    Write-Host 'Issue #87 Hosted dev acceptance passed.'
    Write-Host 'Verified: saved plan has no unapproved destroys -> exact saved-plan apply -> real AWS launch/state/revocation -> Cognito/DynamoDB/S3 cleanup.'
}
finally {
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        Remove-Item -LiteralPath $planPath -Force
    }
    $env:AWS_PROFILE = $previousProfile
    $env:AWS_REGION = $previousRegion
}
