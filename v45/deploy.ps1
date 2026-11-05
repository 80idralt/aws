# Novatrix v45 VG: bygger nätverket, databasen, EFS och WordPress från kod.
# Kräver: inloggad med "aws login", key pair novatrix-key, rollen och bucketarna från v43.

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$env:AWS_CLI_FILE_ENCODING = "UTF-8"

# Inställningar, det här är det man byter om man bygger i ett annat konto
$Nyckel    = "novatrix-key"
$Typ       = "t3.micro"
$Roll      = "novatrix-ec2-s3-read"
$Ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
$UserData  = Join-Path $PSScriptRoot "user-data.sh"
$DbKlass   = "db.t3.micro"
$DbGb      = 20
$DbMotor   = "11.4"
$Bucket    = "novatrix-backup-80idralt-01"
$Livscykel = Join-Path $PSScriptRoot "livscykel.json"

# Min IP just nu, för SSH
$MinIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()

# 1. VPC
$VpcId = aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text
aws ec2 create-tags --resources $VpcId --tags Key=Name,Value=novatrix-vpc
# DNS hostnames på, annars hittar webbservern inte EFS-namnet
aws ec2 modify-vpc-attribute --vpc-id $VpcId --enable-dns-hostnames
Write-Host "VPC skapat: $VpcId"

# 2. Subnät, ett publikt och två privata
$PublicId = aws ec2 create-subnet --vpc-id $VpcId --cidr-block 10.0.1.0/24 `
    --availability-zone eu-north-1a --query Subnet.SubnetId --output text
aws ec2 create-tags --resources $PublicId --tags Key=Name,Value=novatrix-public

$PrivAId = aws ec2 create-subnet --vpc-id $VpcId --cidr-block 10.0.2.0/24 `
    --availability-zone eu-north-1a --query Subnet.SubnetId --output text
aws ec2 create-tags --resources $PrivAId --tags Key=Name,Value=novatrix-private-a

$PrivBId = aws ec2 create-subnet --vpc-id $VpcId --cidr-block 10.0.4.0/24 `
    --availability-zone eu-north-1b --query Subnet.SubnetId --output text
aws ec2 create-tags --resources $PrivBId --tags Key=Name,Value=novatrix-private-b
Write-Host "Subnät skapade"

# 3. Internet gateway, skapa och koppla till VPC:t
$IgwId = aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text
aws ec2 create-tags --resources $IgwId --tags Key=Name,Value=novatrix-igw
aws ec2 attach-internet-gateway --internet-gateway-id $IgwId --vpc-id $VpcId
Write-Host "Internet gateway skapad och kopplad: $IgwId"

# 4. Route table med väg ut, bara för det publika subnätet
$RtId = aws ec2 create-route-table --vpc-id $VpcId --query RouteTable.RouteTableId --output text
aws ec2 create-tags --resources $RtId --tags Key=Name,Value=novatrix-public-rt
aws ec2 create-route --route-table-id $RtId --destination-cidr-block 0.0.0.0/0 --gateway-id $IgwId | Out-Null
aws ec2 associate-route-table --route-table-id $RtId --subnet-id $PublicId | Out-Null
Write-Host "Route table skapad och kopplad till novatrix-public"

# 5. Security groups. Bastion först, eftersom webben pekar på den.
$BastionSg = aws ec2 create-security-group --group-name novatrix-bastion-sg `
    --description "SSH fran min IP" --vpc-id $VpcId --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $BastionSg --protocol tcp --port 22 --cidr "$MinIp/32" | Out-Null

$WebSg = aws ec2 create-security-group --group-name novatrix-web-sg `
    --description "Webb fran alla, SSH bara fran bastion" --vpc-id $VpcId --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $WebSg --protocol tcp --port 80 --cidr 0.0.0.0/0 | Out-Null
aws ec2 authorize-security-group-ingress --group-id $WebSg --protocol tcp --port 443 --cidr 0.0.0.0/0 | Out-Null
aws ec2 authorize-security-group-ingress --group-id $WebSg --protocol tcp --port 22 --source-group $BastionSg | Out-Null

$DbSg = aws ec2 create-security-group --group-name novatrix-db-sg `
    --description "MySQL bara fran webben" --vpc-id $VpcId --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $DbSg --protocol tcp --port 3306 --source-group $WebSg | Out-Null

