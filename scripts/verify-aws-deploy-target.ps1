param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Region
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "Required command was not found in PATH: aws"
}

$arguments = @("sts", "get-caller-identity", "--output", "json", "--no-cli-pager")
if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $arguments += @("--profile", $Profile)
}
if (-not [string]::IsNullOrWhiteSpace($Region)) {
    $arguments += @("--region", $Region)
}

$rawIdentity = & aws @arguments
if ($LASTEXITCODE -ne 0) {
    throw "aws sts get-caller-identity failed with exit code $LASTEXITCODE."
}
if ([string]::IsNullOrWhiteSpace(($rawIdentity -join "`n"))) {
    throw "aws sts get-caller-identity returned an empty response."
}

try {
    $identity = ($rawIdentity -join "`n") | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "aws sts get-caller-identity returned invalid JSON: $($_.Exception.Message)"
}

if ($identity.Account -ne $ExpectedAccountId) {
    throw "AWS account mismatch. Expected $ExpectedAccountId but current credentials target $($identity.Account)."
}
if ([string]::IsNullOrWhiteSpace([string]$identity.Arn)) {
    throw "AWS caller identity response did not contain Arn."
}

$profileLabel = if ([string]::IsNullOrWhiteSpace($Profile)) { "default credential chain" } else { "profile '$Profile'" }
$regionLabel = if ([string]::IsNullOrWhiteSpace($Region)) { "credential/default configuration" } else { "explicit '$Region'" }
Write-Host "AWS deploy target verified."
Write-Host "  Account: $($identity.Account)"
Write-Host "  Caller:  $($identity.Arn)"
Write-Host "  Source:  $profileLabel"
Write-Host "  Region:  $regionLabel"
