param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,63}$')]
    [string]$BuiltinId = 'shiba-game'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
        Method     = $Method
        Uri        = $Uri
        Headers    = $Headers
        TimeoutSec = 20
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

function Invoke-ExpectedJsonError {
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
        [string]$ExpectedError,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $parameters = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = $Headers
        TimeoutSec         = 20
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    $response = Invoke-WebRequest @parameters
    if ([int]$response.StatusCode -ne $ExpectedStatus) {
        throw "$Context returned HTTP $([int]$response.StatusCode); expected $ExpectedStatus. Body=$($response.Content)"
    }
    $payload = $response.Content | ConvertFrom-Json
    if ([string]$payload.error -ne $ExpectedError) {
        throw "$Context returned error '$($payload.error)'; expected '$ExpectedError'."
    }
    return $payload
}

function Invoke-NoContentDelete {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [switch]$BestEffort
    )

    try {
        $response = Invoke-WebRequest -Method Delete -Uri $Uri -Headers $Headers -TimeoutSec 20
        if ([int]$response.StatusCode -ne 204) {
            throw "$Context returned HTTP $([int]$response.StatusCode); expected 204."
        }
        return $true
    }
    catch {
        if ($BestEffort.IsPresent) {
            Write-Warning "$Context cleanup failed: $($_.Exception.Message)"
            return $false
        }
        throw
    }
}

$baseUri = [Uri]$HostedApiBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne 'https' -or $baseUri.AbsolutePath -ne '/') {
    throw 'HostedApiBaseUrl must be an absolute HTTPS origin without a path.'
}
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }
$ownerHeaders = $null
$memberHeaders = $null
$ownerCreated = $false
$memberCreated = $false
$memberJoined = $false
$groupId = $null
$installedAppId = $null
$forkedAppId = $null
$completed = $false