$EfsSg = aws ec2 create-security-group --group-name novatrix-efs-sg `
    --description "NFS bara fran webben" --vpc-id $VpcId --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $EfsSg --protocol tcp --port 2049 --source-group $WebSg | Out-Null
Write-Host "Security groups skapade: bastion, web, db och efs"

# 6. NACL för det publika subnätet, regler åt båda håll
$NaclId = aws ec2 create-network-acl --vpc-id $VpcId --query NetworkAcl.NetworkAclId --output text
aws ec2 create-tags --resources $NaclId --tags Key=Name,Value=novatrix-public-nacl

# In
aws ec2 create-network-acl-entry --network-acl-id $NaclId --ingress --rule-number 100 --protocol tcp --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --ingress --rule-number 110 --protocol tcp --port-range From=443,To=443 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --ingress --rule-number 120 --protocol tcp --port-range From=22,To=22 --cidr-block "$MinIp/32" --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --ingress --rule-number 130 --protocol tcp --port-range From=1024,To=65535 --cidr-block 0.0.0.0/0 --rule-action allow

# Ut
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 100 --protocol tcp --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 110 --protocol tcp --port-range From=443,To=443 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 120 --protocol tcp --port-range From=1024,To=65535 --cidr-block 0.0.0.0/0 --rule-action allow

# Ny i v45: webben ska nå databasen och EFS, men bara i de två privata subnäten.
# Inte hela 10.0.0.0/16 (då ingår det publika subnätet) och aldrig internet.
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 140 --protocol tcp --port-range From=3306,To=3306 --cidr-block 10.0.2.0/24 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 141 --protocol tcp --port-range From=3306,To=3306 --cidr-block 10.0.4.0/24 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 150 --protocol tcp --port-range From=2049,To=2049 --cidr-block 10.0.2.0/24 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id $NaclId --egress --rule-number 151 --protocol tcp --port-range From=2049,To=2049 --cidr-block 10.0.4.0/24 --rule-action allow

# Byt ut standard-NACL:en på det publika subnätet mot vår
$KopplingId = aws ec2 describe-network-acls `
    --filters "Name=association.subnet-id,Values=$PublicId" `
    --query "NetworkAcls[0].Associations[?SubnetId=='$PublicId'].NetworkAclAssociationId" `
    --output text
aws ec2 replace-network-acl-association --association-id $KopplingId --network-acl-id $NaclId | Out-Null
Write-Host "NACL skapad och kopplad till novatrix-public"

# 7. Databasen. Först listan med rum den får bo i, bara de privata.
aws rds create-db-subnet-group --db-subnet-group-name novatrix-db-subnets `
    --db-subnet-group-description "Privata subnat for databasen" `
    --subnet-ids $PrivAId $PrivBId | Out-Null

# Lösenordet skapas och sparas i Secrets Manager, det står aldrig i koden.
# Backup 1 dag är max på Free plan, 14 dagar sparas i S3 i stället.
aws rds create-db-instance --db-instance-identifier novatrix-db `
    --engine mariadb --engine-version $DbMotor `
    --db-instance-class $DbKlass --allocated-storage $DbGb `
    --storage-type gp2 --storage-encrypted `
    --master-username admin --manage-master-user-password `
    --db-name wordpress `
    --db-subnet-group-name novatrix-db-subnets --vpc-security-group-ids $DbSg `
    --availability-zone eu-north-1a --no-multi-az --no-publicly-accessible `
    --backup-retention-period 1 --no-deletion-protection | Out-Null
Write-Host "Databasen novatrix-db skapas, tar cirka 10 minuter. Vi fortsätter så länge."

# 8. EFS, den delade disken för wp-content. Krypterad, Bursting, ingen extra backup.
$EfsId = aws efs create-file-system `
    --performance-mode generalPurpose --throughput-mode bursting `
    --encrypted --no-backup --tags Key=Name,Value=novatrix-efs `
    --query FileSystemId --output text
Write-Host "EFS skapad: $EfsId, väntar på att den blir klar..."

# AWS har inget wait-kommando för EFS, så vi frågar var 5:e sekund
do {
    Start-Sleep -Seconds 5
    $Lage = aws efs describe-file-systems --file-system-id $EfsId `
        --query "FileSystems[0].LifeCycleState" --output text
} while ($Lage -ne "available")

