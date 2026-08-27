param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,31}$')]
    [string]$LoginId,

    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,63}$')]
    [string]$BuiltinId = 'shiba-game'
)

$ErrorActionPreference = 'Stop'
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

    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "$Name must be an absolute HTTPS URL."
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw "$Name must not contain user info, query, or fragment."
    }
    if ($uri.Port -ne 443) {
        throw "$Name must use the default HTTPS port."
    }
    if ($uri.AbsolutePath -ne '/') {
        throw "$Name must not contain a path."
    }
    if ($uri.HostNameType -eq [System.UriHostNameType]::IPv4 -or $uri.HostNameType -eq [System.UriHostNameType]::IPv6) {
        throw "$Name must not use an IP literal."
    }

    return $uri
}

function Assert-HexId {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Value -notmatch '^[0-9a-f]{32}$') {
        throw "$Name must be a 32-character lowercase hexadecimal ID. Received '$Value'."
    }
}

function Invoke-JsonApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [AllowNull()]
        [object]$Body,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        TimeoutSec = 15
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    try {
        return Invoke-RestMethod @parameters
    }
    catch {
        throw "$Context failed: $($_.Exception.Message)"
    }
}

function Invoke-NoContentDelete {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    try {
        $response = Invoke-WebRequest `
            -Method Delete `
            -Uri $Uri `
            -Headers $Headers `
            -TimeoutSec 15
    }
    catch {
        throw "$Context failed: $($_.Exception.Message)"
    }

    if ([int]$response.StatusCode -ne 204) {
        throw "$Context returned HTTP $([int]$response.StatusCode); expected 204."
    }
}

$baseUri = Get-StrictHttpsBaseUri -Value $HostedApiBaseUrl -Name 'HostedApiBaseUrl'
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }

Write-Host '[1/12] Verify Hosted health and tenant identity'
$health = Invoke-JsonApi -Method GET -Uri "$base/hosted/health" -Headers $publicHeaders -Body $null -Context 'Hosted health'
if ($health.service -ne 'minapp-hosted-api' -or $health.status -ne 'ok') {
    throw "Hosted health response is invalid. service='$($health.service)' status='$($health.status)'."
}

