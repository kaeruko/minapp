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
    [ValidatePattern('^[a-z]{2}-[a-z]+-\d_[A-Za-z0-9]+$')]
    [string]$UserPoolId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]{3,255}$')]
    [string]$DataTableName
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

function Assert-RecoveryCode {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Value -notmatch '^(?:[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-){4}[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$') {
        throw "$Name has an invalid format."
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
        [ValidateSet('GET', 'POST', 'DELETE')]
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

function New-RandomPassword {
    return 'Z9' + [Guid]::NewGuid().ToString('N')
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
        return $null
    }

    try {
        return $text | ConvertFrom-Json
    }
    catch {
        throw "$Context returned non-JSON output: $text"
    }
}

function Get-CognitoSubject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LoginId
    )

    $user = Invoke-AwsJson `
        -Arguments @('cognito-idp', 'admin-get-user', '--user-pool-id', $UserPoolId, '--username', $LoginId) `
        -Context "Cognito admin-get-user for $LoginId"

    $subRows = @($user.UserAttributes | Where-Object { $_.Name -eq 'sub' })
    if ($subRows.Count -ne 1) {
        throw "Cognito user $LoginId must have exactly one sub attribute."
    }
    $subject = [string]$subRows[0].Value
    if ($subject -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "Cognito user $LoginId has an invalid sub attribute."
    }
    return $subject
}

function Assert-CognitoUserMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LoginId
    )

    $arguments = @(
        'cognito-idp', 'admin-get-user',
        '--user-pool-id', $UserPoolId,
        '--username', $LoginId,
        '--profile', $AwsProfile,
        '--region', $AwsRegion,
        '--output', 'json',
        '--no-cli-pager'
    )
    $output = @(& aws @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"

    if ($exitCode -eq 0) {
        throw "Cognito user $LoginId still exists after account deletion."
    }
    if ($text -notmatch 'UserNotFoundException') {
        throw "Cognito verification for $LoginId failed for an unexpected reason: $text"
    }
}

function Get-DynamoProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pk,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $key = "pk={S=$Pk},sk={S=PROFILE}"
    return Invoke-AwsJson `
        -Arguments @(
            'dynamodb', 'get-item',
            '--table-name', $DataTableName,
            '--key', $key,
            '--consistent-read'
        ) `
        -Context $Context
}

function Assert-DynamoProfilePresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pk,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $response = Get-DynamoProfile -Pk $Pk -Context $Context
    if ($null -eq $response -or $null -eq $response.PSObject.Properties['Item']) {
        throw "$Context did not find the expected DynamoDB profile."
    }
}

function Assert-DynamoProfileMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pk,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $response = Get-DynamoProfile -Pk $Pk -Context $Context
    if ($null -ne $response -and $null -ne $response.PSObject.Properties['Item']) {
        throw "$Context found a DynamoDB profile that should have been deleted."
    }
}

$baseUri = Get-StrictHttpsBaseUri -Value $HostedApiBaseUrl -Name 'HostedApiBaseUrl'
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }

$ownerLoginId = $null
$ownerUserId = $null
$ownerAuthSubject = $null
$ownerPassword1 = $null
$ownerPassword2 = $null
$ownerPassword3 = $null
$ownerRecovery1 = $null
$ownerRecovery2 = $null
$ownerRecovery3 = $null
$ownerRecovery4 = $null
$ownerAccessToken = $null
$ownerHeaders = $null
$ownerExists = $false

$transfereeLoginId = $null
$transfereeUserId = $null
$transfereeAuthSubject = $null
$transfereePassword = $null
$transfereeAccessToken = $null
$transfereeHeaders = $null
$transfereeExists = $false

$groupId = $null

