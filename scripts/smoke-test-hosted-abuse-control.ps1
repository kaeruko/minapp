param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [string]$AwsRegion,

    [Parameter(Mandatory = $true)]
    [string]$AwsProfile,

    [Parameter(Mandatory = $true)]
    [string]$DataTableName
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

function Invoke-ExpectStatus {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('POST', 'DELETE')]
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
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    $response = Invoke-WebRequest @parameters
    $actualStatus = [int]$response.StatusCode
    if ($actualStatus -ne $ExpectedStatus) {
        throw "$Context returned HTTP $actualStatus; expected HTTP $ExpectedStatus. Body=$($response.Content)"
    }
    return $response
}

$baseUri = [Uri]$HostedApiBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne 'https' -or $baseUri.AbsolutePath -ne '/') {
    throw 'HostedApiBaseUrl must be an absolute HTTPS origin with no path.'
}
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }
$abuseTableName = "$DataTableName-abuse"
$tempLoginId = 'abuse' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$tempPassword = 'T9' + [Guid]::NewGuid().ToString('N')
$recoverLoginId = 'recover' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$loginProbeId = 'login' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$fakeRecoveryCode = '2345-6789-ABCD-EFGH-JKLM'
$tempCreated = $false
$registrationBody = $null

try {
    Write-Host '[1/8] Verify Hosted health and tenant identity'
    $health = Invoke-JsonApi -Method GET -Uri "$base/hosted/health" -Headers $publicHeaders -Body $null -Context 'Hosted health'
    if ($health.service -ne 'minapp-hosted-api' -or $health.status -ne 'ok') {
        throw 'Hosted health response is invalid.'
    }
    $tenantInfo = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
    if ($tenantInfo.tenant_id -ne $ExpectedTenantId) {
        throw "tenant-info tenant mismatch. Expected $ExpectedTenantId but received $($tenantInfo.tenant_id)."
    }
    $legal = Invoke-JsonApi -Method GET -Uri "$base/hosted/legal" -Headers $publicHeaders -Body $null -Context 'Hosted legal documents'
    $termsVersion = [string]$legal.terms.version
    $privacyVersion = [string]$legal.privacy.version
    if ($termsVersion -notmatch '^hosted-terms-' -or $privacyVersion -notmatch '^hosted-privacy-') {
        throw 'Hosted legal endpoint returned invalid version identifiers.'
    }
    $registrationBody = @{
        login_id = $tempLoginId
        password = $tempPassword
        terms_version = $termsVersion
        privacy_version = $privacyVersion
        terms_accepted = $true
        privacy_accepted = $true
    }

    Write-Host '[2/8] Verify abuse-control DynamoDB table and TTL'
    aws dynamodb describe-table `
      --table-name $abuseTableName `
      --region $AwsRegion `
      --profile $AwsProfile `
      --output json | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "describe-table failed for $abuseTableName"
    }
    $ttl = aws dynamodb describe-time-to-live `
      --table-name $abuseTableName `
      --region $AwsRegion `
      --profile $AwsProfile `
      --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "describe-time-to-live failed for $abuseTableName"
    }
    if ($ttl.TimeToLiveDescription.TimeToLiveStatus -notin @('ENABLED', 'ENABLING')) {
        throw "Abuse table TTL is not enabled. status=$($ttl.TimeToLiveDescription.TimeToLiveStatus)"
    }
    if ($ttl.TimeToLiveDescription.AttributeName -ne 'expires_at_epoch') {
        throw "Abuse table TTL attribute mismatch: $($ttl.TimeToLiveDescription.AttributeName)"
    }

    Write-Host '[3/8] Register one temporary account'
    $registration = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body $registrationBody `
        -Context 'Temporary registration'
    if ($registration.login_id -ne $tempLoginId) {
        throw 'Temporary registration returned a different login_id.'
    }
    $tempCreated = $true
    $registration = $null

    Write-Host '[4/8] Verify registration per-login limit returns 429'
    foreach ($attempt in 2..3) {
        Invoke-ExpectStatus `
            -Method POST `
            -Uri "$base/hosted/register" `
            -Headers $publicHeaders `
            -Body $registrationBody `
            -ExpectedStatus 409 `
            -Context "Duplicate registration attempt $attempt" | Out-Null
    }
    $limitedRegister = Invoke-ExpectStatus `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body $registrationBody `
        -ExpectedStatus 429 `
        -Context 'Registration rate limit'
    $registerPayload = $limitedRegister.Content | ConvertFrom-Json
    if ($registerPayload.error -ne 'rate_limited') {
        throw "Registration 429 returned unexpected error '$($registerPayload.error)'."
    }

    Write-Host '[5/8] Verify recovery per-login limit returns 429'
    foreach ($attempt in 1..6) {
        Invoke-ExpectStatus `
            -Method POST `
            -Uri "$base/hosted/recover" `
            -Headers $publicHeaders `
            -Body @{ login_id = $recoverLoginId; recovery_code = $fakeRecoveryCode; new_password = $tempPassword } `
            -ExpectedStatus 401 `
            -Context "Recovery probe attempt $attempt" | Out-Null
    }
    $limitedRecover = Invoke-ExpectStatus `
        -Method POST `
        -Uri "$base/hosted/recover" `
        -Headers $publicHeaders `
        -Body @{ login_id = $recoverLoginId; recovery_code = $fakeRecoveryCode; new_password = $tempPassword } `
        -ExpectedStatus 429 `
        -Context 'Recovery rate limit'
    $recoverPayload = $limitedRecover.Content | ConvertFrom-Json
    if ($recoverPayload.error -ne 'rate_limited') {
        throw "Recovery 429 returned unexpected error '$($recoverPayload.error)'."
    }

    Write-Host '[6/8] Verify login per-login limit returns 429'
    foreach ($attempt in 1..10) {
        Invoke-ExpectStatus `
            -Method POST `
            -Uri "$base/auth/login" `
            -Headers $publicHeaders `
            -Body @{ login_id = $loginProbeId; password = $tempPassword } `
            -ExpectedStatus 401 `
            -Context "Login probe attempt $attempt" | Out-Null
    }
    $limitedLogin = Invoke-ExpectStatus `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $loginProbeId; password = $tempPassword } `
        -ExpectedStatus 429 `
        -Context 'Login rate limit'
    $loginPayload = $limitedLogin.Content | ConvertFrom-Json
    if ($loginPayload.error -ne 'rate_limited') {
        throw "Login 429 returned unexpected error '$($loginPayload.error)'."
    }

    Write-Host '[7/8] Delete temporary account'
    $login = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $tempLoginId; password = $tempPassword } `
        -Context 'Temporary account login'
    if ($login.state -ne 'authenticated' -or [string]::IsNullOrWhiteSpace([string]$login.access_token)) {
        throw 'Temporary account login did not authenticate.'
    }
    $authHeaders = @{
        Accept = 'application/json'
        Authorization = "Bearer $($login.access_token)"
    }
    Invoke-ExpectStatus `
        -Method DELETE `
        -Uri "$base/hosted/account" `
        -Headers $authHeaders `
        -Body $null `
        -ExpectedStatus 204 `
        -Context 'Temporary account deletion' | Out-Null
    $tempCreated = $false

    Write-Host '[8/8] Abuse-control smoke test complete'
    Write-Host ''
    Write-Host 'Hosted abuse-control AWS smoke test passed.'
    Write-Host 'Verified: abuse table TTL -> register 429 -> recover 429 -> login 429 -> temporary account cleanup.'
}
finally {
    $registrationBody = $null
    $tempPassword = $null
    if ($tempCreated) {
        Write-Warning 'The abuse-control smoke test stopped before temporary account cleanup completed.'
        Write-Warning "temporary_login_id=$tempLoginId"
        Write-Warning 'No password or recovery code is printed.'
    }
}
