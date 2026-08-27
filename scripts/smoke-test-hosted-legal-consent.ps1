param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z]{2}-[a-z]+-\d$')]
    [string]$AwsRegion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]{3,255}$')]
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

function Assert-HttpFailure {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('POST')]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [object]$Body,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedStatus,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedError,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        ContentType = 'application/json'
        Body = $Body | ConvertTo-Json -Depth 20 -Compress
        TimeoutSec = 15
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
        $bodyText = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($bodyText)) {
            throw "$Context returned HTTP $actualStatus without a JSON error body."
        }
        $payload = $bodyText | ConvertFrom-Json
        if ([string]$payload.error -ne $ExpectedError) {
            throw "$Context returned error '$($payload.error)'; expected '$ExpectedError'."
        }
        return
    }
    throw "$Context unexpectedly succeeded with HTTP $([int]$response.StatusCode)."
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
    return $text | ConvertFrom-Json
}

function Get-DynamoProfile {
    param([Parameter(Mandatory = $true)][string]$UserId)
    $key = "pk={S=USER#$UserId},sk={S=PROFILE}"
    return Invoke-AwsJson `
        -Arguments @('dynamodb', 'get-item', '--table-name', $DataTableName, '--key', $key, '--consistent-read') `
        -Context 'Hosted legal USER profile lookup'
}

function New-AuthHeaders {
    param([Parameter(Mandatory = $true)][string]$Token)
    return @{ Accept = 'application/json'; Authorization = "Bearer $Token" }
}

$baseUri = [Uri]$HostedApiBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne 'https' -or $baseUri.AbsolutePath -ne '/') {
    throw 'HostedApiBaseUrl must be an absolute HTTPS origin without a path.'
}
$base = $baseUri.AbsoluteUri.TrimEnd('/')
$publicHeaders = @{ Accept = 'application/json' }
$loginId = 'legal' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$password = 'Z9' + [Guid]::NewGuid().ToString('N')
$userId = $null
$accessToken = $null
$created = $false

try {
    Write-Host '[1/9] Verify Hosted health and tenant identity'
    $health = Invoke-JsonApi -Method GET -Uri "$base/hosted/health" -Headers $publicHeaders -Body $null -Context 'Hosted health'
    if ($health.service -ne 'minapp-hosted-api' -or $health.status -ne 'ok') {
        throw 'Hosted health response is invalid.'
    }
    $tenantInfo = Invoke-JsonApi -Method GET -Uri "$base/tenant-info" -Headers $publicHeaders -Body $null -Context 'tenant-info'
    if ([string]$tenantInfo.tenant_id -ne $ExpectedTenantId) {
        throw "tenant-info mismatch: $($tenantInfo.tenant_id)"
    }

    Write-Host '[2/9] Fetch current Terms and Privacy versions'
    $legal = Invoke-JsonApi -Method GET -Uri "$base/hosted/legal" -Headers $publicHeaders -Body $null -Context 'Hosted legal documents'
    $termsVersion = [string]$legal.terms.version
    $privacyVersion = [string]$legal.privacy.version
    if ($termsVersion -notmatch '^hosted-terms-' -or $privacyVersion -notmatch '^hosted-privacy-') {
        throw 'Hosted legal endpoint returned invalid version identifiers.'
    }
    if ([string]$legal.terms.body -notmatch 'zero tolerance') {
        throw 'Hosted Terms do not contain the expected zero-tolerance statement.'
    }
    if ([string]$legal.privacy.body -notmatch 'Amazon Web Services') {
        throw 'Hosted Privacy Policy does not describe the AWS processing layer.'
    }

    $validRegistration = @{
        login_id = $loginId
        password = $password
        terms_version = $termsVersion
        privacy_version = $privacyVersion
        terms_accepted = $true
        privacy_accepted = $true
    }

    Write-Host '[3/9] Verify registration without consent is rejected'
    $missingConsent = @{
        login_id = $loginId
        password = $password
        terms_version = $termsVersion
        privacy_version = $privacyVersion
        terms_accepted = $false
        privacy_accepted = $true
    }
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body $missingConsent `
        -ExpectedStatus 400 `
        -ExpectedError 'terms_not_accepted' `
        -Context 'Terms acceptance rejection'

    Write-Host '[4/9] Verify stale legal version is rejected'
    $stale = $validRegistration.Clone()
    $stale.terms_version = 'hosted-terms-stale'
    Assert-HttpFailure `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body $stale `
        -ExpectedStatus 409 `
        -ExpectedError 'terms_version_outdated' `
        -Context 'Stale Terms version rejection'

    Write-Host '[5/9] Register with current Terms and Privacy consent'
    $registration = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/hosted/register" `
        -Headers $publicHeaders `
        -Body $validRegistration `
        -Context 'Hosted legal registration'
    $created = $true
    $userId = [string]$registration.user_id
    if ($userId -notmatch '^[0-9a-f]{32}$') {
        throw 'Registration returned an invalid user_id.'
    }
    if ([string]$registration.legal.terms_version -ne $termsVersion -or [string]$registration.legal.privacy_version -ne $privacyVersion) {
        throw 'Registration response legal versions do not match /hosted/legal.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$registration.legal.accepted_at)) {
        throw 'Registration response has no server acceptance timestamp.'
    }

    Write-Host '[6/9] Verify DynamoDB consent audit fields'
    $profile = Get-DynamoProfile -UserId $userId
    if ($null -eq $profile.Item) {
        throw 'Hosted USER profile was not found.'
    }
    if ([string]$profile.Item.terms_version.S -ne $termsVersion) {
        throw 'Stored terms_version does not match the accepted Terms version.'
    }
    if ([string]$profile.Item.privacy_version.S -ne $privacyVersion) {
        throw 'Stored privacy_version does not match the accepted Privacy version.'
    }
    if ($profile.Item.terms_accepted.BOOL -ne $true -or $profile.Item.privacy_accepted.BOOL -ne $true) {
        throw 'Stored legal acceptance flags are not true.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$profile.Item.terms_accepted_at.S)) {
        throw 'Stored legal acceptance timestamp is missing.'
    }

    Write-Host '[7/9] Login registered user'
    $login = Invoke-JsonApi `
        -Method POST `
        -Uri "$base/auth/login" `
        -Headers $publicHeaders `
        -Body @{ login_id = $loginId; password = $password } `
        -Context 'Hosted legal test login'
    if ($login.state -ne 'authenticated') {
        throw 'Hosted legal test login did not authenticate.'
    }
    $accessToken = [string]$login.access_token

    Write-Host '[8/9] Delete temporary account'
    $delete = Invoke-WebRequest `
        -Method DELETE `
        -Uri "$base/hosted/account" `
        -Headers (New-AuthHeaders -Token $accessToken) `
        -TimeoutSec 15
    if ([int]$delete.StatusCode -ne 204) {
        throw "Account deletion returned HTTP $([int]$delete.StatusCode)."
    }
    $created = $false

    Write-Host '[9/9] Legal-consent smoke test complete'
    Write-Host ''
    Write-Host 'Hosted legal-consent AWS smoke test passed.'
    Write-Host 'Verified: legal documents -> explicit consent required -> stale version rejected -> consent version/timestamp persisted -> cleanup.'
}
finally {
    if ($created) {
        Write-Warning "Temporary account may remain after failure: login_id=$loginId user_id=$userId"
    }
    $password = $null
    $accessToken = $null
}
