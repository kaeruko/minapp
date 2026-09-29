param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$null = Get-Command cmd.exe -ErrorAction Stop
$null = Get-Command terraform.exe -ErrorAction Stop

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hostedDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'infra/hosted'))
$backendConfig = Join-Path $hostedDir 'backend.hcl'
$tfvarsPath = Join-Path $hostedDir 'terraform.tfvars'
$planName = 'tfplan-hosted-deploy'
$planPath = Join-Path $hostedDir $planName

if (-not (Test-Path -LiteralPath $backendConfig -PathType Leaf)) {
    throw "Hosted backend config is missing: $backendConfig"
}
if (-not (Test-Path -LiteralPath $tfvarsPath -PathType Leaf)) {
    throw "Hosted Terraform variables are missing: $tfvarsPath"
}

function Invoke-Terraform {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Context,

        [switch]$Capture
    )

    $command = "terraform $Arguments"

    if ($Capture) {
        $output = @(& cmd.exe /d /s /c $command 2>&1)
        $exitCode = $LASTEXITCODE
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ($exitCode -ne 0) {
            throw "$Context failed with exit code $exitCode. Output: $text"
        }
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "$Context returned empty output."
        }
        return $text
    }

    & cmd.exe /d /s /c $command
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Context failed with exit code $exitCode."
    }
}

Push-Location $hostedDir
try {
    Write-Host '[1/6] Initialize Hosted Terraform backend'
    Invoke-Terraform -Arguments 'init -backend-config=backend.hcl' -Context 'Terraform init'

    Write-Host '[2/6] Check formatting'
    Invoke-Terraform -Arguments 'fmt -check' -Context 'Terraform fmt check'

    Write-Host '[3/6] Validate configuration'
    Invoke-Terraform -Arguments 'validate' -Context 'Terraform validate'

    Write-Host '[4/6] Create saved plan'
    Invoke-Terraform -Arguments "plan -out=$planName" -Context 'Terraform plan'

    Write-Host '[5/6] Reject destroy or replacement actions'
    $planJsonText = Invoke-Terraform -Arguments "show -json $planName" -Context 'Terraform show JSON' -Capture
    try {
        $plan = $planJsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Terraform plan JSON could not be decoded: $($_.Exception.Message)"
    }

    $destructive = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'delete' }
    )

    if ($destructive.Count -ne 0) {
        $details = @(
            $destructive |
                ForEach-Object {
                    "$($_.address) [$(@($_.change.actions) -join ',')]"
                }
        ) -join '; '
        throw "Terraform plan contains destroy/replacement actions. Apply stopped. $details"
    }

    $creates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'create' }
    ).Count
    $updates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains 'update' }
    ).Count

    Write-Host "  Plan accepted: creates=$creates updates=$updates deletes=0"
    Invoke-Terraform -Arguments "show -no-color $planName" -Context 'Terraform show'

    if (-not $Apply) {
        Write-Host ''
        Write-Host 'Plan only. Nothing was applied.'
        Write-Host 'Review the plan above, then run:'
        Write-Host '  .\scripts\deploy-hosted.ps1 -Apply'
        return
    }

    Write-Host '[6/6] Apply the exact saved plan'
    Invoke-Terraform -Arguments "apply -input=false $planName" -Context 'Terraform apply'

    $apiBaseUrl = (Invoke-Terraform -Arguments 'output -raw api_base_url' -Context 'Terraform output api_base_url' -Capture).Trim()
    Write-Host ''
    Write-Host 'Hosted deployment completed.'
    Write-Host "API=$apiBaseUrl"
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        Remove-Item -LiteralPath $planPath -Force
    }
}
