param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$HostedApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$ExpectedTenantId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsRegion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IdentityRoleName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IdentityFunctionName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataTableName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
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

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $raw = & aws @Arguments --profile $AwsProfile --region $AwsRegion --output json --no-cli-pager
    if ($LASTEXITCODE -ne 0) {
        throw "$Context failed with exit code $LASTEXITCODE."
    }
    try {
        return ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$Context returned invalid JSON: $($_.Exception.Message)"
    }
}

function Assert-ExactSet {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $difference = @(Compare-Object -ReferenceObject $expectedValues -DifferenceObject $actualValues)
    if ($difference.Count -ne 0) {
        throw "$Context mismatch. Expected='$($expectedValues -join ',')' Actual='$($actualValues -join ',')'."
    }
}

function Assert-PolicyStatement {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PolicyDocument,

        [Parameter(Mandatory = $true)]
        [string]$Sid,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedActions,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedResources
    )

    $matches = @($PolicyDocument.Statement | Where-Object { [string]$_.Sid -eq $Sid })
    if ($matches.Count -ne 1) {
        throw "IAM policy must contain exactly one '$Sid' statement; found $($matches.Count)."
    }
    $statement = $matches[0]
    if ([string]$statement.Effect -ne 'Allow') {
        throw "IAM statement '$Sid' must have Effect=Allow."
    }
    if ($null -ne $statement.PSObject.Properties['NotAction'] -or $null -ne $statement.PSObject.Properties['NotResource']) {
        throw "IAM statement '$Sid' must not use NotAction or NotResource."
    }
    Assert-ExactSet -Actual @($statement.Action) -Expected $ExpectedActions -Context "IAM statement '$Sid' actions"
    Assert-ExactSet -Actual @($statement.Resource) -Expected $ExpectedResources -Context "IAM statement '$Sid' resources"
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw 'Required command was not found in PATH: aws'
}

$applicationPolicyName = "$IdentityRoleName-application"
$abusePolicyName = "$IdentityRoleName-abuse-control"
$expectedRoleArn = "arn:aws:iam::$ExpectedAccountId`:role/$IdentityRoleName"
$metadataTableArn = "arn:aws:dynamodb:$AwsRegion`:$ExpectedAccountId`:table/$DataTableName"
$runtimeTableArn = "arn:aws:dynamodb:$AwsRegion`:$ExpectedAccountId`:table/$RuntimeTableName"
$abuseTableArn = "arn:aws:dynamodb:$AwsRegion`:$ExpectedAccountId`:table/$DataTableName-abuse"
$userPoolArn = "arn:aws:cognito-idp:$AwsRegion`:$ExpectedAccountId`:userpool/$UserPoolId"
$basicExecutionPolicyArn = 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'

Write-Host '[1/5] Verify AWS account and Lambda role boundary'
$identity = Invoke-AwsJson -Arguments @('sts', 'get-caller-identity') -Context 'AWS caller identity'
if ([string]$identity.Account -ne $ExpectedAccountId) {
    throw "AWS account mismatch. Expected $ExpectedAccountId but current credentials target $($identity.Account)."
}
$lambda = Invoke-AwsJson `
    -Arguments @('lambda', 'get-function-configuration', '--function-name', $IdentityFunctionName) `
    -Context 'Hosted identity Lambda configuration'
if ([string]$lambda.Role -ne $expectedRoleArn) {
    throw "Hosted identity Lambda role mismatch. Expected '$expectedRoleArn' but found '$($lambda.Role)'."
}

Write-Host '[2/5] Verify dedicated role attachments and inline policies'
$inline = Invoke-AwsJson -Arguments @('iam', 'list-role-policies', '--role-name', $IdentityRoleName) -Context 'Hosted inline policies'
Assert-ExactSet `
    -Actual @($inline.PolicyNames) `
    -Expected @($applicationPolicyName, $abusePolicyName) `
    -Context 'Hosted inline policy names'
$attached = Invoke-AwsJson -Arguments @('iam', 'list-attached-role-policies', '--role-name', $IdentityRoleName) -Context 'Hosted attached policies'
Assert-ExactSet `
    -Actual @($attached.AttachedPolicies.PolicyArn) `
    -Expected @($basicExecutionPolicyArn) `
    -Context 'Hosted attached policy ARNs'