try {
    Write-Host '[1/18] Verify Hosted health and tenant identity'
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

    Write-Host '[2/18] Verify AWS account and Hosted resources'
    $null = Get-Command aws -ErrorAction Stop
    if (-not $UserPoolId.StartsWith("${AwsRegion}_", [System.StringComparison]::Ordinal)) {
        throw "UserPoolId '$UserPoolId' does not belong to region '$AwsRegion'."
    }

    $identity = Invoke-AwsJson -Arguments @('sts', 'get-caller-identity') -Context 'AWS caller identity'
    if ([string]$identity.Account -ne $ExpectedAwsAccountId) {
        throw "AWS account mismatch. Expected $ExpectedAwsAccountId but received $($identity.Account)."
    }

    $pool = Invoke-AwsJson `
        -Arguments @('cognito-idp', 'describe-user-pool', '--user-pool-id', $UserPoolId) `
        -Context 'Hosted Cognito user pool lookup'
    if ([string]$pool.UserPool.Id -ne $UserPoolId) {
        throw 'Hosted Cognito user pool lookup returned a different pool.'
    }

    $table = Invoke-AwsJson `
        -Arguments @('dynamodb', 'describe-table', '--table-name', $DataTableName) `
        -Context 'Hosted DynamoDB data table lookup'
    if ([string]$table.Table.TableName -ne $DataTableName) {
        throw 'Hosted DynamoDB lookup returned a different table.'
    }

    Write-Host '[3/18] Register lifecycle owner and verify backing records exist'
    $ownerLoginId = 'lifea' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $ownerPassword1 = New-RandomPassword
    $ownerRegistration = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; password = $ownerPassword1 } `
        -Context 'Lifecycle owner registration'
    $ownerExists = $true
    $ownerUserId = [string]$ownerRegistration.user_id
    Assert-HexId -Value $ownerUserId -Name 'Lifecycle owner user_id'
    if ($ownerRegistration.login_id -ne $ownerLoginId -or $ownerRegistration.role -ne 'user' -or $ownerRegistration.status -ne 'active') {
        throw 'Lifecycle owner registration returned an invalid user.'
    }
    $ownerRecovery1 = [string]$ownerRegistration.recovery_code
    Assert-RecoveryCode -Value $ownerRecovery1 -Name 'Initial recovery code'
    $ownerAuthSubject = Get-CognitoSubject -LoginId $ownerLoginId
    Assert-DynamoProfilePresent -Pk "USER#$ownerUserId" -Context 'Lifecycle owner USER profile precondition'
    Assert-DynamoProfilePresent -Pk "AUTH#$ownerAuthSubject" -Context 'Lifecycle owner AUTH profile precondition'
    $ownerRegistration = $null

    Write-Host '[4/18] Recover password with initial recovery code'
    $ownerPassword2 = New-RandomPassword
    $recovered1 = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; recovery_code = $ownerRecovery1; new_password = $ownerPassword2 } `
        -Context 'Initial recovery'
    if ($recovered1.login_id -ne $ownerLoginId) {
        throw 'Initial recovery returned a different login_id.'
    }
    $ownerRecovery2 = [string]$recovered1.recovery_code
    Assert-RecoveryCode -Value $ownerRecovery2 -Name 'Recovery-rotated code'
    if ($ownerRecovery2 -eq $ownerRecovery1) {
        throw 'Recovery did not rotate the recovery code.'
    }
    $recovered1 = $null

    Write-Host '[5/18] Verify old password and old recovery code are rejected'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; password = $ownerPassword1 } `
        -ExpectedStatus 401 `
        -Context 'Old password rejection'

    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; recovery_code = $ownerRecovery1; new_password = (New-RandomPassword) } `
        -ExpectedStatus 401 `
        -Context 'Old recovery code rejection after recovery'

    Write-Host '[6/18] Login and rotate recovery code manually'
    $ownerAccessToken = Invoke-HostedLogin `
        -Base $base `
        -PublicHeaders $publicHeaders `
        -LoginId $ownerLoginId `
        -Password $ownerPassword2 `
        -Context 'Lifecycle owner login after recovery'
    $ownerHeaders = New-AuthenticatedHeaders -AccessToken $ownerAccessToken

    $manualRotation = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/recovery-code" `
        -Headers $ownerHeaders `
        -Body @{} `
        -Context 'Manual recovery code rotation'
    $ownerRecovery3 = [string]$manualRotation.recovery_code
    Assert-RecoveryCode -Value $ownerRecovery3 -Name 'Manually rotated recovery code'
    if ($ownerRecovery3 -eq $ownerRecovery2) {
        throw 'Manual recovery-code rotation returned the previous code.'
    }
    $manualRotation = $null

    Write-Host '[7/18] Verify manual rotation and recover with the new code'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; recovery_code = $ownerRecovery2; new_password = (New-RandomPassword) } `
        -ExpectedStatus 401 `
        -Context 'Pre-manual-rotation recovery code rejection'

    $ownerPassword3 = New-RandomPassword
    $recovered2 = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; recovery_code = $ownerRecovery3; new_password = $ownerPassword3 } `
        -Context 'Recovery with manually rotated code'
    $ownerRecovery4 = [string]$recovered2.recovery_code
    Assert-RecoveryCode -Value $ownerRecovery4 -Name 'Recovery code after manual-rotation recovery'
    if ($ownerRecovery4 -eq $ownerRecovery3) {
        throw 'Recovery with the manually rotated code did not rotate again.'
    }
    $recovered2 = $null

    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; recovery_code = $ownerRecovery3; new_password = (New-RandomPassword) } `
        -ExpectedStatus 401 `
        -Context 'Consumed manually rotated recovery code rejection'

    $ownerAccessToken = Invoke-HostedLogin `
        -Base $base `
        -PublicHeaders $publicHeaders `
        -LoginId $ownerLoginId `
        -Password $ownerPassword3 `
        -Context 'Lifecycle owner login after second recovery'
    $ownerHeaders = New-AuthenticatedHeaders -AccessToken $ownerAccessToken

    Write-Host '[8/18] Create owned group'
    $groupName = 'Hosted lifecycle E2E ' + [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $group = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups" `
        -Headers $ownerHeaders `
        -Body @{ name = $groupName } `
        -Context 'Lifecycle group creation'
    $groupId = [string]$group.group_id
    Assert-HexId -Value $groupId -Name 'Lifecycle group_id'
    if ($group.role -ne 'owner' -or $group.status -ne 'active') {
        throw 'Lifecycle group did not make the lifecycle user owner.'
    }
    Write-Host "  group_id=$groupId"

    Write-Host '[9/18] Verify group owner account deletion is rejected'
    Assert-HttpFailure `
        -Method DELETE `
        -Uri "$base/hosted/account" `
        -Headers $ownerHeaders `
        -Body $null `
        -ExpectedStatus 409 `
        -Context 'Owned-group account deletion rejection'

    Write-Host '[10/18] Register transferee and verify backing records exist'
    $transfereeLoginId = 'lifeb' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $transfereePassword = New-RandomPassword
    $transfereeRegistration = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body @{ login_id = $transfereeLoginId; password = $transfereePassword } `
        -Context 'Transferee registration'
    $transfereeExists = $true
    $transfereeUserId = [string]$transfereeRegistration.user_id
    Assert-HexId -Value $transfereeUserId -Name 'Transferee user_id'
    if ($transfereeRegistration.login_id -ne $transfereeLoginId -or $transfereeRegistration.role -ne 'user' -or $transfereeRegistration.status -ne 'active') {
        throw 'Transferee registration returned an invalid user.'
    }
    Assert-RecoveryCode -Value ([string]$transfereeRegistration.recovery_code) -Name 'Transferee recovery code'
    $transfereeAuthSubject = Get-CognitoSubject -LoginId $transfereeLoginId
    Assert-DynamoProfilePresent -Pk "USER#$transfereeUserId" -Context 'Transferee USER profile precondition'
    Assert-DynamoProfilePresent -Pk "AUTH#$transfereeAuthSubject" -Context 'Transferee AUTH profile precondition'
    $transfereeRegistration = $null

    $transfereeAccessToken = Invoke-HostedLogin `
        -Base $base `
        -PublicHeaders $publicHeaders `
        -LoginId $transfereeLoginId `
        -Password $transfereePassword `
        -Context 'Transferee login'
    $transfereeHeaders = New-AuthenticatedHeaders -AccessToken $transfereeAccessToken

    Write-Host '[11/18] Invite transferee into the group'
    $invite = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/invite" `
        -Headers $ownerHeaders `
        -Body @{} `
        -Context 'Lifecycle group invite creation'
    $inviteCode = [string]$invite.code
    if ($inviteCode -notmatch '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$') {
        throw 'Lifecycle invite returned an invalid code.'
    }

    $joined = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/join" `
        -Headers $transfereeHeaders `
        -Body @{ code = $inviteCode } `
        -Context 'Transferee join'
    if ($joined.group_id -ne $groupId -or $joined.role -ne 'member' -or $joined.status -ne 'active') {
        throw 'Transferee join returned an invalid membership.'
    }

    Write-Host '[12/18] Transfer ownership and verify role swap'
    $transfer = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/groups/$groupId/owner" `
        -Headers $ownerHeaders `
        -Body @{ user_id = $transfereeUserId } `
        -Context 'Ownership transfer'
    if ($transfer.group_id -ne $groupId -or $transfer.owner_user_id -ne $transfereeUserId) {
        throw 'Ownership transfer returned an invalid result.'
    }

    $membersAfterTransfer = Invoke-JsonApi `
        -Method GET `
        -Uri "$base/hosted/groups/$groupId/members" `
        -Headers $transfereeHeaders `
        -Body $null `
        -Context 'Membership listing after ownership transfer'
    if (@($membersAfterTransfer.members | Where-Object { $_.user_id -eq $ownerUserId -and $_.role -eq 'member' }).Count -ne 1) {
        throw 'Old owner did not become a member after ownership transfer.'
    }
    if (@($membersAfterTransfer.members | Where-Object { $_.user_id -eq $transfereeUserId -and $_.role -eq 'owner' }).Count -ne 1) {
        throw 'Transferee did not become owner after ownership transfer.'
    }

    Write-Host '[13/18] Delete old owner account after transfer'
    Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $ownerHeaders -Context 'Old owner account deletion'
    $ownerExists = $false

    Write-Host '[14/18] Verify old owner Cognito, DynamoDB, membership, and login cleanup'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $ownerLoginId; password = $ownerPassword3 } `
        -ExpectedStatus 401 `
        -Context 'Deleted old owner login rejection'
    Assert-CognitoUserMissing -LoginId $ownerLoginId
    Assert-DynamoProfileMissing -Pk "USER#$ownerUserId" -Context 'Deleted old owner USER profile cleanup'
    Assert-DynamoProfileMissing -Pk "AUTH#$ownerAuthSubject" -Context 'Deleted old owner AUTH profile cleanup'

    $membersAfterOwnerDelete = Invoke-JsonApi `
        -Method GET `
        -Uri "$base/hosted/groups/$groupId/members" `
        -Headers $transfereeHeaders `
        -Body $null `
        -Context 'Membership listing after old owner account deletion'
    if (@($membersAfterOwnerDelete.members | Where-Object { $_.user_id -eq $ownerUserId }).Count -ne 0) {
        throw 'Deleted old owner is still present in group membership.'
    }
    if (@($membersAfterOwnerDelete.members | Where-Object { $_.user_id -eq $transfereeUserId -and $_.role -eq 'owner' }).Count -ne 1) {
        throw 'Transferee is not the sole expected owner after old owner account deletion.'
    }

    Write-Host '[15/18] New owner deletes group'
    Invoke-NoContentDelete -Uri "$base/hosted/groups/$groupId" -Headers $transfereeHeaders -Context 'Lifecycle group deletion'
    $groupId = $null

    Write-Host '[16/18] Delete transferee account'
    Invoke-NoContentDelete -Uri "$base/hosted/account" -Headers $transfereeHeaders -Context 'Transferee account deletion'
    $transfereeExists = $false

    Write-Host '[17/18] Verify transferee Cognito, DynamoDB, and login cleanup'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $transfereeLoginId; password = $transfereePassword } `
        -ExpectedStatus 401 `
        -Context 'Deleted transferee login rejection'
    Assert-CognitoUserMissing -LoginId $transfereeLoginId
    Assert-DynamoProfileMissing -Pk "USER#$transfereeUserId" -Context 'Deleted transferee USER profile cleanup'
    Assert-DynamoProfileMissing -Pk "AUTH#$transfereeAuthSubject" -Context 'Deleted transferee AUTH profile cleanup'

    Write-Host '[18/18] Account lifecycle smoke test complete'
    Write-Host ''
    Write-Host 'Hosted account lifecycle AWS smoke test passed.'
    Write-Host 'Verified: recovery -> recovery-code rotation -> stale-code rejection -> owner delete rejection -> ownership transfer -> account deletion -> Cognito/DynamoDB cleanup.'
}
finally {
    $ownerPassword1 = $null
    $ownerPassword2 = $null
    $ownerPassword3 = $null
    $ownerRecovery1 = $null
    $ownerRecovery2 = $null
    $ownerRecovery3 = $null
    $ownerRecovery4 = $null
    $ownerAccessToken = $null
    $ownerHeaders = $null
    $transfereePassword = $null
    $transfereeAccessToken = $null
    $transfereeHeaders = $null

    if ($ownerExists -or $transfereeExists -or $null -ne $groupId) {
        Write-Warning 'The account lifecycle smoke test stopped before cleanup completed. Temporary resources may remain for diagnosis.'
        if ($ownerExists -and $null -ne $ownerLoginId) {
            Write-Warning "lifecycle_owner_login_id=$ownerLoginId"
        }
        if ($null -ne $ownerUserId) {
            Write-Warning "lifecycle_owner_user_id=$ownerUserId"
        }
        if ($transfereeExists -and $null -ne $transfereeLoginId) {
            Write-Warning "transferee_login_id=$transfereeLoginId"
        }
        if ($null -ne $transfereeUserId) {
            Write-Warning "transferee_user_id=$transfereeUserId"
        }
        if ($null -ne $groupId) {
            Write-Warning "group_id=$groupId"
        }
        Write-Warning 'Passwords and recovery codes are intentionally not printed.'
    }
}
