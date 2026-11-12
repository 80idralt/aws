# Novatrix v46: river miljön i omvänd ordning, webb, data, nät.
# Kör:  .\destroy.ps1                       river novatrix
#       .\destroy.ps1 -Prefix novatrix-test  river kopian
# Bucketarna och key pairet ingår inte i någon stack och ligger kvar.

param(
    [string]$Prefix = "novatrix"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Omvänd ordning, annars stoppar CloudFormation eftersom exporterna används
foreach ($Lager in "webb", "data", "natverk") {
    $Stack = "$Prefix-$Lager"
    Write-Host "River $Stack ..."
    aws cloudformation delete-stack --stack-name $Stack
    aws cloudformation wait stack-delete-complete --stack-name $Stack
}

Write-Host "Klart. Kvar finns bara bucketarna och key pairet."
