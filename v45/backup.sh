#!/bin/bash
# Novatrix v45: backup av databasen till S3, med datum och tid i filnamnet.
# Körs på webbservern:  bash backup.sh <rds-endpoint>
# Lösenordet frågas efter när mysqldump körs. Det står aldrig i filen.

BUCKET="novatrix-backup-80idralt-01"
ENDPOINT="$1"
FIL="/tmp/wordpress-$(date +%F-%H%M).sql"

if [ -z "$ENDPOINT" ]; then
  echo "Ange databasens endpoint: bash backup.sh <rds-endpoint>"
  exit 1
fi

# Sluta direkt om något steg misslyckas. Ta alltid bort dumpen från servern på slutet.
set -e
trap 'rm -f "$FIL"' EXIT

# 1. Profilen backup lånar rollen novatrix-backup-write från v43.
#    Den rollen får bara lägga filer i backup/, inte läsa eller radera.
if ! grep -q "profile backup" ~/.aws/config 2>/dev/null; then
  KONTO=$(aws sts get-caller-identity --query Account --output text)
  mkdir -p ~/.aws
  cat >> ~/.aws/config <<EOF
[profile backup]
role_arn = arn:aws:iam::${KONTO}:role/novatrix-backup-write
credential_source = Ec2InstanceMetadata
region = eu-north-1
EOF
  echo "Profilen backup skapad"
fi

# 2. Kopia av hela databasen wordpress
mysqldump --single-transaction -h "$ENDPOINT" -u admin -p wordpress > "$FIL"
echo "Dump klar: $FIL ($(du -h "$FIL" | cut -f1))"

# 3. Till S3 med den lånade rollen
aws s3 cp "$FIL" "s3://$BUCKET/backup/" --profile backup
echo "Klart. Filen ligger under backup/ och tas bort av livscykelregeln efter 14 dagar."