try {
    Write-Host '[1/11] Verify tenant, health, and legal versions'
    $tenant = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
    if ([string]$tenant.tenant_id -ne $ExpectedTenantId) {
        throw "Tenant mismatch. Expected '$ExpectedTenantId', received '$($tenant.tenant_id)'."
    }
    $health = Invoke-JsonApi -Method GET -Uri "$base/hosted/health" -Headers $publicHeaders -Body $null -Context 'Hosted health'
    if ([string]$health.status -ne 'ok') { throw 'Hosted health is not ok.' }
    $legal = Invoke-JsonApi -Method GET -Uri "$base/hosted/legal" -Headers $publicHeaders -Body $null -Context 'Hosted legal'

    Write-Host '[2/11] Register and authenticate temporary owner/member'
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $ownerLogin = "bridgesmokeowner$suffix"
    $memberLogin = "bridgesmokemember$suffix"
    $ownerPassword = 'T9' + [Guid]::NewGuid().ToString('N')
    $memberPassword = 'T9' + [Guid]::NewGuid().ToString('N')

    $ownerRegistration = Invoke-JsonApi -Method POST -Uri "$base/hosted/register" -Headers $publicHeaders -Body @{
        login_id = $ownerLogin
        password = $ownerPassword
        terms_version = [string]$legal.terms.version
        privacy_version = [string]$legal.privacy.version
        terms_accepted = $true
        privacy_accepted = $true
    } -Context 'Owner registration'
    $ownerCreated = $true

    $memberRegistration = Invoke-JsonApi -Method POST -Uri "$base/hosted/register" -Headers $publicHeaders -Body @{
        login_id = $memberLogin
        password = $memberPassword
        terms_version = [string]$legal.terms.version
        privacy_version = [string]$legal.privacy.version
        terms_accepted = $true
        privacy_accepted = $true
    } -Context 'Member registration'
    $memberCreated = $true
    $memberUserId = [string]$memberRegistration.user_id
    if ($memberUserId -notmatch '^[0-9a-f]{32}$') { throw 'Member registration returned an invalid user_id.' }

    $ownerLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $ownerLogin; password = $ownerPassword } -Context 'Owner login'
    $memberLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $memberLogin; password = $memberPassword } -Context 'Member login'
    $ownerHeaders = @{ Authorization = "Bearer $($ownerLoginResult.access_token)"; Accept = 'application/json' }
    $memberHeaders = @{ Authorization = "Bearer $($memberLoginResult.access_token)"; Accept = 'application/json' }

    Write-Host '[3/11] Create group and add active member'
    $group = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups" -Headers $ownerHeaders -Body @{ name = "bridge-smoke-$suffix" } -Context 'Group creation'
    $groupId = [string]$group.group_id
    $invite = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/invite" -Headers $ownerHeaders -Body @{} -Context 'Invite creation'
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/join" -Headers $memberHeaders -Body @{ code = [string]$invite.code } -Context 'Member join')
    $memberJoined = $true

    Write-Host '[4/11] Install, fork, and publish a real Hosted app'
    $installed = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/install" -Headers $ownerHeaders -Body @{ builtin_id = $BuiltinId } -Context 'Built-in installation'
    $installedAppId = [string]$installed.app_id
    $forked = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/fork" -Headers $ownerHeaders -Body @{ title = "bridge smoke $suffix" } -Context 'Fork'
    $forkedAppId = [string]$forked.app_id
    if ([int]$forked.source_revision -ne 1) { throw 'Fork did not start at source revision 1.' }
    $published = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/publish" -Headers $ownerHeaders -Body @{ revision = 1 } -Context 'Publish'
    if ([int]$published.published_version -ne 1) { throw 'Publish did not create version 1.' }

    Write-Host '[5/11] Create integrated launch session as member'
    $launch = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/launch-session" -Headers $memberHeaders -Body @{} -Context 'Launch session'
    $launchJson = $launch | ConvertTo-Json -Depth 20 -Compress
    if ($launchJson -match '(?i)access_token|refresh_token|id_token|aws_access_key|aws_secret|aws_session|authorization') {
        throw 'Launch response leaked a Cognito/AWS credential field.'
    }
    if ([string]$launch.content_path -notmatch '^/hosted/content/[A-Za-z0-9_-]{32,128}/index\.html$') {
        throw 'Launch response returned an invalid content_path.'
    }
    if ([string]$launch.runtime_token -notmatch '^[A-Za-z0-9_-]{32,64}$') {
        throw 'Launch response returned an invalid runtime_token.'
    }
    if ([int]$launch.content_expires_in -ne 600 -or [int]$launch.runtime_expires_in -ne 600) {
        throw 'Launch response did not return the expected 10 minute expiries.'
    }
    $runtimeToken = [string]$launch.runtime_token

    Write-Host '[6/11] Fetch published content without Authorization'
    $content = Invoke-WebRequest -Method Get -Uri "$base$($launch.content_path)" -TimeoutSec 20
    if ([int]$content.StatusCode -ne 200) { throw 'Published launch content was not readable.' }

    Write-Host '[7/11] Exercise Runtime state set/get/delete through the launch token'
    $stateKey = 'bridge_smoke'
    $set = Invoke-JsonApi -Method POST -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Body @{ value = @{ page = 3; marker = $suffix } } -Context 'Runtime set'
    if ([int]$set.value.page -ne 3 -or [string]$set.value.marker -ne $suffix) { throw 'Runtime set returned an unexpected value.' }
    $get = Invoke-JsonApi -Method GET -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Body $null -Context 'Runtime get'
    if ([int]$get.value.page -ne 3 -or [string]$get.value.marker -ne $suffix) { throw 'Runtime get returned an unexpected value.' }
    [void](Invoke-NoContentDelete -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Context 'Runtime state delete')

    Write-Host '[8/11] Prove member removal revokes the existing Runtime capability immediately'
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/runtime/$runtimeToken/state/revocation" -Headers $publicHeaders -Body @{ value = 'before-removal' } -Context 'Pre-removal Runtime set')
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/members/$memberUserId" -Headers $ownerHeaders -Context 'Member removal')
    $memberJoined = $false
    [void](Invoke-ExpectedJsonError -Method GET -Uri "$base/hosted/runtime/$runtimeToken/state/revocation" -Headers $publicHeaders -Body $null -ExpectedStatus 403 -ExpectedError 'forbidden' -Context 'Revoked Runtime capability')

    Write-Host '[9/11] Prove removed member cannot mint a replacement launch session'
    [void](Invoke-ExpectedJsonError -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/launch-session" -Headers $memberHeaders -Body @{} -ExpectedStatus 403 -ExpectedError 'forbidden' -Context 'Removed member relaunch')

    Write-Host '[10/11] Delete Hosted apps and prove the old content capability is dead'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId" -Headers $ownerHeaders -Context 'Fork deletion')
    $forkedAppId = $null
    $oldContent = Invoke-WebRequest -Method Get -Uri "$base$($launch.content_path)" -TimeoutSec 20 -SkipHttpErrorCheck
    if ([int]$oldContent.StatusCode -ne 404) {
        throw "Deleted app content returned HTTP $([int]$oldContent.StatusCode); expected 404."
    }
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" -Headers $ownerHeaders -Context 'Built-in deletion')
    $installedAppId = $null

    Write-Host '[11/11] Clean up group and temporary accounts'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId" -Headers $ownerHeaders -Context 'Group deletion')
    $groupId = $null
    [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $memberHeaders -Context 'Member account deletion')
    $memberCreated = $false
    [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $ownerHeaders -Context 'Owner account deletion')
    $ownerCreated = $false
    $completed = $true
}
finally {
    if ($null -ne $forkedAppId -and $null -ne $groupId -and $null -ne $ownerHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId" -Headers $ownerHeaders -Context 'Fork' -BestEffort)
    }
    if ($null -ne $installedAppId -and $null -ne $groupId -and $null -ne $ownerHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" -Headers $ownerHeaders -Context 'Built-in' -BestEffort)
    }
    if ($memberJoined -and $null -ne $groupId -and $null -ne $memberHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/membership" -Headers $memberHeaders -Context 'Member leave' -BestEffort)
    }
    if ($null -ne $groupId -and $null -ne $ownerHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId" -Headers $ownerHeaders -Context 'Group' -BestEffort)
    }
    if ($memberCreated -and $null -ne $memberHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $memberHeaders -Context 'Member account' -BestEffort)
    }
    if ($ownerCreated -and $null -ne $ownerHeaders) {
        [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $ownerHeaders -Context 'Owner account' -BestEffort)
    }
}

if (-not $completed) {
    throw 'Hosted Runtime bridge smoke did not complete.'
}

Write-Host ''
Write-Host 'Hosted Runtime bridge AWS smoke test passed.'
Write-Host 'Verified: launch -> content -> state set/get/delete -> immediate member revocation -> relaunch denial -> cleanup.'
