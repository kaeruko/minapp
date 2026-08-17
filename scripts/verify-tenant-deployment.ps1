param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,15}$')]
    [string]$ExpectedEnvironment,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 2147483647)]
    [int]$ExpectedProtocolVersion = 1
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    $baseUri = [Uri]$ApiBaseUrl
}
catch {
    throw "ApiBaseUrl is not a valid URI: $ApiBaseUrl"
}
if ($baseUri.Scheme -ne "https" -or [string]::IsNullOrWhiteSpace($baseUri.Host)) {
    throw "ApiBaseUrl must be an absolute HTTPS URL."
}
if (-not [string]::IsNullOrEmpty($baseUri.UserInfo) -or -not [string]::IsNullOrEmpty($baseUri.Query) -or -not [string]::IsNullOrEmpty($baseUri.Fragment)) {
    throw "ApiBaseUrl must not contain user info, query, or fragment."
}

$endpoint = $ApiBaseUrl.TrimEnd('/') + "/tenant-info"
try {
    $payload = Invoke-RestMethod -Method Get -Uri $endpoint -Headers @{ Accept = "application/json" } -TimeoutSec 15
}
catch {
    throw "GET $endpoint failed: $($_.Exception.Message)"
}

$expectedFields = @("api_protocol_version", "environment", "service", "tenant_id") | Sort-Object
$actualFields = @($payload.PSObject.Properties.Name) | Sort-Object
if (($expectedFields -join "|") -ne ($actualFields -join "|")) {
    throw "tenant-info schema mismatch. Expected fields [$($expectedFields -join ', ')] but received [$($actualFields -join ', ')]."
}
if ($payload.service -ne "minapp-tenant-api") {
    throw "tenant-info service mismatch: $($payload.service)"
}
if ($payload.tenant_id -ne $ExpectedTenantId) {
    throw "tenant_id mismatch. Expected $ExpectedTenantId but endpoint reports $($payload.tenant_id)."
}
if ([int]$payload.api_protocol_version -ne $ExpectedProtocolVersion) {
    throw "API protocol mismatch. Expected $ExpectedProtocolVersion but endpoint reports $($payload.api_protocol_version)."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedEnvironment) -and $payload.environment -ne $ExpectedEnvironment) {
    throw "Environment mismatch. Expected $ExpectedEnvironment but endpoint reports $($payload.environment)."
}

Write-Host "Tenant deployment verified."
Write-Host "  Tenant:      $($payload.tenant_id)"
Write-Host "  API:         $ApiBaseUrl"
Write-Host "  Protocol:    $($payload.api_protocol_version)"
Write-Host "  Environment: $($payload.environment)"
