#!/bin/bash
# Novatrix v45: webbservern installerar WordPress och kopplar in EFS på wp-content.
# EFS_ID byts mot det riktiga id:t av deploy.ps1 innan servern startas.

# 1. Program: webbserver, PHP till WordPress, databasklient och EFS-verktyget
dnf install -y httpd php php-mysqlnd php-gd php-mbstring php-xml mariadb105 amazon-efs-utils

# 2. EFS på wp-content, via fstab så att den kopplas in vid varje omstart
mkdir -p /var/www/html/wp-content
echo "EFS_ID:/ /var/www/html/wp-content efs _netdev,noresvport,tls 0 0" >> /etc/fstab

# EFS-namnet kan ta en stund innan det går att slå upp. Försök upp till 10 gånger.
for i in 1 2 3 4 5 6 7 8 9 10; do
  mount -a && mountpoint -q /var/www/html/wp-content && break
  sleep 15
done

# 3. WordPress till webbroten. -n gör att filer som redan finns på EFS inte skrivs över.
cd /tmp
curl -sSLo latest.tar.gz https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -rn /tmp/wordpress/. /var/www/html/

# 4. apache äger filerna, sedan startar PHP och webbservern
chown -R apache:apache /var/www/html
systemctl enable --now php-fpm httpd
