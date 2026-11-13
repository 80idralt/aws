#!/bin/bash
# Novatrix v46: loads a backup into a newly built environment.
# Run on novatrix-web:  bash restore.sh wordpress-DATE.sql uploads-DATE.tgz
# The server role cannot read backups, so I fetch the files from S3 as admin
# and copy them here with scp first.
set -euo pipefail

DUMP="$1"
FILES="$2"
CONFIG=/var/www/html/wp-config.php

# The new server already wrote wp-config.php from the secret, read it from there
DB_HOST=$(sed -n "s/.*'DB_HOST', '\(.*\)'.*/\1/p" "$CONFIG")
export MYSQL_PWD=$(sed -n "s/.*'DB_PASSWORD', '\(.*\)'.*/\1/p" "$CONFIG")

# 1. The database. The dump creates all tables in the empty database.
mysql -h "$DB_HOST" -u admin wordpress < "$DUMP"

# 2. The images back to EFS, owned by the web server
sudo tar -xzf "$FILES" -C /var/www/html/wp-content
sudo chown -R apache:apache /var/www/html/wp-content/uploads

# 3. WordPress stores its own address in the database, also in the image links.
#    Swap the old server address for this one, otherwise visitors are sent there.
#    The new address comes from the instance metadata (IMDSv2 needs a token).
TOKEN=$(curl -sS -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
NEW="http://$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)"
OLD=$(mysql -N -h "$DB_HOST" -u admin wordpress -e "SELECT option_value FROM wp_options WHERE option_name='siteurl';")

mysql -h "$DB_HOST" -u admin wordpress -e "
  UPDATE wp_options SET option_value='$NEW' WHERE option_name IN ('siteurl','home');
  UPDATE wp_posts SET post_content=REPLACE(post_content,'$OLD','$NEW'), guid=REPLACE(guid,'$OLD','$NEW');"

echo "Bytte $OLD mot $NEW"
echo "Klart. Öppna $NEW"
