#!/bin/bash
# Novatrix v46: backup of the database and the uploaded files to S3.
# Run on novatrix-web:  bash backup.sh
# Address and password are read from wp-config.php, so nobody types them.
set -euo pipefail

BUCKET="novatrix-backup-80idralt-01"
REGION="eu-north-1"
CONFIG=/var/www/html/wp-config.php
STAMP=$(date +%F-%H%M)
DUMP="/tmp/wordpress-$STAMP.sql"
FILES="/tmp/uploads-$STAMP.tgz"

# Always remove the copies from the server when we are done
trap 'rm -f "$DUMP" "$FILES"' EXIT

# MYSQL_PWD keeps the password off the command line and out of the history
DB_HOST=$(sed -n "s/.*'DB_HOST', '\(.*\)'.*/\1/p" "$CONFIG")
export MYSQL_PWD=$(sed -n "s/.*'DB_PASSWORD', '\(.*\)'.*/\1/p" "$CONFIG")

# 1. The database: posts, pages and users
mysqldump --single-transaction -h "$DB_HOST" -u admin wordpress > "$DUMP"

# 2. The images live on EFS, not in the database, so they need their own copy
tar -czf "$FILES" -C /var/www/html/wp-content uploads

# 3. To S3. The role may only put files in backup/, not read or delete them,
#    so a hacked server cannot get at old backups.
aws s3 cp "$DUMP" "s3://$BUCKET/backup/" --region "$REGION"
aws s3 cp "$FILES" "s3://$BUCKET/backup/" --region "$REGION"
echo "Klart: $(basename "$DUMP") och $(basename "$FILES") ligger i s3://$BUCKET/backup/"
