# Novatrix v46: builds the whole environment from the three templates, network, data, web.
# Run:  .\deploy.ps1                       builds novatrix
#       .\deploy.ps1 -Prefix novatrix-test  builds a copy with other names
# Needs: logged in with "aws login", key pair novatrix-key and the two buckets.
# Safe to run again. What already matches the files is left alone.

param(
    [string]$Prefix = "novatrix"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The only values to change when building in another account
$KeyName      = "novatrix-key"
$DataBucket   = "novatrix-data-80idralt-01"
$BackupBucket = "novatrix-backup-80idralt-01"

# My public IP right now, only this address may use SSH
$MyIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()

Set-Location $PSScriptRoot

# Validate all three first, so a typo stops us before anything is built
foreach ($File in "natverk.yaml", "data.yaml", "webb.yaml") {
    aws cloudformation validate-template --template-body "file://$File" | Out-Null
    Write-Host "$File validerad"
}

# Network, data, web. Each layer reads the exports of the layer before it.
# --no-fail-on-empty-changeset: "No changes" is not an error when run again.
aws cloudformation deploy --template-file natverk.yaml --stack-name "$Prefix-natverk" `
    --no-fail-on-empty-changeset `
    --parameter-overrides "Prefix=$Prefix" "MyIp=$MyIp/32"

aws cloudformation deploy --template-file data.yaml --stack-name "$Prefix-data" `
    --no-fail-on-empty-changeset `
    --parameter-overrides "Prefix=$Prefix"

# CAPABILITY_NAMED_IAM: we accept that this stack creates a role with its own name
aws cloudformation deploy --template-file webb.yaml --stack-name "$Prefix-webb" `
    --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM `
    --parameter-overrides "Prefix=$Prefix" "KeyName=$KeyName" "DataBucket=$DataBucket" "BackupBucket=$BackupBucket"

$Url = aws cloudformation describe-stacks --stack-name "$Prefix-webb" `
    --query "Stacks[0].Outputs[?OutputKey=='WebUrl'].OutputValue" --output text
Write-Host ""
Write-Host "Klart. Sidan: $Url (user data behöver 2-3 minuter till)"
