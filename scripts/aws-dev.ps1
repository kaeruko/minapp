$env:AWS_PROFILE = "minapp-admin"

aws sts get-caller-identity
if ($LASTEXITCODE -ne 0) {
    throw "AWS authentication failed"
}

Write-Host "MinApp AWS environment ready."
Write-Host "  Profile: minapp-admin"
Write-Host "  Region:  us-west-2 (Terraform configuration)"