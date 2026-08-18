param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$DirectoryApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClassroomCode,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$ExpectedTenantApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,31}$')]
    [string]$LoginId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedAppTitle
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-StrictHttpsBaseUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        $uri = [Uri]$Value
    }
    catch {
        throw "$Name is not a valid URI."
    }

    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne "https" -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "$Name must be an absolute HTTPS URL."
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw "$Name must not contain user info, query, or fragment."
    }
    if ($uri.Port -ne 443) {
        throw "$Name must use the default HTTPS port."
    }
    if ($uri.AbsolutePath -ne "/") {
        throw "$Name must not contain a path."
    }
    if ($uri.HostNameType -eq [System.UriHostNameType]::IPv4 -or $uri.HostNameType -eq [System.UriHostNameType]::IPv6) {
        throw "$Name must not use an IP literal."
    }

    return $uri
}

function Assert-ExactFields {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Payload,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedFields,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $Payload) {
        throw "$Context returned no JSON object."
    }
    $actualFields = @($Payload.PSObject.Properties.Name) | Sort-Object
    $expected = @($ExpectedFields) | Sort-Object
    if (($actualFields -join "|") -ne ($expected -join "|")) {
        throw "$Context schema mismatch. Expected [$($expected -join ', ')] but received [$($actualFields -join ', ')]."
    }
}

$directoryUri = Get-StrictHttpsBaseUri -Value $DirectoryApiBaseUrl -Name "DirectoryApiBaseUrl"
$expectedTenantUri = Get-StrictHttpsBaseUri -Value $ExpectedTenantApiBaseUrl -Name "ExpectedTenantApiBaseUrl"

$normalizedCode = $ClassroomCode.Replace("-", "").ToUpperInvariant()
if ($normalizedCode -notmatch '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{12}$') {
    throw "ClassroomCode is invalid."
}
$formattedCode = "{0}-{1}-{2}" -f $normalizedCode.Substring(0, 4), $normalizedCode.Substring(4, 4), $normalizedCode.Substring(8, 4)

$resolveEndpoint = $directoryUri.AbsoluteUri.TrimEnd('/') + "/v1/classrooms/resolve"
$resolveBody = @{ code = $formattedCode } | ConvertTo-Json -Compress
try {
    $descriptor = Invoke-RestMethod `
        -Method Post `
        -Uri $resolveEndpoint `
        -Headers @{ Accept = "application/json" } `
        -ContentType "application/json" `
        -Body $resolveBody `
        -TimeoutSec 15
}
catch {
    throw "Directory classroom resolve failed: $($_.Exception.Message)"
}
finally {
    $resolveBody = $null
}

Assert-ExactFields `
    -Payload $descriptor `
    -ExpectedFields @("schema_version", "tenant_id", "display_name", "api_base_url", "api_protocol_version", "config_revision", "valid_for_seconds") `
    -Context "Directory descriptor"

if ([int]$descriptor.schema_version -ne 1) {
    throw "Unsupported Directory schema_version: $($descriptor.schema_version)"
}
if ($descriptor.tenant_id -ne $ExpectedTenantId) {
    throw "Directory resolved the wrong tenant. Expected $ExpectedTenantId but received $($descriptor.tenant_id)."
}
if ([int]$descriptor.api_protocol_version -ne 1) {
    throw "Unsupported tenant protocol: $($descriptor.api_protocol_version)"
}
if ([int]$descriptor.config_revision -lt 1) {
    throw "Directory returned an invalid config_revision."
}
if ([int]$descriptor.valid_for_seconds -lt 1 -or [int]$descriptor.valid_for_seconds -gt 86400) {
    throw "Directory returned an unsupported descriptor TTL."
}

$resolvedTenantUri = Get-StrictHttpsBaseUri -Value ([string]$descriptor.api_base_url) -Name "Directory api_base_url"
if ($resolvedTenantUri.AbsoluteUri.TrimEnd('/') -ne $expectedTenantUri.AbsoluteUri.TrimEnd('/')) {
    throw "Directory resolved the wrong tenant API. Expected $($expectedTenantUri.AbsoluteUri) but received $($resolvedTenantUri.AbsoluteUri)."
}

$tenantInfoEndpoint = $resolvedTenantUri.AbsoluteUri.TrimEnd('/') + "/tenant-info"
try {
    $tenantInfo = Invoke-RestMethod `
        -Method Get `
        -Uri $tenantInfoEndpoint `
        -Headers @{ Accept = "application/json" } `
        -TimeoutSec 15
}
catch {
    throw "Tenant /tenant-info verification failed: $($_.Exception.Message)"
}

Assert-ExactFields `
    -Payload $tenantInfo `
    -ExpectedFields @("service", "tenant_id", "api_protocol_version", "environment") `
    -Context "tenant-info"

