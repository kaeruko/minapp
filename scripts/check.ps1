$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command was not found in PATH: $Name"
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE. Arguments: $($Arguments -join ' ')"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Require-Command -Name "python"
Require-Command -Name "node"
Require-Command -Name "flutter"
Require-Command -Name "terraform"

Push-Location $repoRoot
try {
    Write-Host "== Python =="
    Invoke-Checked -Command "python" -Arguments @(
        "-m", "compileall", "-q",
        "backend/src", "backend/tests", "tools"
    )
    Invoke-Checked -Command "python" -Arguments @(
        "-m", "unittest", "discover", "-s", "backend/tests", "-v"
    )

    Write-Host "== Web =="
    Invoke-Checked -Command "node" -Arguments @("--check", "apps/web/app.js")

    Write-Host "== Flutter =="
    Push-Location (Join-Path $repoRoot "apps\mobile")
    try {
        Invoke-Checked -Command "flutter" -Arguments @("pub", "get")
        Invoke-Checked -Command "flutter" -Arguments @("analyze")
        Invoke-Checked -Command "flutter" -Arguments @("test")
    }
    finally {
        Pop-Location
    }

    Write-Host "== Terraform =="
    Invoke-Checked -Command "terraform" -Arguments @(
        "fmt", "-check", "-recursive", "infra/terraform"
    )
    Invoke-Checked -Command "terraform" -Arguments @(
        "-chdir=infra/terraform", "init", "-backend=false", "-input=false"
    )
    Invoke-Checked -Command "terraform" -Arguments @(
        "-chdir=infra/terraform", "validate"
    )

    Write-Host "All checks passed."
}
finally {
    Pop-Location
}
