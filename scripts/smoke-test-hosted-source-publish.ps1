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

function New-SourceZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $index = $archive.CreateEntry('index.html')
            $writer = [System.IO.StreamWriter]::new($index.Open(), [System.Text.UTF8Encoding]::new($false))
            try {
                $writer.Write("<!doctype html><meta charset=`"utf-8`"><h1>$Marker</h1><script src=`"assets/app.js`"></script>")
            }
            finally {
                $writer.Dispose()
            }

            $script = $archive.CreateEntry('assets/app.js')
            $writer = [System.IO.StreamWriter]::new($script.Open(), [System.Text.UTF8Encoding]::new($false))
            try {
                $writer.Write("document.body.dataset.smoke = '$Marker';")
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-ZipUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedStatus,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $response = Invoke-WebRequest `
        -Method Post `
        -Uri $Uri `
        -Headers $Headers `
        -ContentType 'application/zip' `
        -InFile $ZipPath `
        -TimeoutSec 20 `
        -SkipHttpErrorCheck
    if ([int]$response.StatusCode -ne $ExpectedStatus) {
        throw "$Context returned HTTP $([int]$response.StatusCode); expected $ExpectedStatus. Body=$($response.Content)"
    }
    return $response
}

$baseUri = [Uri]$HostedApiBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne 'https' -or $baseUri.AbsolutePath -ne '/') {
    throw 'HostedApiBaseUrl must be an absolute HTTPS origin without a path.'
}
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('minapp-hosted-source-' + [Guid]::NewGuid().ToString('N'))
$tempRoot = [System.IO.Path]::GetFullPath($tempRoot)
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $tempRoot.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary smoke directory escaped the system temporary directory.'
}
[void](New-Item -ItemType Directory -Path $tempRoot)

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
    Write-Host '[1/12] Verify tenant and current Hosted legal versions'
    $tenant = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
    if ($tenant.tenant_id -ne $ExpectedTenantId) {
        throw "Tenant mismatch. Expected '$ExpectedTenantId', received '$($tenant.tenant_id)'."
    }
    $legal = Invoke-JsonApi -Method GET -Uri "$base/hosted/legal" -Headers $publicHeaders -Body $null -Context 'Hosted legal'

    Write-Host '[2/12] Register and authenticate temporary owner and member'
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $ownerLogin = "sourcesmokeowner$suffix"
    $memberLogin = "sourcesmokemember$suffix"
    $ownerPassword = 'T9' + [Guid]::NewGuid().ToString('N')
    $memberPassword = 'T9' + [Guid]::NewGuid().ToString('N')
    foreach ($account in @(
            @{ Login = $ownerLogin; Password = $ownerPassword; Kind = 'owner' },
            @{ Login = $memberLogin; Password = $memberPassword; Kind = 'member' }
        )) {
        $registration = Invoke-JsonApi `
            -Method POST `
            -Uri "$base/hosted/register" `
            -Headers $publicHeaders `
            -Body @{
                login_id         = $account.Login
                password         = $account.Password
                terms_version    = [string]$legal.terms.version
                privacy_version  = [string]$legal.privacy.version
                terms_accepted   = $true
                privacy_accepted = $true
            } `
            -Context "Temporary $($account.Kind) registration"
        if ($account.Kind -eq 'owner') { $ownerCreated = $true } else { $memberCreated = $true }
    }
    $ownerLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $ownerLogin; password = $ownerPassword } -Context 'Owner login'
    $memberLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $memberLogin; password = $memberPassword } -Context 'Member login'
    $ownerHeaders = @{ Authorization = "Bearer $($ownerLoginResult.access_token)"; Accept = 'application/json' }
    $memberHeaders = @{ Authorization = "Bearer $($memberLoginResult.access_token)"; Accept = 'application/json' }

    Write-Host '[3/12] Create group and add active member'
    $group = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups" -Headers $ownerHeaders -Body @{ name = "source-smoke-$suffix" } -Context 'Group creation'
    $groupId = [string]$group.group_id
    $invite = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/invite" -Headers $ownerHeaders -Body @{} -Context 'Invite creation'
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/join" -Headers $memberHeaders -Body @{ code = [string]$invite.code } -Context 'Member join')
    $memberJoined = $true

    Write-Host '[4/12] Install built-in and fork its real source'
    $installed = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/install" -Headers $ownerHeaders -Body @{ builtin_id = $BuiltinId } -Context 'Built-in installation'
    $installedAppId = [string]$installed.app_id
    $forked = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/fork" -Headers $ownerHeaders -Body @{ title = "source smoke fork $suffix" } -Context 'Source fork'
    $forkedAppId = [string]$forked.app_id
    if ([int]$forked.source_revision -ne 1 -or -not [bool]$forked.editable) {
        throw 'Fork did not return editable source revision 1.'
    }

    Write-Host '[5/12] Download source ZIP and verify revision headers'
    $downloadPath = Join-Path $tempRoot 'download.zip'
    $download = Invoke-WebRequest -Method Get -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/source" -Headers $ownerHeaders -OutFile $downloadPath -PassThru -TimeoutSec 20
    if ([int]$download.StatusCode -ne 200 -or [string]$download.Headers['x-minapp-source-revision'] -ne '1') {
        throw 'Source download did not return HTTP 200 and revision 1.'
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, (Join-Path $tempRoot 'downloaded'))
    if (-not (Test-Path (Join-Path $tempRoot 'downloaded/index.html') -PathType Leaf)) {
        throw 'Forked source ZIP does not contain root index.html.'
    }

    Write-Host '[6/12] Update validated ZIP and reject stale revision'
    $publishedMarker = "published-$suffix"
    $draftMarker = "draft-$suffix"
    $publishedZip = Join-Path $tempRoot 'published.zip'
    $draftZip = Join-Path $tempRoot 'draft.zip'
    New-SourceZip -Path $publishedZip -Marker $publishedMarker
    New-SourceZip -Path $draftZip -Marker $draftMarker
    $updatedResponse = Invoke-ZipUpdate -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/source?revision=1" -Headers $ownerHeaders -ZipPath $publishedZip -ExpectedStatus 200 -Context 'Source revision 2 update'
    $updated = $updatedResponse.Content | ConvertFrom-Json
    if ([int]$updated.revision -ne 2) { throw 'Source update did not advance to revision 2.' }
    [void](Invoke-ZipUpdate -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/source?revision=1" -Headers $ownerHeaders -ZipPath $publishedZip -ExpectedStatus 409 -Context 'Stale source update')

    Write-Host '[7/12] Publish revision 2 as immutable version 1'
    $published = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/publish" -Headers $ownerHeaders -Body @{ revision = 2 } -Context 'Publish'
    if ([int]$published.published_version -ne 1 -or [int]$published.source_revision -ne 2) {
        throw 'Publish did not create version 1 from source revision 2.'
    }

    Write-Host '[8/12] Change draft after publish'
    [void](Invoke-ZipUpdate -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/source?revision=2" -Headers $ownerHeaders -ZipPath $draftZip -ExpectedStatus 200 -Context 'Post-publish draft update')

    Write-Host '[9/12] Create member-scoped content session without child credentials'
    $session = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/published-session" -Headers $memberHeaders -Body @{} -Context 'Published session'
    $sessionJson = $session | ConvertTo-Json -Depth 10 -Compress
    if ($sessionJson -match '(?i)access_token|refresh_token|aws_access_key|authorization') {
        throw 'Published session leaked a parent or AWS credential field.'
    }
    if ([string]$session.content_path -notmatch '^/hosted/content/[A-Za-z0-9_-]{32,128}/index\.html$') {
        throw 'Published session returned an invalid scoped content path.'
    }

    Write-Host '[10/12] Fetch published content without Authorization and prove immutability'
    $content = Invoke-WebRequest -Method Get -Uri "$base$($session.content_path)" -TimeoutSec 20
    if ([int]$content.StatusCode -ne 200 -or [string]$content.Headers['x-content-type-options'] -ne 'nosniff') {
        throw 'Published content response is missing required security headers.'
    }
    if ([string]$content.Content -notmatch [regex]::Escape($publishedMarker) -or [string]$content.Content -match [regex]::Escape($draftMarker)) {
        throw 'Published content changed after the draft was edited.'
    }

    Write-Host '[11/12] Delete fork and verify its content session is revoked by metadata authorization'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId" -Headers $ownerHeaders -Context 'Fork deletion')
    $forkedAppId = $null
    $revoked = Invoke-WebRequest -Method Get -Uri "$base$($session.content_path)" -TimeoutSec 20 -SkipHttpErrorCheck
    if ([int]$revoked.StatusCode -ne 404) {
        throw "Deleted app content returned HTTP $([int]$revoked.StatusCode); expected 404."
    }

    Write-Host '[12/12] Clean up built-in, membership, group, and temporary accounts'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" -Headers $ownerHeaders -Context 'Built-in deletion')
    $installedAppId = $null
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/membership" -Headers $memberHeaders -Context 'Member leave')
    $memberJoined = $false
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
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if (-not $completed) {
    throw 'Hosted source/publish smoke did not complete.'
}

Write-Host ''
Write-Host 'Hosted source/publish AWS smoke test passed.'
Write-Host 'Verified: real built-in copy -> edit -> stale rejection -> immutable publish -> active-member delivery -> cleanup.'
