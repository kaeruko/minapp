param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{12}$')]
    [string]$ExpectedAwsAccountId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z]{2}-[a-z]+-\d$')]
    [string]$AwsRegion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]{3,255}$')]
    [string]$DataTableName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]{3,255}$')]
    [string]$RuntimeTableName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPoolId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UploadBucketName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PublishedBucketName,

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

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $fullArguments = @($Arguments) + @(
        '--profile', $AwsProfile,
        '--region', $AwsRegion,
        '--output', 'json',
        '--no-cli-pager'
    )
    $output = @(& aws @fullArguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if ($exitCode -ne 0) {
        throw "$Context failed with AWS CLI exit code $exitCode`: $text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Context returned an empty response."
    }
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        throw "$Context returned non-JSON output: $text"
    }
}

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
        $digest = $algorithm.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-CognitoSubject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LoginId,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $user = Invoke-AwsJson `
        -Arguments @('cognito-idp', 'admin-get-user', '--user-pool-id', $UserPoolId, '--username', $LoginId) `
        -Context $Context
    $matches = @($user.UserAttributes | Where-Object { [string]$_.Name -eq 'sub' })
    if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$matches[0].Value)) {
        throw "$Context did not return exactly one Cognito sub attribute."
    }
    return [string]$matches[0].Value
}

