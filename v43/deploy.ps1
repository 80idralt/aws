# Novatrix v43 VG: bygger hela IAM-modellen från kod.
# Kräver: inloggad med "aws login", key pair novatrix-key finns i kontot.

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$env:AWS_CLI_FILE_ENCODING = "UTF-8"

# Inställningar
$Region       = "eu-north-1"
$Mapp         = Join-Path $PSScriptRoot "policies"
$DataBucket   = "novatrix-data-80idralt-01"
$BackupBucket = "novatrix-backup-80idralt-01"

# Kontonumret hämtas här, så att det aldrig behöver stå i repot
$Konto = aws sts get-caller-identity --query Account --output text

# 1. Bucketarna. Ny bucket blockerar allmän åtkomst från start.
aws s3api create-bucket --bucket $DataBucket --region $Region `
    --create-bucket-configuration LocationConstraint=$Region | Out-Null
aws s3api create-bucket --bucket $BackupBucket --region $Region `
    --create-bucket-configuration LocationConstraint=$Region | Out-Null
aws s3 cp (Join-Path $PSScriptRoot "hej.txt") "s3://$DataBucket/hej.txt" | Out-Null
Write-Host "Bucketar skapade, hej.txt uppladdad"

# 2. Människorna: policy först, sedan grupp, sedan användare
$DriftArn = aws iam create-policy --policy-name novatrix-drift `
    --policy-document "file://$Mapp/drift.json" --query Policy.Arn --output text
aws iam create-group --group-name novatrix-drift | Out-Null
aws iam attach-group-policy --group-name novatrix-drift --policy-arn $DriftArn
aws iam create-user --user-name drift-test | Out-Null
aws iam add-user-to-group --user-name drift-test --group-name novatrix-drift

$UtvArn = aws iam create-policy --policy-name novatrix-utveckling `
    --policy-document "file://$Mapp/utveckling.json" --query Policy.Arn --output text
aws iam create-group --group-name novatrix-utveckling | Out-Null
aws iam attach-group-policy --group-name novatrix-utveckling --policy-arn $UtvArn
aws iam create-user --user-name dev-test | Out-Null
aws iam add-user-to-group --user-name dev-test --group-name novatrix-utveckling
Write-Host "Grupper och testanvändare skapade"

# 3. Roll 1: webbservern läser data-bucketen
aws iam create-role --role-name novatrix-ec2-s3-read `
    --assume-role-policy-document "file://$Mapp/trust-ec2.json" | Out-Null
aws iam put-role-policy --role-name novatrix-ec2-s3-read `
    --policy-name novatrix-s3-read --policy-document "file://$Mapp/s3-read.json"

# Omslaget som låter en server bära rollen (konsolen gjorde det automatiskt)
aws iam create-instance-profile --instance-profile-name novatrix-ec2-s3-read | Out-Null
aws iam add-role-to-instance-profile --instance-profile-name novatrix-ec2-s3-read `
    --role-name novatrix-ec2-s3-read
Write-Host "Roll 1 novatrix-ec2-s3-read skapad"

# 4. Roll 2 och kedjan. KONTONUMMER i filerna byts mot det riktiga numret här.
$TrustBackup  = (Get-Content "$Mapp/trust-backup.json" -Raw).Replace("KONTONUMMER", $Konto)
$AssumeBackup = (Get-Content "$Mapp/assume-backup.json" -Raw).Replace("KONTONUMMER", $Konto)

# IAM behöver några sekunder innan en ny roll kan pekas ut i en annan rolls trust
Start-Sleep -Seconds 10

aws iam create-role --role-name novatrix-backup-write `
    --assume-role-policy-document $TrustBackup | Out-Null
aws iam put-role-policy --role-name novatrix-backup-write `
    --policy-name novatrix-s3-backup --policy-document "file://$Mapp/s3-backup.json"

# Sista länken: roll 1 får låna roll 2
aws iam put-role-policy --role-name novatrix-ec2-s3-read `
    --policy-name novatrix-assume-backup --policy-document $AssumeBackup
Write-Host "Roll 2 novatrix-backup-write och kedjan skapade"


# 5. Servern byggs med v42-skriptet, sedan får den roll 1
& (Join-Path $PSScriptRoot "..\v42\deploy.ps1")

$InstansId = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=novatrix-web" "Name=instance-state-name,Values=running" `
    --query "Reservations[0].Instances[0].InstanceId" --output text
aws ec2 associate-iam-instance-profile --instance-id $InstansId `
    --iam-instance-profile Name=novatrix-ec2-s3-read | Out-Null
Write-Host "Roll 1 kopplad till servern $InstansId"
