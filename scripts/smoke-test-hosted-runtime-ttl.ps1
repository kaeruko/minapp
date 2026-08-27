param(
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
    [string]$DataTableName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

Write-Host '[1/3] Verify AWS account'
$null = Get-Command aws -ErrorAction Stop
$identity = Invoke-AwsJson -Arguments @('sts', 'get-caller-identity') -Context 'AWS caller identity'
if ([string]$identity.Account -ne $ExpectedAwsAccountId) {
    throw "AWS account mismatch. Expected $ExpectedAwsAccountId but received $($identity.Account)."
}

Write-Host '[2/3] Verify Hosted metadata table'
$table = Invoke-AwsJson `
    -Arguments @('dynamodb', 'describe-table', '--table-name', $DataTableName) `
    -Context 'Hosted DynamoDB table lookup'
if ([string]$table.Table.TableName -ne $DataTableName) {
    throw "DynamoDB table mismatch. Expected '$DataTableName' but received '$($table.Table.TableName)'."
}
if ([string]$table.Table.TableStatus -ne 'ACTIVE') {
    throw "DynamoDB table '$DataTableName' is not ACTIVE: $($table.Table.TableStatus)"
}

Write-Host '[3/3] Verify runtime-session TTL cleanup'
$ttl = Invoke-AwsJson `
    -Arguments @('dynamodb', 'describe-time-to-live', '--table-name', $DataTableName) `
    -Context 'Hosted DynamoDB TTL lookup'
$description = $ttl.TimeToLiveDescription
if ($null -eq $description) {
    throw 'DynamoDB TTL response has no TimeToLiveDescription.'
}
if ([string]$description.AttributeName -ne 'ttl_epoch') {
    throw "DynamoDB TTL attribute mismatch. Expected 'ttl_epoch' but received '$($description.AttributeName)'."
}
if ([string]$description.TimeToLiveStatus -ne 'ENABLED') {
    throw "DynamoDB TTL is not ENABLED. Current status: $($description.TimeToLiveStatus)"
}

Write-Host ''
Write-Host 'Hosted runtime-session TTL AWS smoke test passed.'
Write-Host 'Verified: metadata table ACTIVE -> TTL attribute ttl_epoch -> TTL status ENABLED.'