function Remove-CapabilityMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HOSTEDCONTENT', 'RUNTIMESESSION')]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [string]$Token,
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [switch]$BestEffort
    )

    try {
        $tokenHash = Get-Sha256Hex -Value $Token
        $key = @{
            pk = @{ S = "$Prefix#$tokenHash" }
            sk = @{ S = 'META' }
        } | ConvertTo-Json -Depth 5 -Compress
        $arguments = @(
            'dynamodb', 'delete-item',
            '--table-name', $DataTableName,
            '--key', $key,
            '--profile', $AwsProfile,
            '--region', $AwsRegion,
            '--no-cli-pager'
        )
        $output = @(& aws @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
            throw "$Context failed with AWS CLI exit code $exitCode`: $text"
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

function Assert-DynamoPartitionEmpty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$Pk,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $values = @{ ':pk' = @{ S = $Pk } } | ConvertTo-Json -Depth 5 -Compress
    $response = Invoke-AwsJson `
        -Arguments @(
            'dynamodb', 'query',
            '--table-name', $TableName,
            '--key-condition-expression', 'pk = :pk',
            '--expression-attribute-values', $values,
            '--consistent-read'
        ) `
        -Context $Context
    if ([int]$response.Count -ne 0) {
        throw "$Context found $($response.Count) residual DynamoDB item(s) for pk '$Pk'."
    }
}

function Assert-CognitoUserMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LoginId,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $filter = "username = `"$LoginId`""
    $response = Invoke-AwsJson `
        -Arguments @('cognito-idp', 'list-users', '--user-pool-id', $UserPoolId, '--filter', $filter) `
        -Context $Context
    if (@($response.Users).Count -ne 0) {
        throw "$Context found a temporary Cognito user that should have been deleted."
    }
}

function Assert-S3PrefixEmpty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $response = Invoke-AwsJson `
        -Arguments @('s3api', 'list-object-versions', '--bucket', $Bucket, '--prefix', $Prefix) `
        -Context $Context
    $versionCount = if ($null -ne $response.PSObject.Properties['Versions']) { @($response.Versions).Count } else { 0 }
    $deleteMarkerCount = if ($null -ne $response.PSObject.Properties['DeleteMarkers']) { @($response.DeleteMarkers).Count } else { 0 }
    if ($versionCount -ne 0 -or $deleteMarkerCount -ne 0) {
        throw "$Context found residual S3 versions=$versionCount deleteMarkers=$deleteMarkerCount for prefix '$Prefix'."
    }
}

$null = Get-Command aws -ErrorAction Stop
$baseUri = [Uri]$HostedApiBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne 'https' -or $baseUri.AbsolutePath -ne '/') {
    throw 'HostedApiBaseUrl must be an absolute HTTPS origin without a path.'
}
if (-not $UserPoolId.StartsWith("${AwsRegion}_", [System.StringComparison]::Ordinal)) {
    throw "UserPoolId '$UserPoolId' does not belong to region '$AwsRegion'."
}

$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }
$ownerHeaders = $null
$memberHeaders = $null
$ownerCreated = $false
$memberCreated = $false
$memberJoined = $false
$groupId = $null
$cleanupGroupId = $null
$installedAppId = $null
$cleanupInstalledAppId = $null
$forkedAppId = $null
$cleanupForkedAppId = $null
$ownerLogin = $null
$memberLogin = $null
$ownerUserId = $null
$memberUserId = $null
$ownerAuthSubject = $null
$memberAuthSubject = $null
$capabilities = [System.Collections.Generic.List[object]]::new()
$flowCompleted = $false

try {
    Write-Host '[1/13] Verify tenant, health, legal versions, and AWS target'
    $tenant = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
    if ([string]$tenant.tenant_id -ne $ExpectedTenantId) {
        throw "Tenant mismatch. Expected '$ExpectedTenantId', received '$($tenant.tenant_id)'."
    }
    $health = Invoke-JsonApi -Method GET -Uri "$base/hosted/health" -Headers $publicHeaders -Body $null -Context 'Hosted health'
    if ([string]$health.status -ne 'ok') { throw 'Hosted health is not ok.' }
    $legal = Invoke-JsonApi -Method GET -Uri "$base/hosted/legal" -Headers $publicHeaders -Body $null -Context 'Hosted legal'
    $identity = Invoke-AwsJson -Arguments @('sts', 'get-caller-identity') -Context 'AWS caller identity'
    if ([string]$identity.Account -ne $ExpectedAwsAccountId) {
        throw "AWS account mismatch. Expected $ExpectedAwsAccountId but received $($identity.Account)."
    }
    foreach ($tableName in @($DataTableName, $RuntimeTableName)) {
        $table = Invoke-AwsJson -Arguments @('dynamodb', 'describe-table', '--table-name', $tableName) -Context "DynamoDB table $tableName"
        if ([string]$table.Table.TableName -ne $tableName -or [string]$table.Table.TableStatus -ne 'ACTIVE') {
            throw "DynamoDB table '$tableName' is not ACTIVE or resolved to a different table."
        }
    }

    Write-Host '[2/13] Register and authenticate temporary owner/member'
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
    $ownerUserId = [string]$ownerRegistration.user_id
    if ($ownerUserId -notmatch '^[0-9a-f]{32}$') { throw 'Owner registration returned an invalid user_id.' }

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

    $ownerAuthSubject = Get-CognitoSubject -LoginId $ownerLogin -Context 'Owner Cognito subject lookup'
    $memberAuthSubject = Get-CognitoSubject -LoginId $memberLogin -Context 'Member Cognito subject lookup'

    $ownerLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $ownerLogin; password = $ownerPassword } -Context 'Owner login'
    $memberLoginResult = Invoke-JsonApi -Method POST -Uri "$base/auth/login" -Headers $publicHeaders -Body @{ login_id = $memberLogin; password = $memberPassword } -Context 'Member login'
    $ownerHeaders = @{ Authorization = "Bearer $($ownerLoginResult.access_token)"; Accept = 'application/json' }
    $memberHeaders = @{ Authorization = "Bearer $($memberLoginResult.access_token)"; Accept = 'application/json' }

    Write-Host '[3/13] Create group and add active member'
    $group = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups" -Headers $ownerHeaders -Body @{ name = "bridge-smoke-$suffix" } -Context 'Group creation'
    $groupId = [string]$group.group_id
    if ($groupId -notmatch '^[0-9a-f]{32}$') { throw 'Group creation returned an invalid group_id.' }
    $cleanupGroupId = $groupId
    $invite = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/invite" -Headers $ownerHeaders -Body @{} -Context 'Invite creation'
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/join" -Headers $memberHeaders -Body @{ code = [string]$invite.code } -Context 'Member join')
    $memberJoined = $true

    Write-Host '[4/13] Install, fork, and publish a real Hosted app'
    $installed = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/install" -Headers $ownerHeaders -Body @{ builtin_id = $BuiltinId } -Context 'Built-in installation'
    $installedAppId = [string]$installed.app_id
    $cleanupInstalledAppId = $installedAppId
    $forked = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$installedAppId/fork" -Headers $ownerHeaders -Body @{ title = "bridge smoke $suffix" } -Context 'Fork'
    $forkedAppId = [string]$forked.app_id
    $cleanupForkedAppId = $forkedAppId
    if ([int]$forked.source_revision -ne 1) { throw 'Fork did not start at source revision 1.' }
    $published = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/publish" -Headers $ownerHeaders -Body @{ revision = 1 } -Context 'Publish'
    if ([int]$published.published_version -ne 1) { throw 'Publish did not create version 1.' }

    Write-Host '[5/13] Create integrated launch session as member'
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
    $contentToken = ([string]$launch.content_path -split '/')[3]
    $runtimeToken = [string]$launch.runtime_token
    $capabilities.Add([pscustomobject]@{ Prefix = 'HOSTEDCONTENT'; Token = $contentToken })
    $capabilities.Add([pscustomobject]@{ Prefix = 'RUNTIMESESSION'; Token = $runtimeToken })

    Write-Host '[6/13] Fetch published content without Authorization'
    $content = Invoke-WebRequest -Method Get -Uri "$base$($launch.content_path)" -TimeoutSec 20
    if ([int]$content.StatusCode -ne 200) { throw 'Published launch content was not readable.' }

    Write-Host '[7/13] Exercise Runtime state set/get/delete through the launch token'
    $stateKey = 'bridge_smoke'
    $set = Invoke-JsonApi -Method POST -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Body @{ value = @{ page = 3; marker = $suffix } } -Context 'Runtime set'
    if ([int]$set.value.page -ne 3 -or [string]$set.value.marker -ne $suffix) { throw 'Runtime set returned an unexpected value.' }
    $get = Invoke-JsonApi -Method GET -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Body $null -Context 'Runtime get'
    if ([int]$get.value.page -ne 3 -or [string]$get.value.marker -ne $suffix) { throw 'Runtime get returned an unexpected value.' }
    [void](Invoke-NoContentDelete -Uri "$base/hosted/runtime/$runtimeToken/state/$stateKey" -Headers $publicHeaders -Context 'Runtime state delete')

    Write-Host '[8/13] Prove member removal revokes the existing Runtime capability immediately'
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/runtime/$runtimeToken/state/revocation" -Headers $publicHeaders -Body @{ value = 'before-removal' } -Context 'Pre-removal Runtime set')
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/members/$memberUserId" -Headers $ownerHeaders -Context 'Member removal')
    $memberJoined = $false
    [void](Invoke-ExpectedJsonError -Method GET -Uri "$base/hosted/runtime/$runtimeToken/state/revocation" -Headers $publicHeaders -Body $null -ExpectedStatus 403 -ExpectedError 'forbidden' -Context 'Revoked Runtime capability')
    [void](Invoke-ExpectedJsonError -Method GET -Uri "$base$($launch.content_path)" -Headers $publicHeaders -Body $null -ExpectedStatus 403 -ExpectedError 'forbidden' -Context 'Revoked published content capability')

    Write-Host '[9/13] Prove removed member cannot relaunch and owner can create an independent scope'
    [void](Invoke-ExpectedJsonError -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/launch-session" -Headers $memberHeaders -Body @{} -ExpectedStatus 403 -ExpectedError 'forbidden' -Context 'Removed member relaunch')
    $ownerLaunch = Invoke-JsonApi -Method POST -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId/launch-session" -Headers $ownerHeaders -Body @{} -Context 'Owner launch before app deletion'
    $ownerContentToken = ([string]$ownerLaunch.content_path -split '/')[3]
    $ownerRuntimeToken = [string]$ownerLaunch.runtime_token
    if ($ownerContentToken -notmatch '^[A-Za-z0-9_-]{32,128}$' -or $ownerRuntimeToken -notmatch '^[A-Za-z0-9_-]{32,64}$') {
        throw 'Owner launch returned an invalid capability.'
    }
    $capabilities.Add([pscustomobject]@{ Prefix = 'HOSTEDCONTENT'; Token = $ownerContentToken })
    $capabilities.Add([pscustomobject]@{ Prefix = 'RUNTIMESESSION'; Token = $ownerRuntimeToken })
    [void](Invoke-JsonApi -Method POST -Uri "$base/hosted/runtime/$ownerRuntimeToken/state/app_delete" -Headers $publicHeaders -Body @{ value = 'before-delete' } -Context 'Owner Runtime precondition')

    Write-Host '[10/13] Delete the app and prove existing content/Runtime capabilities are revoked'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$forkedAppId" -Headers $ownerHeaders -Context 'Fork deletion')
    $forkedAppId = $null
    [void](Invoke-ExpectedJsonError -Method GET -Uri "$base$($ownerLaunch.content_path)" -Headers $publicHeaders -Body $null -ExpectedStatus 404 -ExpectedError 'app_not_found' -Context 'Deleted app published content capability')
    [void](Invoke-ExpectedJsonError -Method GET -Uri "$base/hosted/runtime/$ownerRuntimeToken/state/app_delete" -Headers $publicHeaders -Body $null -ExpectedStatus 404 -ExpectedError 'app_not_found' -Context 'Deleted app Runtime capability')
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId/apps/$installedAppId" -Headers $ownerHeaders -Context 'Built-in deletion')
    $installedAppId = $null

    Write-Host '[11/13] Clean up group and temporary accounts through the public contract'
    [void](Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId" -Headers $ownerHeaders -Context 'Group deletion')
    $groupId = $null
    [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $memberHeaders -Context 'Member account deletion')
    $memberCreated = $false
    [void](Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $ownerHeaders -Context 'Owner account deletion')
    $ownerCreated = $false
    $flowCompleted = $true
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

    foreach ($capability in $capabilities) {
        [void](Remove-CapabilityMetadata `
            -Prefix ([string]$capability.Prefix) `
            -Token ([string]$capability.Token) `
            -Context "Capability metadata $($capability.Prefix)" `
            -BestEffort)
    }
}

if (-not $flowCompleted) {
    throw 'Hosted Runtime bridge smoke did not complete.'
}

Write-Host '[12/13] Verify Cognito and DynamoDB temporary data is physically gone'
Assert-CognitoUserMissing -LoginId $ownerLogin -Context 'Owner Cognito cleanup verification'
Assert-CognitoUserMissing -LoginId $memberLogin -Context 'Member Cognito cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "USER#$ownerUserId" -Context 'Owner USER cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "USER#$memberUserId" -Context 'Member USER cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "AUTH#$ownerAuthSubject" -Context 'Owner AUTH cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "AUTH#$memberAuthSubject" -Context 'Member AUTH cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "GROUP#$cleanupGroupId" -Context 'Group metadata cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "APP#$cleanupInstalledAppId" -Context 'Installed app cleanup verification'
Assert-DynamoPartitionEmpty -TableName $DataTableName -Pk "APP#$cleanupForkedAppId" -Context 'Fork app cleanup verification'
Assert-DynamoPartitionEmpty -TableName $RuntimeTableName -Pk "GROUP#$cleanupGroupId#APP#$cleanupForkedAppId" -Context 'Runtime state cleanup verification'
foreach ($capability in $capabilities) {
    $hash = Get-Sha256Hex -Value ([string]$capability.Token)
    Assert-DynamoPartitionEmpty `
        -TableName $DataTableName `
        -Pk "$($capability.Prefix)#$hash" `
        -Context "Capability cleanup verification $($capability.Prefix)"
}

Write-Host '[13/13] Verify temporary S3 source/published versions are physically gone'
Assert-S3PrefixEmpty -Bucket $UploadBucketName -Prefix "hosted/drafts/$cleanupGroupId/" -Context 'Hosted draft S3 cleanup verification'
Assert-S3PrefixEmpty -Bucket $PublishedBucketName -Prefix "hosted/published/$cleanupGroupId/" -Context 'Hosted published S3 cleanup verification'

Write-Host ''
Write-Host 'Hosted Runtime bridge AWS smoke test passed.'
Write-Host 'Verified: launch -> content -> state -> member revocation -> app revocation -> API cleanup -> Cognito/DynamoDB/S3 physical cleanup.'