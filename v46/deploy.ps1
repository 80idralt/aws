# Novatrix v46: bygger hela miljön från de tre templaterna i ordningen nät, data, webb.
# Kör:  .\deploy.ps1                       bygger novatrix
#       .\deploy.ps1 -Prefix novatrix-test  bygger en kopia med andra namn
# Kräver: inloggad med "aws login", key pair novatrix-key och de två bucketarna.

param(
    [string]$Prefix = "novatrix"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Det här byter man om man bygger i ett annat konto
$Nyckel       = "novatrix-key"
$DataBucket   = "novatrix-data-80idralt-01"
$BackupBucket = "novatrix-backup-80idralt-01"

# Min IP just nu, för SSH
$MinIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()

Set-Location $PSScriptRoot

# Validera alla tre först, så att ett skrivfel stoppar innan något byggs
foreach ($Fil in "natverk.yaml", "data.yaml", "webb.yaml") {
    aws cloudformation validate-template --template-body "file://$Fil" | Out-Null
    Write-Host "$Fil validerad"
}

# Bygg i ordningen nät, data, webb. Varje lager läser exporter från lagret före.
aws cloudformation deploy --template-file natverk.yaml --stack-name "$Prefix-natverk" `
    --no-fail-on-empty-changeset `
    --parameter-overrides "Prefix=$Prefix" "MyIp=$MinIp/32"

aws cloudformation deploy --template-file data.yaml --stack-name "$Prefix-data" `
    --no-fail-on-empty-changeset `
    --parameter-overrides "Prefix=$Prefix"

aws cloudformation deploy --template-file webb.yaml --stack-name "$Prefix-webb" `
    --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM `
    --parameter-overrides "Prefix=$Prefix" "KeyName=$Nyckel" "DataBucket=$DataBucket" "BackupBucket=$BackupBucket"

$Url = aws cloudformation describe-stacks --stack-name "$Prefix-webb" `
    --query "Stacks[0].Outputs[?OutputKey=='WebUrl'].OutputValue" --output text
Write-Host ""
Write-Host "Klart. Sidan: $Url (user data behöver 2-3 minuter till)"