Write-Host '[3/5] Verify least-privilege application and abuse policies'
$application = Invoke-AwsJson `
    -Arguments @('iam', 'get-role-policy', '--role-name', $IdentityRoleName, '--policy-name', $applicationPolicyName) `
    -Context 'Hosted application policy'
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedMetadata' `
    -ExpectedActions @(
        'dynamodb:DeleteItem',
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:Query',
        'dynamodb:TransactWriteItems',
        'dynamodb:UpdateItem'
    ) `
    -ExpectedResources @($metadataTableArn)
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedRuntimeData' `
    -ExpectedActions @(
        'dynamodb:DeleteItem',
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:Query',
        'dynamodb:TransactWriteItems',
        'dynamodb:UpdateItem'
    ) `
    -ExpectedResources @($runtimeTableArn)
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedUserAdministration' `
    -ExpectedActions @(
        'cognito-idp:AdminCreateUser',
        'cognito-idp:AdminDeleteUser',
        'cognito-idp:AdminGetUser',
        'cognito-idp:AdminSetUserPassword'
    ) `
    -ExpectedResources @($userPoolArn)
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedBuiltinSourceTemplates' `
    -ExpectedActions @('s3:GetObject') `
    -ExpectedResources @(
        "arn:aws:s3:::$UploadBucketName/hosted/templates/shiba-game/v1/source.zip",
        "arn:aws:s3:::$UploadBucketName/hosted/templates/shiba-goshujin/v1/source.zip"
    )
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedDraftSourceObjects' `
    -ExpectedActions @('s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:DeleteObjectVersion') `
    -ExpectedResources @("arn:aws:s3:::$UploadBucketName/hosted/drafts/*")
Assert-PolicyStatement `
    -PolicyDocument $application.PolicyDocument `
    -Sid 'HostedPublishedSourceObjects' `
    -ExpectedActions @('s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:DeleteObjectVersion') `
    -ExpectedResources @("arn:aws:s3:::$PublishedBucketName/hosted/published/*")
Assert-ExactSet `
    -Actual @($application.PolicyDocument.Statement.Sid) `
    -Expected @(
        'HostedMetadata',
        'HostedRuntimeData',
        'HostedUserAdministration',
        'HostedBuiltinSourceTemplates',
        'HostedDraftSourceObjects',
        'HostedPublishedSourceObjects'
    ) `
    -Context 'Hosted application statement SIDs'

$abuse = Invoke-AwsJson `
    -Arguments @('iam', 'get-role-policy', '--role-name', $IdentityRoleName, '--policy-name', $abusePolicyName) `
    -Context 'Hosted abuse-control policy'
Assert-PolicyStatement `
    -PolicyDocument $abuse.PolicyDocument `
    -Sid 'HostedAbuseRateLimits' `
    -ExpectedActions @('dynamodb:UpdateItem') `
    -ExpectedResources @($abuseTableArn)
Assert-ExactSet `
    -Actual @($abuse.PolicyDocument.Statement.Sid) `
    -Expected @('HostedAbuseRateLimits') `
    -Context 'Hosted abuse-control statement SIDs'

$allActions = @($application.PolicyDocument.Statement.Action) + @($abuse.PolicyDocument.Statement.Action)
if (@($allActions | ForEach-Object { @($_) } | Where-Object { $_ -in @('s3:ListBucket', 's3:*') }).Count -ne 0) {
    throw 'Hosted identity role unexpectedly contains an S3 list or wildcard action.'
}

Write-Host '[4/5] Run one-user Hosted and Runtime flow with a generated temporary account'
& "$PSScriptRoot/smoke-test-hosted.ps1" `
    -HostedApiBaseUrl $HostedApiBaseUrl `
    -ExpectedTenantId $ExpectedTenantId `
    -TemporaryUser `
    -BuiltinId $BuiltinId

Write-Host '[5/5] Run abuse-control limit and cleanup flow'
& "$PSScriptRoot/smoke-test-hosted-abuse-control.ps1" `
    -HostedApiBaseUrl $HostedApiBaseUrl `
    -ExpectedTenantId $ExpectedTenantId `
    -AwsRegion $AwsRegion `
    -AwsProfile $AwsProfile `
    -DataTableName $DataTableName

Write-Host ''
Write-Host 'Hosted IAM AWS smoke test passed.'
Write-Host 'Verified: dedicated role boundary -> exact DynamoDB/Cognito/S3 prefixes -> no S3 list/wildcard -> one-user Runtime -> abuse control -> cleanup.'