$tenantInfo = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
if ($tenantInfo.service -ne 'minapp-tenant-api') {
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
$authHeaders = $null
$groupId = $null
$installedAppId = $null
$forkedAppId = $null
$runtimeToken = $null

try {
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Password must not be empty.'
    }

    Write-Host '[2/12] Login'
    $login = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $LoginId; password = $password } `
        -Context 'Hosted login'

    if ($login.state -ne 'authenticated') {
        throw "Hosted login returned unsupported state: $($login.state)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$login.access_token)) {
        throw 'Hosted login returned no access token.'
    }
    $accessToken = [string]$login.access_token
    $authHeaders = @{
        Accept = 'application/json'
        Authorization = "Bearer $accessToken"
    }

    Write-Host '[3/12] Verify /hosted/me'
    $me = Invoke-JsonApi -Method GET -Uri "$base/hosted/me" -Headers $authHeaders -Body $null -Context 'Hosted /me'
    if ($null -eq $me.user) {
        throw 'Hosted /me returned no user object.'
    }
    Assert-HexId -Value ([string]$me.user.user_id) -Name 'Hosted user_id'
    if ($me.user.login_id -ne $LoginId -or $me.user.role -ne 'user' -or $me.user.status -ne 'active') {
        throw "Hosted /me user mismatch. login_id='$($me.user.login_id)' role='$($me.user.role)' status='$($me.user.status)'."
    }

    $runId = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $groupName = "Hosted E2E $runId"

    Write-Host '[4/12] Create group'
    $group = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups" `
        -Headers $authHeaders `
        -Body @{ name = $groupName } `
        -Context 'Hosted group creation'

    $groupId = [string]$group.group_id
    Assert-HexId -Value $groupId -Name 'Created group_id'
    if ($group.name -ne $groupName -or $group.role -ne 'owner' -or $group.status -ne 'active' -or $group.visibility -ne 'private') {
        throw "Created group response is invalid. group_id=$groupId"
    }
    Write-Host "  group_id=$groupId"

    Write-Host '[5/12] Verify group listing'
    $groupsResponse = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups" -Headers $authHeaders -Body $null -Context 'Hosted group listing'
    $matchingGroups = @($groupsResponse.groups | Where-Object { $_.group_id -eq $groupId })
    if ($matchingGroups.Count -ne 1) {
        throw "Expected exactly one listed group with id $groupId but found $($matchingGroups.Count)."
    }

    Write-Host "[6/12] Install builtin '$BuiltinId'"
    $installed = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/install" `
        -Headers $authHeaders `
        -Body @{ builtin_id = $BuiltinId } `
        -Context 'Hosted builtin install'

    $installedAppId = [string]$installed.app_id
    Assert-HexId -Value $installedAppId -Name 'Installed app_id'
    if ($installed.group_id -ne $groupId -or $installed.source_kind -ne 'builtin' -or $installed.builtin_id -ne $BuiltinId -or [bool]$installed.editable) {
        throw "Installed app response is invalid. app_id=$installedAppId"
    }
    Write-Host "  app_id=$installedAppId"

    Write-Host '[7/12] Verify group app listing'
    $appsResponse = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/apps" -Headers $authHeaders -Body $null -Context 'Hosted app listing'
    $matchingApps = @($appsResponse.apps | Where-Object { $_.app_id -eq $installedAppId })
    if ($matchingApps.Count -ne 1) {
        throw "Expected exactly one listed app with id $installedAppId but found $($matchingApps.Count)."
    }

    Write-Host '[8/12] Create Runtime session'
    $session = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/runtime-session" `
        -Headers $authHeaders `
        -Body @{} `
        -Context 'Runtime session creation'

    $runtimeToken = [string]$session.token
    if ($runtimeToken -notmatch '^[A-Za-z0-9_-]{32,64}$') {
        throw 'Runtime session returned an invalid token.'
    }
    if ([int]$session.expires_in -le 0 -or [int]$session.expires_in -gt 600) {
        throw "Runtime session returned invalid expires_in: $($session.expires_in)"
    }

    Write-Host '[9/12] Runtime state POST / GET / DELETE'
    $stateKey = 'smoke.value'
    $stateValue = @{
        run_id = $runId
        message = 'わん'
    }
    $stateUri = "$base/hosted/runtime/$runtimeToken/state/$stateKey"

    $stored = Invoke-JsonApi `
        -Method POST `
        -Uri $stateUri `
        -Headers $publicHeaders `
        -Body @{ value = $stateValue } `
        -Context 'Runtime state POST'
    if ($stored.key -ne $stateKey -or $stored.value.run_id -ne $runId -or $stored.value.message -ne 'わん') {
        throw 'Runtime state POST returned a different value than was written.'
    }

    $loaded = Invoke-JsonApi -Method GET -Uri $stateUri -Headers $publicHeaders -Body $null -Context 'Runtime state GET'
    if ($loaded.key -ne $stateKey -or $loaded.value.run_id -ne $runId -or $loaded.value.message -ne 'わん') {
        throw 'Runtime state GET returned a different value than was written.'
    }

    Invoke-NoContentDelete -Uri $stateUri -Headers $publicHeaders -Context 'Runtime state DELETE'

    Write-Host '[10/12] Fork app and verify listing'
    $forkTitle = "Hosted E2E fork $runId"
    $forked = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/fork" `
        -Headers $authHeaders `
        -Body @{ title = $forkTitle } `
        -Context 'Hosted app fork'

    $forkedAppId = [string]$forked.app_id
    Assert-HexId -Value $forkedAppId -Name 'Forked app_id'
    if ($forked.group_id -ne $groupId -or $forked.source_kind -ne 'fork' -or $forked.parent_app_id -ne $installedAppId -or -not [bool]$forked.editable) {
        throw "Forked app response is invalid. app_id=$forkedAppId"
    }
    $appsAfterFork = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/apps" -Headers $authHeaders -Body $null -Context 'Hosted app listing after fork'
    foreach ($expectedAppId in @($installedAppId, $forkedAppId)) {
        $count = @($appsAfterFork.apps | Where-Object { $_.app_id -eq $expectedAppId }).Count
        if ($count -ne 1) {
            throw "Expected app $expectedAppId exactly once after fork, found $count."
        }
    }

    Write-Host '[11/12] Delete fork and installed app'
    Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId" -Headers $authHeaders -Context 'Fork deletion'
    $forkedAppId = $null
    Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" -Headers $authHeaders -Context 'Installed app deletion'
    $installedAppId = $null

    $appsAfterDelete = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/apps" -Headers $authHeaders -Body $null -Context 'Hosted app listing after deletion'
    if (@($appsAfterDelete.apps).Count -ne 0) {
        throw "Expected no apps after cleanup but found $(@($appsAfterDelete.apps).Count)."
    }

    Write-Host '[12/12] Delete group and verify it disappeared'
    Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId" -Headers $authHeaders -Context 'Hosted group deletion'
    $deletedGroupId = $groupId
    $groupId = $null

    $groupsAfterDelete = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups" -Headers $authHeaders -Body $null -Context 'Hosted group listing after deletion'
    $remaining = @($groupsAfterDelete.groups | Where-Object { $_.group_id -eq $deletedGroupId })
    if ($remaining.Count -ne 0) {
        throw "Deleted group $deletedGroupId is still listed."
    }

    Write-Host ''
    Write-Host 'Hosted AWS smoke test passed.'
    Write-Host 'Verified: /hosted/me -> group -> builtin -> Runtime POST/GET/DELETE -> fork -> app delete -> group delete.'
}
finally {
    $login = $null
    $securePassword = $null
    $password = $null
    $accessToken = $null
    $runtimeToken = $null
    $authHeaders = $null
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }

    if ($null -ne $forkedAppId -or $null -ne $installedAppId -or $null -ne $groupId) {
        Write-Warning 'The smoke test stopped before cleanup completed. Test resources may remain for diagnosis.'
        if ($null -ne $groupId) {
            Write-Warning "group_id=$groupId"
        }
        if ($null -ne $installedAppId) {
            Write-Warning "installed_app_id=$installedAppId"
        }
        if ($null -ne $forkedAppId) {
            Write-Warning "forked_app_id=$forkedAppId"
        }
    }
}
