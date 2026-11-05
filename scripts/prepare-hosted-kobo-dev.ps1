# Prepare Kobo dev deployment settings on this machine only. No AWS command runs.
# backend.hcl and terraform.tfvars are gitignored and must never be committed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$hosted = Join-Path (Split-Path -Parent $PSScriptRoot) 'infra/hosted'
$backendPath = Join-Path $hosted 'backend.hcl'
$varsPath = Join-Path $hosted 'terraform.tfvars'
$cachedPath = Join-Path $hosted '.terraform/terraform.tfstate'
$koboKey = 'minapp/hosted/kobo/dev/terraform.tfstate'
$oldKey = 'minapp/hosted/dev/terraform.tfstate'
$region = 'us-west-2'

function Read-StrictUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required local file not found: $Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $decoder = [System.Text.UTF8Encoding]::new($false, $true)
    $value = $decoder.GetString($bytes, $offset, $bytes.Length - $offset)
    return [pscustomobject]@{ Text = $value; HasBom = $hasBom }
}

function Get-OneSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Name) +
        '[ \t]*=[ \t]*"([^"\r\n]+)"[ \t]*\r?$'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one quoted $Name setting; found $($matches.Count)."
    }
    return $matches[0].Groups[1].Value
}

$backend = Read-StrictUtf8 $backendPath
$vars = Read-StrictUtf8 $varsPath
$cache = Read-StrictUtf8 $cachedPath
$state = $cache.Text | ConvertFrom-Json

if ($null -eq $state.backend -or $state.backend.type -ne 's3' -or
    $null -eq $state.backend.config) {
    throw 'Cached Terraform backend is not an S3 configuration.'
}
if ($state.backend.config.key -ne $koboKey -or
    $state.backend.config.region -ne $region) {
    throw 'Cached Terraform backend does not match the Kobo dev target.'
}
if ((Get-OneSetting $backend.Text 'bucket') -ne $state.backend.config.bucket) {
    throw 'backend.hcl bucket does not match the cached Kobo backend.'
}
if ((Get-OneSetting $backend.Text 'region') -ne $region -or
    (Get-OneSetting $vars.Text 'aws_region') -ne $region -or
    (Get-OneSetting $vars.Text 'environment') -ne 'dev') {
    throw 'Region or environment does not match the Kobo dev target.'
}

$currentKey = Get-OneSetting $backend.Text 'key'
if ($currentKey -ne $oldKey -and $currentKey -ne $koboKey) {
    throw 'backend.hcl uses an unexpected state key; refusing to change it.'
}
$editionMatches = [regex]::Matches($vars.Text, '(?m)^[ \t]*edition[ \t]*=')
if ($editionMatches.Count -gt 1) {
    throw 'terraform.tfvars contains more than one edition setting.'
}
if ($editionMatches.Count -eq 1 -and
    (Get-OneSetting $vars.Text 'edition') -ne 'kobo') {
    throw 'terraform.tfvars has a non-Kobo edition; refusing to replace it.'
}

$newBackend = $backend.Text
if ($currentKey -eq $oldKey) {
    $newBackend = $backend.Text.Replace(
        '"' + $oldKey + '"', '"' + $koboKey + '"'
    )
    if ($newBackend -eq $backend.Text) {
        throw 'Expected backend state key replacement did not happen.'
    }
}
$newVars = $vars.Text
if ($editionMatches.Count -eq 0) {
    $crlf = [string][char]13 + [string][char]10
    $lf = [string][char]10
    if ($vars.Text.Contains($crlf) -and
        $vars.Text.Replace($crlf, '').Contains($lf)) {
        throw 'terraform.tfvars has mixed line endings.'
    }
    $newline = if ($vars.Text.Contains($crlf)) { $crlf } else { $lf }
    $separator = if ($vars.Text.EndsWith($lf)) { '' } else { $newline }
    $newVars = $vars.Text + $separator + 'edition = "kobo"' + $newline
}
if ((Get-OneSetting $newBackend 'key') -ne $koboKey -or
    (Get-OneSetting $newVars 'edition') -ne 'kobo') {
    throw 'Postcondition failed; no files were changed.'
}

if ($newBackend -ne $backend.Text) {
    [System.IO.File]::WriteAllText(
        $backendPath, $newBackend,
        [System.Text.UTF8Encoding]::new($backend.HasBom, $true)
    )
}
if ($newVars -ne $vars.Text) {
    [System.IO.File]::WriteAllText(
        $varsPath, $newVars,
        [System.Text.UTF8Encoding]::new($vars.HasBom, $true)
    )
}
Write-Host 'Kobo dev local Terraform configuration prepared.'
Write-Host 'No Terraform init, plan, or apply was run.'