# Ett uttag i varje privat subnät, med efs-sg som vakt
aws efs create-mount-target --file-system-id $EfsId --subnet-id $PrivAId --security-groups $EfsSg | Out-Null
aws efs create-mount-target --file-system-id $EfsId --subnet-id $PrivBId --security-groups $EfsSg | Out-Null
Write-Host "Mount targets skapade, väntar på att båda blir klara..."

# Räkna hur många uttag som är klara, vänta tills det är 2
do {
    Start-Sleep -Seconds 10
    $Klara = aws efs describe-mount-targets --file-system-id $EfsId `
        --query "length(MountTargets[?LifeCycleState=='available'])" --output text
} while ($Klara -ne "2")
Write-Host "EFS klar med uttag i private-a och private-b"

# 9. Backup-bucketen finns sedan v43. Här får den regeln som tar bort backuper efter 14 dagar.
aws s3api put-bucket-lifecycle-configuration --bucket $Bucket --lifecycle-configuration "file://$Livscykel"
Write-Host "Livscykelregel backup-14-dagar satt på $Bucket"

# 10. Servrarna. Webben får rollen från v43 och user data som installerar WordPress.
# user-data.sh har EFS_ID som platshållare.
# Byt till det riktiga id:t och spara en färdig kopia.
# Radbrytningarna görs om till Linux-stil, så att det fungerar även om filen sparats i Windows.
$Skript = (Get-Content $UserData -Raw).Replace("EFS_ID", $EfsId).Replace("`r`n", "`n")
$UserDataKlar = Join-Path $env:TEMP "novatrix-user-data.sh"
Set-Content -Path $UserDataKlar -Value $Skript -NoNewline

$WebId = aws ec2 run-instances --image-id $Ami --instance-type $Typ --key-name $Nyckel `
    --subnet-id $PublicId --security-group-ids $WebSg --associate-public-ip-address `
    --iam-instance-profile Name=$Roll --user-data "file://$UserDataKlar" `
    --query "Instances[0].InstanceId" --output text
aws ec2 create-tags --resources $WebId `
    --tags Key=Name,Value=novatrix-web Key=Project,Value=novatrix

# Bastion: ingen roll och ingen user data, den ska bara vara en dörr
$BastionId = aws ec2 run-instances --image-id $Ami --instance-type $Typ --key-name $Nyckel `
    --subnet-id $PublicId --security-group-ids $BastionSg --associate-public-ip-address `
    --query "Instances[0].InstanceId" --output text
aws ec2 create-tags --resources $BastionId `
    --tags Key=Name,Value=novatrix-bastion Key=Project,Value=novatrix
Write-Host "Servrar startade, väntar på att de ska köra..."

aws ec2 wait instance-running --instance-ids $WebId $BastionId

$WebIp     = aws ec2 describe-instances --instance-ids $WebId --query "Reservations[0].Instances[0].PublicIpAddress" --output text
$WebPrivat = aws ec2 describe-instances --instance-ids $WebId --query "Reservations[0].Instances[0].PrivateIpAddress" --output text
$BastionIp = aws ec2 describe-instances --instance-ids $BastionId --query "Reservations[0].Instances[0].PublicIpAddress" --output text

# 11. Databasen startades i avsnitt 7. Nu väntar vi in den och hämtar adressen.
Write-Host "Väntar på databasen, det kan ta några minuter till..."
aws rds wait db-instance-available --db-instance-identifier novatrix-db
$DbAdress = aws rds describe-db-instances --db-instance-identifier novatrix-db `
    --query "DBInstances[0].Endpoint.Address" --output text
$HemligArn = aws rds describe-db-instances --db-instance-identifier novatrix-db `
    --query "DBInstances[0].MasterUserSecret.SecretArn" --output text

Write-Host ""
Write-Host "Klart."
Write-Host "Webbsidan:  http://$WebIp (user data behöver 1-2 minuter till)"
Write-Host "Bastion:    $BastionIp"
Write-Host "Webbens privata IP, nås via bastion: $WebPrivat"
Write-Host "Databasens endpoint: $DbAdress"
Write-Host "Databaslösenordet (användare admin) hämtar du med:"
$Kommando = "(aws secretsmanager get-secret-value --secret-id $HemligArn" +
    " --query SecretString --output text | ConvertFrom-Json).password"
Write-Host "  $Kommando"
