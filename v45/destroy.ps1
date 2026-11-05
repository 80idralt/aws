# Novatrix v45 VG: river allt som deploy.ps1 skapade, i omvänd ordning.
# Kräver: inloggad med "aws login".

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Hitta VPC:t på namnet
$VpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=novatrix-vpc" --query "Vpcs[0].VpcId" --output text
if ($VpcId -eq "None") {
    Write-Host "Inget novatrix-vpc finns, inget att riva."
    exit 0
}

# 1. Databasen. Starta raderingen först, den tar längst tid.
#    Ingen sista snapshot och inga sparade backuper.
$DbFinns = aws rds describe-db-instances `
    --query "DBInstances[?DBInstanceIdentifier=='novatrix-db'].DBInstanceIdentifier" --output text
if ($DbFinns) {
    aws rds delete-db-instance --db-instance-identifier novatrix-db `
        --skip-final-snapshot --delete-automated-backups | Out-Null
    Write-Host "Databasen raderas, vi fortsätter så länge"
}

# 2. Servrarna, de sitter i subnätet. Hoppa över den som redan är borta.
$Lever = "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down"
$WebId = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=novatrix-web" $Lever `
    --query "Reservations[0].Instances[0].InstanceId" --output text
if ($WebId -ne "None") {
    aws ec2 terminate-instances --instance-ids $WebId | Out-Null
    Write-Host "Terminerar webbservern, väntar..."
    aws ec2 wait instance-terminated --instance-ids $WebId
}

$BastionId = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=novatrix-bastion" $Lever `
    --query "Reservations[0].Instances[0].InstanceId" --output text
if ($BastionId -ne "None") {
    aws ec2 terminate-instances --instance-ids $BastionId | Out-Null
    Write-Host "Terminerar bastion, väntar..."
    aws ec2 wait instance-terminated --instance-ids $BastionId
}
Write-Host "Servrarna borta"

# 3. EFS. Uttagen först, sedan disken.
$EfsId = aws efs describe-file-systems --query "FileSystems[?Name=='novatrix-efs'].FileSystemId" --output text
if ($EfsId) {
    $Uttag = aws efs describe-mount-targets --file-system-id $EfsId --query "MountTargets[].MountTargetId" --output text
    foreach ($MtId in $Uttag -split "\s+") {
        aws efs delete-mount-target --mount-target-id $MtId
    }
    Write-Host "EFS-uttagen tas bort, väntar..."
    do {
        Start-Sleep -Seconds 10
        $Kvar = aws efs describe-mount-targets --file-system-id $EfsId --query "length(MountTargets)" --output text
    } while ($Kvar -ne "0")
    aws efs delete-file-system --file-system-id $EfsId
    Write-Host "EFS borta"
}

# 4. Databasen måste vara helt borta innan listan med rum kan raderas
if ($DbFinns) {
    Write-Host "Väntar på att databasen ska vara helt borta..."
    aws rds wait db-instance-deleted --db-instance-identifier novatrix-db
}
aws rds delete-db-subnet-group --db-subnet-group-name novatrix-db-subnets
Write-Host "Databasen och subnet group borta"

# 5. Security groups. efs och db pekar på web, web pekar på bastion. Därför efs och db först.
$EfsSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-efs-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $EfsSg | Out-Null
$DbSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-db-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $DbSg | Out-Null
$WebSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-web-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $WebSg | Out-Null
$BastionSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-bastion-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $BastionSg | Out-Null
Write-Host "Security groups borta"

# 6. Subnäten. Då släpper också kopplingarna till route table och NACL.
$PublicId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-public" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PublicId
$PrivAId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-private-a" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PrivAId
$PrivBId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-private-b" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PrivBId
Write-Host "Subnäten borta"

# 7. Route table och NACL
$RtId = aws ec2 describe-route-tables --filters "Name=tag:Name,Values=novatrix-public-rt" --query "RouteTables[0].RouteTableId" --output text
aws ec2 delete-route-table --route-table-id $RtId

$NaclId = aws ec2 describe-network-acls --filters "Name=tag:Name,Values=novatrix-public-nacl" --query "NetworkAcls[0].NetworkAclId" --output text
aws ec2 delete-network-acl --network-acl-id $NaclId
Write-Host "Route table och NACL borta"

# 8. Internet gateway: lossa från VPC:t, sedan ta bort
$IgwId = aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=novatrix-igw" --query "InternetGateways[0].InternetGatewayId" --output text
aws ec2 detach-internet-gateway --internet-gateway-id $IgwId --vpc-id $VpcId
aws ec2 delete-internet-gateway --internet-gateway-id $IgwId
Write-Host "Internet gateway borta"

# 9. Sist själva VPC:t
aws ec2 delete-vpc --vpc-id $VpcId
Write-Host ""
Write-Host "Klart. Allt från v45 är rivet."
Write-Host "IAM och bucketarna från v43 står kvar, med livscykelregeln."
