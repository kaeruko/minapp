[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Region = "us-west-2"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$verifyScript = Join-Path $PSScriptRoot "verify-aws-deploy-target.ps1"
if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    throw "AWS deploy target verification script not found: $verifyScript"
}

& $verifyScript `
    -ExpectedAccountId $ExpectedAccountId `
    -Profile $Profile `
    -Region $Region

if ($LASTEXITCODE -ne 0) {
    throw "AWS authentication or deploy target verification failed."
}

$env:AWS_PROFILE = $Profile

Write-Host "MinApp AWS environment ready."
Write-Host "  Profile: $Profile"
Write-Host "  Account: $ExpectedAccountId"
Write-Host "  Region:  $Region"
