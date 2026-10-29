# Novatrix v44 VG: river allt som deploy.ps1 skapade, i omvänd ordning.
# Kräver: inloggad med "aws login".

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Hitta VPC:t på namnet
$VpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=novatrix-vpc" --query "Vpcs[0].VpcId" --output text
if ($VpcId -eq "None") {
    Write-Host "Inget novatrix-vpc finns, inget att riva."
    exit 0
}

# 1. Servrarna först, de sitter i subnätet. Hoppa över den som redan är borta.
$WebId = aws ec2 describe-instances --filters "Name=tag:Name,Values=novatrix-web" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" `
    --query "Reservations[0].Instances[0].InstanceId" --output text
if ($WebId -ne "None") {
    aws ec2 terminate-instances --instance-ids $WebId | Out-Null
    Write-Host "Terminerar webbservern, väntar..."
    aws ec2 wait instance-terminated --instance-ids $WebId
}

$BastionId = aws ec2 describe-instances --filters "Name=tag:Name,Values=novatrix-bastion" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" `
    --query "Reservations[0].Instances[0].InstanceId" --output text
if ($BastionId -ne "None") {
    aws ec2 terminate-instances --instance-ids $BastionId | Out-Null
    Write-Host "Terminerar bastion, väntar..."
    aws ec2 wait instance-terminated --instance-ids $BastionId
}
Write-Host "Servrarna borta"

# 2. Security groups. db pekar på web, web pekar på bastion, så db först.
$DbSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-db-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $DbSg
$WebSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-web-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $WebSg
$BastionSg = aws ec2 describe-security-groups --filters "Name=group-name,Values=novatrix-bastion-sg" --query "SecurityGroups[0].GroupId" --output text
aws ec2 delete-security-group --group-id $BastionSg
Write-Host "Security groups borta"

# 3. Subnäten. Då släpper också kopplingarna till route table och NACL.
$PublicId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-public" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PublicId
$PrivAId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-private-a" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PrivAId
$PrivBId = aws ec2 describe-subnets --filters "Name=tag:Name,Values=novatrix-private-b" --query "Subnets[0].SubnetId" --output text
aws ec2 delete-subnet --subnet-id $PrivBId
Write-Host "Subnäten borta"

# 4. Route table och NACL
$RtId = aws ec2 describe-route-tables --filters "Name=tag:Name,Values=novatrix-public-rt" --query "RouteTables[0].RouteTableId" --output text
aws ec2 delete-route-table --route-table-id $RtId

$NaclId = aws ec2 describe-network-acls --filters "Name=tag:Name,Values=novatrix-public-nacl" --query "NetworkAcls[0].NetworkAclId" --output text
aws ec2 delete-network-acl --network-acl-id $NaclId
Write-Host "Route table och NACL borta"

# 5. Internet gateway: lossa från VPC:t, sedan ta bort
$IgwId = aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=novatrix-igw" --query "InternetGateways[0].InternetGatewayId" --output text
aws ec2 detach-internet-gateway --internet-gateway-id $IgwId --vpc-id $VpcId
aws ec2 delete-internet-gateway --internet-gateway-id $IgwId
Write-Host "Internet gateway borta"

# 6. Sist själva VPC:t
aws ec2 delete-vpc --vpc-id $VpcId
Write-Host ""
Write-Host "Klart. Nätverket och servrarna från v44 är rivna. IAM och bucketar från v43 står kvar."
