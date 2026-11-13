# Novatrix v46: removes the environment in reverse order, web, data, network.
# Run:  .\destroy.ps1                       removes novatrix
#       .\destroy.ps1 -Prefix novatrix-test  removes the copy
# The buckets and the key pair are not part of any stack and stay.
# The database and EFS go with the data stack. Run backup.sh first to keep the content.

param(
    [string]$Prefix = "novatrix"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Reverse order. CloudFormation refuses to remove a stack whose exports are still in use.
foreach ($Layer in "webb", "data", "natverk") {
    $Stack = "$Prefix-$Layer"
    Write-Host "River $Stack ..."
    aws cloudformation delete-stack --stack-name $Stack
    # delete-stack only starts the job, wait so the next layer is free
    aws cloudformation wait stack-delete-complete --stack-name $Stack
}

Write-Host "Klart. Kvar finns bara bucketarna och key pairet."
