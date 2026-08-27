param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,31}$')]
    [string]$OwnerLoginId,

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

function Assert-HttpFailure {
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
        [int]$ExpectedStatus,

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
        $response = Invoke-WebRequest @parameters
    }
    catch {
        if ($null -eq $_.Exception.Response) {
            throw "$Context failed without an HTTP response: $($_.Exception.Message)"
        }
        $actualStatus = [int]$_.Exception.Response.StatusCode
        if ($actualStatus -ne $ExpectedStatus) {
            throw "$Context returned HTTP $actualStatus; expected HTTP $ExpectedStatus."
        }
        return
    }

    throw "$Context unexpectedly succeeded with HTTP $([int]$response.StatusCode); expected HTTP $ExpectedStatus."
}

function New-AuthenticatedHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        throw 'Access token must not be empty.'
    }
    return @{
        Accept = 'application/json'
        Authorization = "Bearer $AccessToken"
    }
}

function Invoke-HostedLogin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$PublicHeaders,

        [Parameter(Mandatory = $true)]
        [string]$LoginId,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $login = Invoke-JsonApi `
        -Method POST `
        -Uri "$Base/auth/login" `
        -Headers $PublicHeaders `
        -Body @{ login_id = $LoginId; password = $Password } `
        -Context $Context

    if ($login.state -ne 'authenticated') {
        throw "$Context returned unsupported state: $($login.state)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$login.access_token)) {
        throw "$Context returned no access token."
    }
    return [string]$login.access_token
}

$baseUri = Get-StrictHttpsBaseUri -Value $HostedApiBaseUrl -Name 'HostedApiBaseUrl'
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }

$ownerSecurePassword = $null
$ownerPasswordPointer = [IntPtr]::Zero
$ownerPassword = $null
$ownerAccessToken = $null
$ownerHeaders = $null
$ownerUserId = $null
$tempMemberLoginId = $null
$tempMemberPassword = $null
$tempMemberUserId = $null
$tempMemberCreated = $false
$tempMemberAccessToken = $null
$tempMemberHeaders = $null
$groupId = $null
$installedAppId = $null
$inviteCode = $null
$ownerRuntimeToken = $null
$memberRuntimeToken = $null
$sharedStateKey = $null

try {
    Write-Host '[1/16] Verify Hosted health and tenant identity'
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

    Write-Host '[2/16] Login owner and verify /hosted/me'
    $ownerSecurePassword = Read-Host "Password for owner $OwnerLoginId" -AsSecureString
    $ownerPasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ownerSecurePassword)
    $ownerPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ownerPasswordPointer)
    if ([string]::IsNullOrEmpty($ownerPassword)) {
        throw 'Owner password must not be empty.'
    }
    $ownerAccessToken = Invoke-HostedLogin `
        -Base $base `
        -PublicHeaders $publicHeaders `
        -LoginId $OwnerLoginId `
        -Password $ownerPassword `
        -Context 'Owner Hosted login'
    $ownerHeaders = New-AuthenticatedHeaders -AccessToken $ownerAccessToken
    $ownerMe = Invoke-JsonApi -Method GET -Uri "$base/hosted/me" -Headers $ownerHeaders -Body $null -Context 'Owner /hosted/me'
    if ($null -eq $ownerMe.user -or $ownerMe.user.login_id -ne $OwnerLoginId) {
        throw 'Owner /hosted/me returned a different user.'
    }
    $ownerUserId = [string]$ownerMe.user.user_id
    Assert-HexId -Value $ownerUserId -Name 'Owner user_id'

    Write-Host '[3/16] Register and login temporary member'
    $runId = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $tempMemberLoginId = 'e2e2' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $tempMemberPassword = 'T9' + [Guid]::NewGuid().ToString('N')
    $registration = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body @{ login_id = $tempMemberLoginId; password = $tempMemberPassword } `
        -Context 'Temporary member registration'
    $tempMemberCreated = $true
    $tempMemberUserId = [string]$registration.user_id
    Assert-HexId -Value $tempMemberUserId -Name 'Temporary member user_id'
    if ($registration.login_id -ne $tempMemberLoginId -or $registration.role -ne 'user' -or $registration.status -ne 'active') {
        throw 'Temporary member registration returned an invalid user.'
    }
    $registration = $null
    $tempMemberAccessToken = Invoke-HostedLogin `
        -Base $base `
        -PublicHeaders $publicHeaders `
        -LoginId $tempMemberLoginId `
        -Password $tempMemberPassword `
        -Context 'Temporary member Hosted login'
    $tempMemberHeaders = New-AuthenticatedHeaders -AccessToken $tempMemberAccessToken

    Write-Host '[4/16] Create group and install builtin'
    $groupName = "Hosted 2-user E2E $runId"
    $group = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups" `
        -Headers $ownerHeaders `
        -Body @{ name = $groupName } `
        -Context 'Hosted group creation'
    $groupId = [string]$group.group_id
    Assert-HexId -Value $groupId -Name 'Created group_id'
    if ($group.role -ne 'owner' -or $group.status -ne 'active') {
        throw 'Created group did not make the first user owner.'
    }
    Write-Host "  group_id=$groupId"

    $installed = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/install" `
        -Headers $ownerHeaders `
        -Body @{ builtin_id = $BuiltinId } `
        -Context 'Hosted builtin install'
    $installedAppId = [string]$installed.app_id
    Assert-HexId -Value $installedAppId -Name 'Installed app_id'
    if ($installed.group_id -ne $groupId -or $installed.builtin_id -ne $BuiltinId) {
        throw 'Installed app response does not match the test group or builtin.'
    }
    Write-Host "  app_id=$installedAppId"

    Write-Host '[5/16] Owner creates invite and member joins'
    $invite = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/invite" `
        -Headers $ownerHeaders `
        -Body @{} `
        -Context 'Hosted invite creation'
    if ($invite.group_id -ne $groupId -or [int]$invite.valid_for_seconds -le 0) {
        throw 'Invite response is invalid.'
    }
    $inviteCode = [string]$invite.code
    if ($inviteCode -notmatch '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$') {
        throw 'Invite response returned an invalid invite code.'
    }

    $joined = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/join" `
        -Headers $tempMemberHeaders `
        -Body @{ code = $inviteCode } `
        -Context 'Temporary member join'
    if ($joined.group_id -ne $groupId -or $joined.role -ne 'member' -or $joined.status -ne 'active') {
        throw 'Temporary member join returned an invalid membership.'
    }

    Write-Host '[6/16] Verify both memberships and member app visibility'
    $members = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/members" -Headers $ownerHeaders -Body $null -Context 'Hosted member listing'
    $ownerRows = @($members.members | Where-Object { $_.user_id -eq $ownerUserId -and $_.role -eq 'owner' })
    $memberRows = @($members.members | Where-Object { $_.user_id -eq $tempMemberUserId -and $_.role -eq 'member' })
    if ($ownerRows.Count -ne 1 -or $memberRows.Count -ne 1) {
        throw "Expected one owner and one member. ownerRows=$($ownerRows.Count) memberRows=$($memberRows.Count)"
    }

    $memberApps = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/apps" -Headers $tempMemberHeaders -Body $null -Context 'Member app listing'
    if (@($memberApps.apps | Where-Object { $_.app_id -eq $installedAppId }).Count -ne 1) {
        throw 'Temporary member cannot see the installed app.'
    }

    Write-Host '[7/16] Create owner and member Runtime sessions'
    $ownerSession = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/runtime-session" `
        -Headers $ownerHeaders `
        -Body @{} `
        -Context 'Owner Runtime session creation'
    $ownerRuntimeToken = [string]$ownerSession.token
    if ($ownerRuntimeToken -notmatch '^[A-Za-z0-9_-]{32,64}$') {
        throw 'Owner Runtime session returned an invalid token.'
    }

    $memberSession = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/runtime-session" `
        -Headers $tempMemberHeaders `
        -Body @{} `
        -Context 'Member Runtime session creation'
    $memberRuntimeToken = [string]$memberSession.token
    if ($memberRuntimeToken -notmatch '^[A-Za-z0-9_-]{32,64}$') {
        throw 'Member Runtime session returned an invalid token.'
    }

    Write-Host '[8/16] Verify shared Runtime state in both directions'
    $sharedStateKey = 'smoke.shared'
    $ownerStateUri = "$base/hosted/runtime/$ownerRuntimeToken/state/$sharedStateKey"
    $memberStateUri = "$base/hosted/runtime/$memberRuntimeToken/state/$sharedStateKey"

    $ownerWrite = Invoke-JsonApi `
        -Method POST `
        -Uri $ownerStateUri `
        -Headers $publicHeaders `
        -Body @{ value = @{ run_id = $runId; writer = 'owner'; message = 'わん' } } `
        -Context 'Owner Runtime state POST'
    if ($ownerWrite.value.writer -ne 'owner') {
        throw 'Owner Runtime state POST returned an unexpected value.'
    }

    $memberRead = Invoke-JsonApi -Method GET -Uri $memberStateUri -Headers $publicHeaders -Body $null -Context 'Member Runtime state GET'
    if ($memberRead.value.run_id -ne $runId -or $memberRead.value.writer -ne 'owner' -or $memberRead.value.message -ne 'わん') {
        throw 'Member did not read the state written by owner.'
    }

    $memberWrite = Invoke-JsonApi `
        -Method POST `
        -Uri $memberStateUri `
        -Headers $publicHeaders `
        -Body @{ value = @{ run_id = $runId; writer = 'member'; message = 'もふ' } } `
        -Context 'Member Runtime state POST'
    if ($memberWrite.value.writer -ne 'member') {
        throw 'Member Runtime state POST returned an unexpected value.'
    }

    $ownerRead = Invoke-JsonApi -Method GET -Uri $ownerStateUri -Headers $publicHeaders -Body $null -Context 'Owner Runtime state GET after member write'
    if ($ownerRead.value.run_id -ne $runId -or $ownerRead.value.writer -ne 'member' -or $ownerRead.value.message -ne 'もふ') {
        throw 'Owner did not read the state written by member.'
    }

    Write-Host '[9/16] Owner removes member'
    Invoke-NoContentDelete `
        -Uri "$base/hosted/groups/$groupId/members/$tempMemberUserId" `
        -Headers $ownerHeaders `
        -Context 'Temporary member removal'

    Write-Host '[10/16] Verify issued member Runtime token is immediately rejected'
    Assert-HttpFailure `
        -Method GET `
        -Uri $memberStateUri `
        -Headers $publicHeaders `
        -Body $null `
        -ExpectedStatus 403 `
        -Context 'Removed member Runtime token'

    Write-Host '[11/16] Member rejoins for ownership-transfer test'
    $rejoined = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/join" `
        -Headers $tempMemberHeaders `
        -Body @{ code = $inviteCode } `
        -Context 'Temporary member rejoin'
    if ($rejoined.group_id -ne $groupId -or $rejoined.role -ne 'member') {
        throw 'Temporary member rejoin returned an invalid membership.'
    }

    Write-Host '[12/16] Transfer ownership to temporary member'
    $transfer = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/owner" `
        -Headers $ownerHeaders `
        -Body @{ user_id = $tempMemberUserId } `
        -Context 'Hosted ownership transfer'
    if ($transfer.group_id -ne $groupId -or $transfer.owner_user_id -ne $tempMemberUserId) {
        throw 'Ownership transfer response is invalid.'
    }

    $membersAfterTransfer = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups/$groupId/members" -Headers $tempMemberHeaders -Body $null -Context 'Member listing after ownership transfer'
    $newOwnerRows = @($membersAfterTransfer.members | Where-Object { $_.user_id -eq $tempMemberUserId -and $_.role -eq 'owner' })
    $oldOwnerRows = @($membersAfterTransfer.members | Where-Object { $_.user_id -eq $ownerUserId -and $_.role -eq 'member' })
    if ($newOwnerRows.Count -ne 1 -or $oldOwnerRows.Count -ne 1) {
        throw "Ownership roles were not swapped correctly. newOwnerRows=$($newOwnerRows.Count) oldOwnerRows=$($oldOwnerRows.Count)"
    }

    Write-Host '[13/16] Delete shared Runtime state'
    Invoke-NoContentDelete -Uri $ownerStateUri -Headers $publicHeaders -Context 'Shared Runtime state cleanup'
    $sharedStateKey = $null

    Write-Host '[14/16] New owner deletes app and group'
    Invoke-NoContentDelete `
        -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" `
        -Headers $tempMemberHeaders `
        -Context 'Installed app deletion by transferred owner'
    $installedAppId = $null

    Invoke-NoContentDelete `
        -Uri "$base/hosted/groups/$groupId" `
        -Headers $tempMemberHeaders `
        -Context 'Group deletion by transferred owner'
    $deletedGroupId = $groupId
    $groupId = $null
    $inviteCode = $null

    $ownerGroupsAfterDelete = Invoke-JsonApi -Method GET -Uri "$base/hosted/groups" -Headers $ownerHeaders -Body $null -Context 'Old owner group listing after deletion'
    if (@($ownerGroupsAfterDelete.groups | Where-Object { $_.group_id -eq $deletedGroupId }).Count -ne 0) {
        throw "Deleted group $deletedGroupId is still listed for the old owner."
    }

    Write-Host '[15/16] Delete temporary member account'
    Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $tempMemberHeaders -Context 'Temporary member account deletion'
    $tempMemberCreated = $false

    Write-Host '[16/16] Verify temporary member can no longer log in'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $tempMemberLoginId; password = $tempMemberPassword } `
        -ExpectedStatus 401 `
        -Context 'Deleted temporary member login'

    Write-Host ''
    Write-Host 'Hosted two-user AWS smoke test passed.'
    Write-Host 'Verified: invite/join -> member app visibility -> shared Runtime -> removal invalidates issued token -> rejoin -> ownership transfer -> cleanup.'
}
finally {
    $ownerSecurePassword = $null
    $ownerPassword = $null
    $ownerAccessToken = $null
    $ownerHeaders = $null
    $tempMemberPassword = $null
    $tempMemberAccessToken = $null
    $tempMemberHeaders = $null
    $inviteCode = $null
    $ownerRuntimeToken = $null
    $memberRuntimeToken = $null
    if ($ownerPasswordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ownerPasswordPointer)
    }

    if ($tempMemberCreated -or $null -ne $installedAppId -or $null -ne $groupId) {
        Write-Warning 'The two-user smoke test stopped before cleanup completed. Test resources may remain for diagnosis.'
        if ($tempMemberCreated) {
            Write-Warning "temporary_member_login_id=$tempMemberLoginId"
            if ($null -ne $tempMemberUserId) {
                Write-Warning "temporary_member_user_id=$tempMemberUserId"
            }
        }
        if ($null -ne $groupId) {
            Write-Warning "group_id=$groupId"
        }
        if ($null -ne $installedAppId) {
            Write-Warning "installed_app_id=$installedAppId"
        }
    }
}
