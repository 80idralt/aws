# Novatrix v43 VG: river allt som deploy.ps1 skapade, i omvänd ordning.
# Kräver: inloggad med "aws login".

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$DataBucket   = "novatrix-data-80idralt-01"
$BackupBucket = "novatrix-backup-80idralt-01"
$Konto = aws sts get-caller-identity --query Account --output text

# 1. Servern först, den bär roll 1
& (Join-Path $PSScriptRoot "..\v42\destroy.ps1")

# 2. Rollerna: ta ur rollen ur omslaget, ta bort omslaget, sedan lapparna, sist rollen
aws iam remove-role-from-instance-profile --instance-profile-name novatrix-ec2-s3-read `
    --role-name novatrix-ec2-s3-read
aws iam delete-instance-profile --instance-profile-name novatrix-ec2-s3-read

aws iam delete-role-policy --role-name novatrix-ec2-s3-read --policy-name novatrix-s3-read
aws iam delete-role-policy --role-name novatrix-ec2-s3-read --policy-name novatrix-assume-backup
aws iam delete-role --role-name novatrix-ec2-s3-read

aws iam delete-role-policy --role-name novatrix-backup-write --policy-name novatrix-s3-backup
aws iam delete-role --role-name novatrix-backup-write
Write-Host "Rollerna borttagna"


# 3. Människorna: ur gruppen, bort med användaren, av med lappen, bort med gruppen, sist lappen
aws iam remove-user-from-group --user-name drift-test --group-name novatrix-drift
aws iam delete-user --user-name drift-test
aws iam detach-group-policy --group-name novatrix-drift `
    --policy-arn "arn:aws:iam::${Konto}:policy/novatrix-drift"
aws iam delete-group --group-name novatrix-drift
aws iam delete-policy --policy-arn "arn:aws:iam::${Konto}:policy/novatrix-drift"

aws iam remove-user-from-group --user-name dev-test --group-name novatrix-utveckling
aws iam delete-user --user-name dev-test
aws iam detach-group-policy --group-name novatrix-utveckling `
    --policy-arn "arn:aws:iam::${Konto}:policy/novatrix-utveckling"
aws iam delete-group --group-name novatrix-utveckling
aws iam delete-policy --policy-arn "arn:aws:iam::${Konto}:policy/novatrix-utveckling"
Write-Host "Grupper, testanvändare och deras policies borttagna"

# 4. Bucketarna. --force tömmer dem först.
aws s3 rb "s3://$DataBucket" --force | Out-Null
aws s3 rb "s3://$BackupBucket" --force | Out-Null
Write-Host "Bucketarna borttagna"

Write-Host ""
Write-Host "Klart. Allt från v43 är rivet."