if ($tenantInfo.service -ne "minapp-tenant-api") {
    throw "tenant-info service mismatch: $($tenantInfo.service)"
}
if ($tenantInfo.tenant_id -ne $ExpectedTenantId) {
    throw "tenant-info tenant mismatch. Expected $ExpectedTenantId but received $($tenantInfo.tenant_id)."
}
if ([int]$tenantInfo.api_protocol_version -ne 1) {
    throw "tenant-info protocol mismatch: $($tenantInfo.api_protocol_version)"
}

$securePassword = Read-Host "Password for $LoginId" -AsSecureString
$passwordPointer = [IntPtr]::Zero
$password = $null
$accessToken = $null
$loginBody = $null
try {
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    if ([string]::IsNullOrEmpty($password)) {
        throw "Password must not be empty."
    }

    $loginBody = @{
        login_id = $LoginId
        password = $password
    } | ConvertTo-Json -Compress

    $loginEndpoint = $resolvedTenantUri.AbsoluteUri.TrimEnd('/') + "/auth/login"
    try {
        $login = Invoke-RestMethod `
            -Method Post `
            -Uri $loginEndpoint `
            -Headers @{ Accept = "application/json" } `
            -ContentType "application/json" `
            -Body $loginBody `
            -TimeoutSec 15
    }
    catch {
        throw "Tenant login failed: $($_.Exception.Message)"
    }

    if ($login.state -eq "new_password_required") {
        throw "Smoke test requires a user with a permanent password. Complete the first-login password change before retrying."
    }
    if ($login.state -ne "authenticated") {
        throw "Tenant login returned unsupported state: $($login.state)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$login.access_token)) {
        throw "Tenant login returned no access token."
    }
    $accessToken = [string]$login.access_token

    $authHeaders = @{
        Accept = "application/json"
        Authorization = "Bearer $accessToken"
    }
    $catalogEndpoint = $resolvedTenantUri.AbsoluteUri.TrimEnd('/') + "/mobile/apps"
    try {
        $catalog = Invoke-RestMethod `
            -Method Get `
            -Uri $catalogEndpoint `
            -Headers $authHeaders `
            -TimeoutSec 15
    }
    catch {
        throw "Mobile catalog request failed: $($_.Exception.Message)"
    }

    if ($null -eq $catalog.apps) {
        throw "Mobile catalog response has no apps list."
    }
    $matchingApps = @($catalog.apps | Where-Object { $_.title -eq $ExpectedAppTitle })
    if ($matchingApps.Count -ne 1) {
        throw "Expected exactly one approved app titled '$ExpectedAppTitle' but found $($matchingApps.Count)."
    }
    $app = $matchingApps[0]
    if ($app.status -ne "approved") {
        throw "Expected app is not approved: $($app.status)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$app.app_id) -or [string]::IsNullOrWhiteSpace([string]$app.version_id)) {
        throw "Expected app is missing app_id or version_id."
    }

    $launchEndpoint = $resolvedTenantUri.AbsoluteUri.TrimEnd('/') + "/mobile/apps/$($app.app_id)/versions/$($app.version_id)/launch"
    try {
        $launch = Invoke-RestMethod `
            -Method Post `
            -Uri $launchEndpoint `
            -Headers $authHeaders `
            -ContentType "application/json" `
            -Body "{}" `
            -TimeoutSec 15
    }
    catch {
        throw "Launch grant request failed: $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$launch.url) -or [int]$launch.expires_in -le 0) {
        throw "Launch grant response is invalid."
    }
    try {
        $launchUri = [Uri][string]$launch.url
    }
    catch {
        throw "Launch URL is malformed."
    }
    if (-not $launchUri.IsAbsoluteUri -or $launchUri.Scheme -ne "https") {
        throw "Launch URL is not absolute HTTPS."
    }
    if ($launchUri.Host -ne $resolvedTenantUri.Host -or $launchUri.Port -ne $resolvedTenantUri.Port) {
        throw "Launch URL escaped the verified tenant origin."
    }
    if ($launchUri.AbsolutePath -notmatch '^/launch/[A-Za-z0-9_-]{32,64}/') {
        throw "Launch URL path is invalid."
    }

    try {
        $launchResponse = Invoke-WebRequest `
            -Method Get `
            -Uri $launchUri.AbsoluteUri `
            -Headers @{ Accept = "text/html,*/*" } `
            -TimeoutSec 15
    }
    catch {
        throw "Launch content request failed: $($_.Exception.Message)"
    }
    if ([int]$launchResponse.StatusCode -lt 200 -or [int]$launchResponse.StatusCode -ge 300) {
        throw "Launch content returned HTTP $($launchResponse.StatusCode)."
    }

    Write-Host "Federated tenant smoke test passed."
    Write-Host "  Tenant:      $ExpectedTenantId"
    Write-Host "  API:         $($resolvedTenantUri.AbsoluteUri.TrimEnd('/'))"
    Write-Host "  Environment: $($tenantInfo.environment)"
    Write-Host "  App:         $ExpectedAppTitle"
    Write-Host "  Launch:      verified"
}
finally {
    $accessToken = $null
    $loginBody = $null
    $password = $null
    $securePassword = $null
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}
