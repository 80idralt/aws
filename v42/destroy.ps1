# Novatrix v42 VG: river allt som deploy.ps1 skapade.

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Namn   = "novatrix-web"
$SgNamn = "novatrix-web-sg"

# 1. Terminera instansen (letar på namnet, hoppar över redan borttagna)
$Instanser = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=$Namn" `
              "Name=instance-state-name,Values=pending,running,stopping,stopped" `
    --query "Reservations[].Instances[].InstanceId" --output text

if ($Instanser) {
    $Lista = $Instanser -split "\s+"
    aws ec2 terminate-instances --instance-ids $Lista | Out-Null
    Write-Host "Terminerar $Instanser, väntar tills den är borta..."
    aws ec2 wait instance-terminated --instance-ids $Lista
    Write-Host "Instansen är borttagen"
} else {
    Write-Host "Ingen instans att ta bort"
}

# 2. Ta bort security groupen (går först när instansen är borta)
$SgId = aws ec2 describe-security-groups --filters "Name=group-name,Values=$SgNamn" `
    --query "SecurityGroups[0].GroupId" --output text

if ($SgId -ne "None") {
    aws ec2 delete-security-group --group-id $SgId | Out-Null
    Write-Host "Security group $SgNamn borttagen ($SgId)"
} else {
    Write-Host "Ingen security group att ta bort"
}

Write-Host ""
Write-Host "Klart. Novatrix-miljön är riven och kostar inget längre."
