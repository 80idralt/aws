# Novatrix v42 VG: bygger hela miljön från kod.
# Kräver: inloggad med "aws login", key pair novatrix-key finns i kontot.

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$env:AWS_CLI_FILE_ENCODING = "UTF-8"

# Inställningar
$Namn     = "novatrix-web"
$SgNamn   = "novatrix-web-sg"
$Nyckel   = "novatrix-key"
$Typ      = "t3.micro"
$Ami      = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
$UserData = Join-Path $PSScriptRoot "user-data.sh"
$Taggar   = "{Key=Name,Value=$Namn},{Key=Project,Value=novatrix}"

# 1. Stoppa om miljön redan finns
$Finns = aws ec2 describe-security-groups --filters "Name=group-name,Values=$SgNamn" --query "SecurityGroups[0].GroupId" --output text
if ($Finns -ne "None") {
    Write-Host "$SgNamn finns redan. Kör destroy.ps1 först."
    exit 1
}

# 2. Security group: SSH bara från min IP just nu, HTTP från alla
$MinIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()
$SgId = aws ec2 create-security-group --group-name $SgNamn `
    --description "SSH fran min IP, HTTP fran alla" `
    --tag-specifications "ResourceType=security-group,Tags=[$Taggar]" `
    --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $SgId --protocol tcp --port 22 --cidr "$MinIp/32" | Out-Null
aws ec2 authorize-security-group-ingress --group-id $SgId --protocol tcp --port 80 --cidr "0.0.0.0/0" | Out-Null
Write-Host "Security group $SgNamn skapad ($SgId)"

# 3. Starta instansen med user data
$InstansId = aws ec2 run-instances `
    --image-id $Ami `
    --instance-type $Typ `
    --key-name $Nyckel `
    --security-group-ids $SgId `
    --user-data "file://$UserData" `
    --tag-specifications "ResourceType=instance,Tags=[$Taggar]" `
    --query "Instances[0].InstanceId" --output text
Write-Host "Instans $InstansId startad, väntar på att den ska köra..."

# 4. Vänta tills den kör och hämta den publika IP:n
aws ec2 wait instance-running --instance-ids $InstansId
$Ip = aws ec2 describe-instances --instance-ids $InstansId `
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text

Write-Host ""
Write-Host "Klart. Sidan finns på http://$Ip"
Write-Host "User data behöver 1-2 minuter till innan sidan svarar."
